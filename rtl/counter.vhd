-- counter.vhd
-- Compteur 8 bits avec reset synchrone.
-- Premiere brique du projet (Etape 0) : sert a valider la chaine
-- d'outils GHDL + GTKWave avant d'attaquer le reseau de neurones.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity counter is
  port (
    clk   : in  std_logic;
    rst   : in  std_logic;                      -- reset synchrone, actif haut
    count : out std_logic_vector(7 downto 0)
  );
end entity counter;

architecture rtl of counter is
  signal cnt : unsigned(7 downto 0) := (others => '0');
begin

  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        cnt <= (others => '0');
      else
        cnt <= cnt + 1;
      end if;
    end if;
  end process;

  count <= std_logic_vector(cnt);

end architecture rtl;
