-- mlp_top_n.vhd
-- Variante de mlp_top.vhd (etape 4) parametree par N_MAC (etape 5,
-- parallelisme spatial). Meme interface externe que mlp_top.vhd (section
-- 3.6 du plan, + le port de debug scores_debug), meme architecture
-- generale (couche 1 -> couche 2 -> argmax), mais remplace layer_engine
-- (1 MAC) par mac_array (N_MAC MAC en parallele, etape 5) et weight_rom
-- (1 voie) par weight_rom_n (N_MAC voies). Avec N_MAC=1, ce circuit est
-- fonctionnellement identique a mlp_top.vhd.
--
-- mlp_top.vhd (etape 4, N_MAC=1 fige, interface officielle) n'est PAS
-- modifie : ce fichier est une variante d'EXPLORATION separee, pour
-- comparer les architectures sans risquer de casser ce qui est deja
-- valide. A l'etape 6, on choisira laquelle synthetiser.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.weights_pkg.all;
use work.argmax_pkg.all;
use work.parallel_pkg.all;

entity mlp_top_n is
  generic (
    N_MAC : positive := 1      -- nombre d'unites MAC en parallele, par couche
  );
  port (
    clk : in std_logic;
    rst : in std_logic;

    pix_we   : in std_logic;
    pix_addr : in natural range 0 to N_IN - 1;
    pix_data : in signed(7 downto 0);

    start : in  std_logic;
    busy  : out std_logic;
    done  : out std_logic;
    digit : out unsigned(3 downto 0);

    scores_debug : out score_array   -- port de debug, voir mlp_top.vhd
  );
end entity mlp_top_n;

architecture rtl of mlp_top_n is

  signal img_raddr : natural range 0 to N_IN - 1;
  signal img_rdata : signed(7 downto 0);

  signal act_we    : std_logic;
  signal act_waddr : natural range 0 to N_HIDDEN - 1;
  signal act_wdata : signed(7 downto 0);
  signal act_raddr : natural range 0 to N_HIDDEN - 1;
  signal act_rdata : signed(7 downto 0);

  signal w1_addr : addr_array_t(0 to N_MAC - 1);
  signal w1_data : data8_array_t(0 to N_MAC - 1);
  signal b1_addr : addr_array_t(0 to N_MAC - 1);
  signal b1_data : data32_array_t(0 to N_MAC - 1);
  signal w2_addr : addr_array_t(0 to N_MAC - 1);
  signal w2_data : data8_array_t(0 to N_MAC - 1);
  signal b2_addr : addr_array_t(0 to N_MAC - 1);
  signal b2_data : data32_array_t(0 to N_MAC - 1);

  signal start1, busy1, done1 : std_logic;
  signal start2, busy2, done2 : std_logic;
  signal out2_we       : std_logic;
  signal out2_addr     : natural range 0 to N_OUT - 1;
  signal out2_data_raw : signed(31 downto 0);

  signal score_regs : score_array := (others => (others => '0'));
  signal digit_i     : unsigned(3 downto 0);

  type top_state_t is (TOP_IDLE, TOP_WAIT1, TOP_WAIT2, TOP_DONE);
  signal top_state, top_next_state : top_state_t := TOP_IDLE;

begin

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

  weight_rom_inst : entity work.weight_rom_n
    generic map (N_PORTS => N_MAC)
    port map (
      clk => clk,
      w1_addr => w1_addr, w1_data => w1_data,
      b1_addr => b1_addr, b1_data => b1_data,
      w2_addr => w2_addr, w2_data => w2_data,
      b2_addr => b2_addr, b2_data => b2_data
    );

  -- couche 1 : 784 entrees -> 32 neurones, N_MAC voies en parallele
  layer1 : entity work.mac_array
    generic map (N_IN => N_IN, N_HIDDEN => N_HIDDEN, N_MAC => N_MAC, M_WIDTH => 16)
    port map (
      clk => clk, rst => rst, start => start1, busy => busy1, done => done1,
      in_addr => img_raddr, in_data => img_rdata,
      w_addr => w1_addr, w_data => w1_data,
      b_addr => b1_addr, b_data => b1_data,
      m => to_unsigned(M1_CONST, 16), s => S1_CONST,
      out_we => act_we, out_addr => act_waddr, out_data => act_wdata,
      out_data_raw => open
    );

  -- couche 2 : 32 entrees -> 10 sorties (scores bruts), N_MAC voies
  layer2 : entity work.mac_array
    generic map (N_IN => N_HIDDEN, N_HIDDEN => N_OUT, N_MAC => N_MAC, M_WIDTH => 16)
    port map (
      clk => clk, rst => rst, start => start2, busy => busy2, done => done2,
      in_addr => act_raddr, in_data => act_rdata,
      w_addr => w2_addr, w_data => w2_data,
      b_addr => b2_addr, b_data => b2_data,
      m => to_unsigned(1, 16), s => 0,   -- non utilises (pas de ReLU en sortie)
      out_we => out2_we, out_addr => out2_addr, out_data => open,
      out_data_raw => out2_data_raw
    );

  process (clk)
  begin
    if rising_edge(clk) then
      if out2_we = '1' then
        score_regs(out2_addr) <= out2_data_raw;
      end if;
    end if;
  end process;

  scores_debug <= score_regs;

  argmax_inst : entity work.argmax
    port map (scores => score_regs, digit => digit_i);

  digit <= digit_i;

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
