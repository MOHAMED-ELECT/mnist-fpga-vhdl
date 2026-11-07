-- tb_relu_requant.vhd
-- Testbench auto-verifiant pour relu_requant.vhd : lit des vecteurs
-- (acc, m, s, resultat attendu) generes par python/gen_vectors.py et
-- verifie que q = clip((acc*m) >> s, 0, 127).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb_relu_requant is
end entity tb_relu_requant;

architecture sim of tb_relu_requant is
  constant VECTORS_FILE : string := "data/vectors/relu_vectors.txt";

  signal acc : signed(31 downto 0) := (others => '0');
  signal m   : unsigned(15 downto 0) := (others => '0');
  signal s   : natural range 0 to 31 := 0;
  signal q   : signed(7 downto 0);
begin

  uut : entity work.relu_requant
    generic map (M_WIDTH => 16)
    port map (acc => acc, m => m, s => s, q => q);

  stim_process : process
    file vecfile : text open read_mode is VECTORS_FILE;
    variable line_v : line;
    variable acc_i, m_i, s_i, expected_i : integer;
    variable n_tests, n_fail : natural := 0;
  begin
    while not endfile(vecfile) loop
      readline(vecfile, line_v);
      read(line_v, acc_i);
      read(line_v, m_i);
      read(line_v, s_i);
      read(line_v, expected_i);

      acc <= to_signed(acc_i, 32);
      m   <= to_unsigned(m_i, 16);
      s   <= s_i;

      wait for 1 ns;  -- laisser le process combinatoire se stabiliser

      n_tests := n_tests + 1;
      if to_integer(q) /= expected_i then
        n_fail := n_fail + 1;
        report "ECHEC vecteur " & integer'image(n_tests) &
               " : acc=" & integer'image(acc_i) &
               " m=" & integer'image(m_i) &
               " s=" & integer'image(s_i) &
               " attendu=" & integer'image(expected_i) &
               " obtenu=" & integer'image(to_integer(q))
          severity error;
      end if;
    end loop;

    if n_fail = 0 then
      report "tb_relu_requant : " & integer'image(n_tests) &
             " vecteurs, tous corrects." severity note;
    else
      report "tb_relu_requant : " & integer'image(n_fail) & "/" &
             integer'image(n_tests) & " ECHECS." severity error;
    end if;

    wait;
  end process;

end architecture sim;
