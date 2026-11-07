-- tb_argmax.vhd
-- Testbench auto-verifiant pour argmax.vhd : lit des vecteurs (10 scores +
-- indice attendu) generes par python/gen_vectors.py, y compris des cas
-- d'egalite, et verifie que digit correspond.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use work.argmax_pkg.all;

entity tb_argmax is
end entity tb_argmax;

architecture sim of tb_argmax is
  constant VECTORS_FILE : string := "data/vectors/argmax_vectors.txt";

  signal scores : score_array := (others => (others => '0'));
  signal digit  : unsigned(3 downto 0);
begin

  uut : entity work.argmax
    port map (scores => scores, digit => digit);

  stim_process : process
    file vecfile : text open read_mode is VECTORS_FILE;
    variable line_v : line;
    variable val_i : integer;
    variable expected_i : integer;
    variable n_tests, n_fail : natural := 0;
  begin
    while not endfile(vecfile) loop
      readline(vecfile, line_v);
      for i in 0 to 9 loop
        read(line_v, val_i);
        scores(i) <= to_signed(val_i, 32);
      end loop;
      read(line_v, expected_i);

      wait for 1 ns;  -- laisser le process combinatoire se stabiliser

      n_tests := n_tests + 1;
      if to_integer(digit) /= expected_i then
        n_fail := n_fail + 1;
        report "ECHEC vecteur " & integer'image(n_tests) &
               " : attendu=" & integer'image(expected_i) &
               " obtenu=" & integer'image(to_integer(digit))
          severity error;
      end if;
    end loop;

    if n_fail = 0 then
      report "tb_argmax : " & integer'image(n_tests) &
             " vecteurs, tous corrects." severity note;
    else
      report "tb_argmax : " & integer'image(n_fail) & "/" &
             integer'image(n_tests) & " ECHECS." severity error;
    end if;

    wait;
  end process;

end architecture sim;
