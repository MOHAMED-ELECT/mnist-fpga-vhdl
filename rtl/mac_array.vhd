-- mac_array.vhd
-- Moteur de couche generique a N_MAC unites MAC en parallele (etape 5 :
-- parallelisme spatial). Assemble controller_fsm_n + N_MAC instances de
-- mac_unit (via for generate, une par voie) + UN SEUL bloc relu_requant
-- partage entre les voies (lu via un multiplexeur sel_lane pendant la
-- phase d'ecriture serialisee). Interface externe identique a
-- layer_engine.vhd (etape 3), a la difference que les ports poids/biais
-- sont desormais des tableaux a N_MAC voies (voir weight_rom_n.vhd) :
-- avec N_MAC=1, mac_array.vhd se comporte exactement comme
-- layer_engine.vhd.
--
-- "Le lien entre N MAC et le nombre de multiplieurs, donc la surface
-- occupee" (plan, etape 5) est directement visible ici : le generate
-- ci-dessous instancie N_MAC fois mac_unit, donc N_MAC multiplieurs
-- 8x8. Le multiplieur de relu_requant (acc * M), lui, N'EST PAS duplique
-- : un seul bloc suffit car l'ecriture des resultats est serialisee.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.parallel_pkg.all;

entity mac_array is
  generic (
    N_IN     : positive;
    N_HIDDEN : positive;
    N_MAC    : positive;
    M_WIDTH  : positive := 16
  );
  port (
    clk   : in  std_logic;
    rst   : in  std_logic;
    start : in  std_logic;
    busy  : out std_logic;
    done  : out std_logic;

    -- lecture des entrees (image_ram ou act_ram), partagee par les N_MAC voies
    in_addr : out natural range 0 to N_IN - 1;
    in_data : in  signed(7 downto 0);

    -- lecture des poids/biais : une voie par unite MAC (weight_rom_n)
    w_addr : out addr_array_t(0 to N_MAC - 1);
    w_data : in  data8_array_t(0 to N_MAC - 1);
    b_addr : out addr_array_t(0 to N_MAC - 1);
    b_data : in  data32_array_t(0 to N_MAC - 1);

    -- remise a l'echelle (M1/S1 ou M2/S2), commune a toutes les voies
    m : in unsigned(M_WIDTH - 1 downto 0);
    s : in natural range 0 to 31;

    -- ecriture des resultats : une voie a la fois (voir controller_fsm_n)
    out_we       : out std_logic;
    out_addr     : out natural range 0 to N_HIDDEN - 1;
    out_data     : out signed(7 downto 0);     -- ReLU + sature [0,127]
    out_data_raw : out signed(31 downto 0)     -- accumulateur brut (scores)
  );
end entity mac_array;

architecture rtl of mac_array is
  signal mac_clear : std_logic_vector(0 to N_MAC - 1);
  signal mac_en    : std_logic_vector(0 to N_MAC - 1);
  signal mac_acc   : data32_array_t(0 to N_MAC - 1);
  signal sel_lane  : natural range 0 to N_MAC - 1;
  signal acc_sel   : signed(31 downto 0);  -- mac_acc(sel_lane), indexation
                                             -- dynamique resolue ici (pas
                                             -- directement dans un port map)
  signal q_requant : signed(7 downto 0);
begin

  ctrl : entity work.controller_fsm_n
    generic map (
      N_IN     => N_IN,
      N_HIDDEN => N_HIDDEN,
      N_MAC    => N_MAC
    )
    port map (
      clk => clk, rst => rst, start => start, busy => busy, done => done,
      in_addr => in_addr,
      w_addr => w_addr, b_addr => b_addr,
      mac_clear => mac_clear, mac_en => mac_en,
      sel_lane => sel_lane,
      out_we => out_we, out_addr => out_addr
    );

  -- N_MAC unites MAC independantes, une par voie : c'est la ou le
  -- parallelisme (et le cout en multiplieurs) se voit directement.
  gen_mac : for l in 0 to N_MAC - 1 generate
    mac_l : entity work.mac_unit
      port map (
        clk => clk, rst => rst, clear => mac_clear(l), en => mac_en(l),
        w => w_data(l), x => in_data, bias => b_data(l), acc => mac_acc(l)
      );
  end generate gen_mac;

  acc_sel <= mac_acc(sel_lane);

  -- un seul relu_requant, partage entre les N_MAC voies via sel_lane
  -- (pilote par controller_fsm_n pendant WRITE_LANE)
  req : entity work.relu_requant
    generic map (M_WIDTH => M_WIDTH)
    port map (acc => acc_sel, m => m, s => s, q => q_requant);

  out_data     <= q_requant;
  out_data_raw <= acc_sel;

end architecture rtl;
