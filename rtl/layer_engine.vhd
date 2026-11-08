-- layer_engine.vhd
-- Assemble le controleur (controller_fsm), l'unite MAC (mac_unit) et le
-- bloc ReLU + remise a l'echelle (relu_requant) pour calculer une couche
-- complete : N_HIDDEN neurones, chacun somme de N_IN produits + biais.
--
-- Reutilisable tel quel pour la couche 2 (etape 4) en changeant les
-- generiques N_IN/N_HIDDEN et en branchant les bonnes ROM/RAM/M/S a
-- l'exterieur. out_data (8 bits, ReLU+sature) sert pour une couche cachee ;
-- out_data_raw (32 bits, brut) sert pour une couche de sortie sans ReLU.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity layer_engine is
  generic (
    N_IN     : positive;
    N_HIDDEN : positive;
    M_WIDTH  : positive := 16
  );
  port (
    clk   : in  std_logic;
    rst   : in  std_logic;
    start : in  std_logic;
    busy  : out std_logic;
    done  : out std_logic;

    -- lecture des entrees (image_ram ou act_ram selon la couche)
    in_addr : out natural range 0 to N_IN - 1;
    in_data : in  signed(7 downto 0);

    -- lecture des poids (region W1 ou W2 de weight_rom)
    w_addr : out natural range 0 to N_IN * N_HIDDEN - 1;
    w_data : in  signed(7 downto 0);

    -- lecture des biais (region B1 ou B2 de weight_rom)
    b_addr : out natural range 0 to N_HIDDEN - 1;
    b_data : in  signed(31 downto 0);

    -- remise a l'echelle (M1/S1 ou M2/S2)
    m : in unsigned(M_WIDTH - 1 downto 0);
    s : in natural range 0 to 31;

    -- ecriture des resultats (act_ram, ou registres de scores pour la sortie)
    out_we       : out std_logic;
    out_addr     : out natural range 0 to N_HIDDEN - 1;
    out_data     : out signed(7 downto 0);     -- ReLU + sature [0,127]
    out_data_raw : out signed(31 downto 0)     -- accumulateur brut (scores)
  );
end entity layer_engine;

architecture rtl of layer_engine is
  signal mac_clear : std_logic;
  signal mac_en    : std_logic;
  signal mac_acc   : signed(31 downto 0);
  signal q_requant : signed(7 downto 0);
begin

  ctrl : entity work.controller_fsm
    generic map (
      N_IN     => N_IN,
      N_HIDDEN => N_HIDDEN
    )
    port map (
      clk => clk, rst => rst, start => start, busy => busy, done => done,
      in_addr => in_addr, w_addr => w_addr, b_addr => b_addr,
      mac_clear => mac_clear, mac_en => mac_en,
      out_we => out_we, out_addr => out_addr
    );

  mac : entity work.mac_unit
    port map (
      clk => clk, rst => rst, clear => mac_clear, en => mac_en,
      w => w_data, x => in_data, bias => b_data, acc => mac_acc
    );

  req : entity work.relu_requant
    generic map (M_WIDTH => M_WIDTH)
    port map (acc => mac_acc, m => m, s => s, q => q_requant);

  out_data     <= q_requant;
  out_data_raw <= mac_acc;

end architecture rtl;
