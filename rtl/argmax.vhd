-- argmax.vhd
-- Trouve l'indice du plus grand parmi 10 scores signes 32 bits.
-- En cas d'egalite, renvoie le plus petit indice (meme convention que
-- numpy.argmax, utilise par le modele de reference Python).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package argmax_pkg is
  type score_array is array (0 to 9) of signed(31 downto 0);
end package argmax_pkg;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.argmax_pkg.all;

entity argmax is
  port (
    scores : in  score_array;
    digit  : out unsigned(3 downto 0)
  );
end entity argmax;

architecture rtl of argmax is
begin

  process (scores)
    variable best_idx : integer range 0 to 9;
    variable best_val : signed(31 downto 0);
  begin
    best_idx := 0;
    best_val := scores(0);
    for i in 1 to 9 loop
      if scores(i) > best_val then
        best_val := scores(i);
        best_idx := i;
      end if;
    end loop;
    digit <= to_unsigned(best_idx, 4);
  end process;

end architecture rtl;
