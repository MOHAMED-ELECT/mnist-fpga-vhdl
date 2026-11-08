-- mlp_top.vhd
-- Circuit complet : reseau 784-32-10 (MNIST), couche 1 (ReLU+requant) puis
-- couche 2 (scores bruts) puis argmax. Reutilise layer_engine deux fois
-- (une instance par couche) et un petit sequenceur haut niveau pour
-- enchainer couche 1 -> couche 2 -> argmax (Figure 5 du plan).
--
-- Interface officielle (section 3.6 du plan) : clk, rst, pix_we, pix_addr,
-- pix_data, start, busy, done, digit. Un port supplementaire,
-- scores_debug, est ajoute UNIQUEMENT pour la verification : l'etape 4 du
-- plan exige de comparer les 10 scores bruts avec le modele Python (pas
-- seulement le chiffre predit), et ces scores ne font pas partie de
-- l'interface fonctionnelle. Ce port n'a pas vocation a etre synthetise
-- dans la version finale du circuit (etape 6) ; il ne sert qu'au
-- testbench tb_mlp_top.vhd.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.weights_pkg.all;
use work.argmax_pkg.all;

entity mlp_top is
  port (
    clk : in std_logic;
    rst : in std_logic;

    -- chargement d'une image, pixel par pixel, avant de lancer l'inference
    pix_we   : in std_logic;
    pix_addr : in natural range 0 to N_IN - 1;
    pix_data : in signed(7 downto 0);

    start : in  std_logic;                 -- impulsion : lance l'inference
    busy  : out std_logic;                 -- calcul en cours
    done  : out std_logic;                 -- impulsion : resultat pret
    digit : out unsigned(3 downto 0);      -- chiffre predit (valide quand done='1')

    -- port de debug (hors interface officielle, voir note ci-dessus)
    scores_debug : out score_array
  );
end entity mlp_top;

architecture rtl of mlp_top is

  -- image_ram (entree de la couche 1)
  signal img_raddr : natural range 0 to N_IN - 1;
  signal img_rdata : signed(7 downto 0);

  -- act_ram (sortie couche 1 / entree couche 2)
  signal act_we    : std_logic;
  signal act_waddr : natural range 0 to N_HIDDEN - 1;
  signal act_wdata : signed(7 downto 0);
  signal act_raddr : natural range 0 to N_HIDDEN - 1;
  signal act_rdata : signed(7 downto 0);

  -- weight_rom (poids/biais des deux couches)
  signal w1_addr : natural range 0 to N_IN * N_HIDDEN - 1;
  signal w1_data : signed(7 downto 0);
  signal b1_addr : natural range 0 to N_HIDDEN - 1;
  signal b1_data : signed(31 downto 0);
  signal w2_addr : natural range 0 to N_HIDDEN * N_OUT - 1;
  signal w2_data : signed(7 downto 0);
  signal b2_addr : natural range 0 to N_OUT - 1;
  signal b2_data : signed(31 downto 0);

  -- layer_engine #1 : couche 1 (784 -> 32, avec ReLU+requant)
  signal start1, busy1, done1 : std_logic;

  -- layer_engine #2 : couche 2 (32 -> 10, sortie brute, pas de ReLU)
  signal start2, busy2, done2  : std_logic;
  signal out2_we               : std_logic;
  signal out2_addr             : natural range 0 to N_OUT - 1;
  signal out2_data_raw         : signed(31 downto 0);

  -- registres des 10 scores bruts (sortie couche 2)
  signal score_regs : score_array := (others => (others => '0'));

  -- argmax (combinatoire)
  signal digit_i : unsigned(3 downto 0);

  -- sequenceur haut niveau : couche1 -> couche2 -> argmax (Figure 5)
  type top_state_t is (TOP_IDLE, TOP_WAIT1, TOP_WAIT2, TOP_DONE);
  signal top_state, top_next_state : top_state_t := TOP_IDLE;

begin

  -- ------------------------------------------------------------ memoires --
  img_ram_inst : entity work.image_ram
    generic map (DEPTH => N_IN)
    port map (
      clk => clk,
      we => pix_we, waddr => pix_addr, wdata => pix_data,
      raddr => img_raddr, rdata => img_rdata
    );

  act_ram_inst : entity work.act_ram
    generic map (DEPTH => N_HIDDEN)
    port map (
      clk => clk,
      we => act_we, waddr => act_waddr, wdata => act_wdata,
      raddr => act_raddr, rdata => act_rdata
    );

  weight_rom_inst : entity work.weight_rom
    port map (
      clk => clk,
      w1_addr => w1_addr, w1_data => w1_data,
      b1_addr => b1_addr, b1_data => b1_data,
      w2_addr => w2_addr, w2_data => w2_data,
      b2_addr => b2_addr, b2_data => b2_data
    );

  -- --------------------------------------------------------- couche 1 --
  -- 784 entrees (image_ram) -> 32 neurones caches (ReLU + requant M1/S1),
  -- ecrits dans act_ram.
  layer1 : entity work.layer_engine
    generic map (N_IN => N_IN, N_HIDDEN => N_HIDDEN, M_WIDTH => 16)
    port map (
      clk => clk, rst => rst, start => start1, busy => busy1, done => done1,
      in_addr => img_raddr, in_data => img_rdata,
      w_addr => w1_addr, w_data => w1_data,
      b_addr => b1_addr, b_data => b1_data,
      m => to_unsigned(M1_CONST, 16), s => S1_CONST,
      out_we => act_we, out_addr => act_waddr, out_data => act_wdata,
      out_data_raw => open
    );

  -- --------------------------------------------------------- couche 2 --
  -- 32 entrees (act_ram) -> 10 sorties (scores bruts, PAS de ReLU/requant :
  -- seul out_data_raw est utilise). Les generiques N_IN/N_HIDDEN de CETTE
  -- instance valent respectivement N_HIDDEN et N_OUT du reseau (32 et 10) :
  -- layer_engine est generique, on l'instancie une 2e fois avec d'autres
  -- tailles pour la couche de sortie.
  layer2 : entity work.layer_engine
    generic map (N_IN => N_HIDDEN, N_HIDDEN => N_OUT, M_WIDTH => 16)
    port map (
      clk => clk, rst => rst, start => start2, busy => busy2, done => done2,
      in_addr => act_raddr, in_data => act_rdata,
      w_addr => w2_addr, w_data => w2_data,
      b_addr => b2_addr, b_data => b2_data,
      m => to_unsigned(1, 16), s => 0,   -- non utilises (pas de ReLU en sortie)
      out_we => out2_we, out_addr => out2_addr, out_data => open,
      out_data_raw => out2_data_raw
    );

  -- registres des 10 scores bruts de la couche 2
  process (clk)
  begin
    if rising_edge(clk) then
      if out2_we = '1' then
        score_regs(out2_addr) <= out2_data_raw;
      end if;
    end if;
  end process;

  scores_debug <= score_regs;

  -- --------------------------------------------------------------- argmax --
  argmax_inst : entity work.argmax
    port map (scores => score_regs, digit => digit_i);

  digit <= digit_i;

  -- ------------------------------------------------- sequenceur haut niveau --
  -- IDLE -> (start) -> WAIT1 -> (done1) -> WAIT2 -> (done2) -> DONE -> IDLE
  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        top_state <= TOP_IDLE;
      else
        top_state <= top_next_state;
      end if;
    end if;
  end process;

  process (top_state, start, done1, done2)
  begin
    top_next_state <= top_state;
    start1 <= '0';
    start2 <= '0';
    done   <= '0';
    busy   <= '1';

    case top_state is

      when TOP_IDLE =>
        busy <= '0';
        if start = '1' then
          start1         <= '1';
          top_next_state <= TOP_WAIT1;
        end if;

      when TOP_WAIT1 =>
        if done1 = '1' then
          start2         <= '1';
          top_next_state <= TOP_WAIT2;
        end if;

      when TOP_WAIT2 =>
        if done2 = '1' then
          top_next_state <= TOP_DONE;
        end if;

      when TOP_DONE =>
        done           <= '1';
        top_next_state <= TOP_IDLE;

    end case;
  end process;

end architecture rtl;
