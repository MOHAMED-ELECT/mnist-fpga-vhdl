-- image_ram.vhd
-- Memoire a lecture et ecriture synchrones qui stocke les pixels d'une
-- image (784 entiers signes 8 bits, valeurs 0..127). Reutilisee avec une
-- profondeur differente pour act_ram (32 activations de la couche cachee).
--
-- Piege : la lecture est synchrone, donc rdata n'est valide qu'un cycle
-- APRES avoir presente raddr (voir controller_fsm.vhd).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity image_ram is
  generic (
    DEPTH : positive := 784
  );
  port (
    clk : in std_logic;

    -- port d'ecriture (chargement d'une image depuis l'exterieur)
    we    : in std_logic;
    waddr : in natural range 0 to DEPTH - 1;
    wdata : in signed(7 downto 0);

    -- port de lecture (consomme par layer_engine)
    raddr : in  natural range 0 to DEPTH - 1;
    rdata : out signed(7 downto 0)
  );
end entity image_ram;

architecture rtl of image_ram is
  type ram_t is array (0 to DEPTH - 1) of signed(7 downto 0);
  signal ram : ram_t := (others => (others => '0'));
begin

  process (clk)
  begin
    if rising_edge(clk) then
      if we = '1' then
        ram(waddr) <= wdata;
      end if;
      rdata <= ram(raddr);
    end if;
  end process;

end architecture rtl;
