-- tb_mac_unit.vhd
-- Testbench auto-verifiant pour mac_unit.vhd : lit des vecteurs
-- (w, x, bias, resultat attendu) generes par python/gen_vectors.py et
-- verifie, pour chacun, que acc = bias + w*x apres un clear puis un en.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb_mac_unit is
end entity tb_mac_unit;

architecture sim of tb_mac_unit is
  constant CLK_PERIOD   : time := 10 ns;
  constant VECTORS_FILE : string := "data/vectors/mac_vectors.txt";

  signal clk   : std_logic := '0';
  signal rst   : std_logic := '1';
  signal clear : std_logic := '0';
  signal en    : std_logic := '0';
  signal w     : signed(7 downto 0)  := (others => '0');
  signal x     : signed(7 downto 0)  := (others => '0');
  signal bias  : signed(31 downto 0) := (others => '0');
  signal acc   : signed(31 downto 0);

  signal sim_done : boolean := false;
begin

  clk_process : process
  begin
    while not sim_done loop
      clk <= '0'; wait for CLK_PERIOD / 2;
      clk <= '1'; wait for CLK_PERIOD / 2;
    end loop;
    wait;
  end process;

  uut : entity work.mac_unit
    port map (
      clk => clk, rst => rst, clear => clear, en => en,
      w => w, x => x, bias => bias, acc => acc
    );

  stim_process : process
    file vecfile : text open read_mode is VECTORS_FILE;
    variable line_v : line;
    variable w_i, x_i, bias_i, expected_i : integer;
    variable n_tests, n_fail : natural := 0;
  begin
    rst <= '1';
    wait until rising_edge(clk);
    wait for 1 ns;
    rst <= '0';

    while not endfile(vecfile) loop
      readline(vecfile, line_v);
      read(line_v, w_i);
      read(line_v, x_i);
      read(line_v, bias_i);
      read(line_v, expected_i);

      w    <= to_signed(w_i, 8);
      x    <= to_signed(x_i, 8);
      bias <= to_signed(bias_i, 32);

      clear <= '1'; en <= '0';
      wait until rising_edge(clk);
      clear <= '0';

      en <= '1';
      wait until rising_edge(clk);
      en <= '0';

      wait for 1 ns;
      n_tests := n_tests + 1;
      if to_integer(acc) /= expected_i then
        n_fail := n_fail + 1;
        report "ECHEC vecteur " & integer'image(n_tests) &
               " : w=" & integer'image(w_i) & " x=" & integer'image(x_i) &
               " bias=" & integer'image(bias_i) &
               " attendu=" & integer'image(expected_i) &
               " obtenu=" & integer'image(to_integer(acc))
          severity error;
      end if;
    end loop;

    if n_fail = 0 then
      report "tb_mac_unit : " & integer'image(n_tests) &
             " vecteurs, tous corrects." severity note;
    else
      report "tb_mac_unit : " & integer'image(n_fail) & "/" &
             integer'image(n_tests) & " ECHECS." severity error;
    end if;

    sim_done <= true;
    wait;
  end process;

end architecture sim;
