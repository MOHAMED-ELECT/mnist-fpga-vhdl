-- act_ram.vhd
-- Memoire des 32 activations de la couche cachee (sortie de la couche 1,
-- entree de la couche 2). Meme structure que image_ram, profondeur
-- differente (32 au lieu de 784) ; separee en deux fichiers pour rester
-- fidele au schema du plan (Figure 3 : image_ram et act_ram).
--
-- Piege : la lecture est synchrone, donc rdata n'est valide qu'un cycle
-- APRES avoir presente raddr.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity act_ram is
  generic (
    DEPTH : positive := 32
  );
  port (
    clk : in std_logic;

    we    : in std_logic;
    waddr : in natural range 0 to DEPTH - 1;
    wdata : in signed(7 downto 0);

    raddr : in  natural range 0 to DEPTH - 1;
    rdata : out signed(7 downto 0)
  );
end entity act_ram;

architecture rtl of act_ram is
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
