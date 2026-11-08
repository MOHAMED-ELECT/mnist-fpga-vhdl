-- weight_rom.vhd
-- Memoire morte (lecture synchrone) contenant les poids et biais des deux
-- couches, initialisee a partir des constantes de weights_pkg.vhd (genere
-- par python/gen_vhdl_pkg.py a partir des poids quantifies en Python).
--
-- Piege : la lecture est synchrone, donc *_data n'est valide qu'un cycle
-- APRES avoir presente *_addr (voir controller_fsm.vhd).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.weights_pkg.all;

entity weight_rom is
  port (
    clk : in std_logic;

    -- couche 1 (784 entrees -> 32 neurones)
    w1_addr : in  natural range 0 to N_IN * N_HIDDEN - 1;
    w1_data : out signed(7 downto 0);
    b1_addr : in  natural range 0 to N_HIDDEN - 1;
    b1_data : out signed(31 downto 0);

    -- couche 2 (32 entrees -> 10 sorties)
    w2_addr : in  natural range 0 to N_HIDDEN * N_OUT - 1;
    w2_data : out signed(7 downto 0);
    b2_addr : in  natural range 0 to N_OUT - 1;
    b2_data : out signed(31 downto 0)
  );
end entity weight_rom;

architecture rtl of weight_rom is
begin

  process (clk)
  begin
    if rising_edge(clk) then
      w1_data <= to_signed(W1_ROM(w1_addr), 8);
      b1_data <= to_signed(B1_ROM(b1_addr), 32);
      w2_data <= to_signed(W2_ROM(w2_addr), 8);
      b2_data <= to_signed(B2_ROM(b2_addr), 32);
    end if;
  end process;

end architecture rtl;
