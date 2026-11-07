-- tb_counter.vhd
-- Testbench auto-verifiant pour counter.vhd (Etape 0).
-- Verifie : le compteur reste a 0 pendant le reset, puis vaut 10
-- apres 10 cycles d'horloge une fois le reset relache.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_counter is
end entity tb_counter;

architecture sim of tb_counter is
  constant CLK_PERIOD : time := 10 ns;

  signal clk   : std_logic := '0';
  signal rst   : std_logic := '1';
  signal count : std_logic_vector(7 downto 0);

  signal sim_done : boolean := false;
begin

  -- generation de l'horloge
  clk_process : process
  begin
    while not sim_done loop
      clk <= '0';
      wait for CLK_PERIOD / 2;
      clk <= '1';
      wait for CLK_PERIOD / 2;
    end loop;
    wait;
  end process;

  -- instance du module teste
  uut : entity work.counter
    port map (
      clk   => clk,
      rst   => rst,
      count => count
    );

  -- scenario de test
  stim_process : process
  begin
    rst <= '1';
    wait for CLK_PERIOD * 2;

    assert count = x"00"
      report "ECHEC : le compteur n'est pas a 0 pendant le reset"
      severity error;

    rst <= '0';
    for i in 1 to 10 loop
      wait until rising_edge(clk);
    end loop;
    wait for 1 ns;

    assert count = x"0A"
      report "ECHEC : le compteur devrait valoir 10 apres 10 cycles post-reset"
      severity error;

    report "tb_counter : tous les tests sont passes (compteur = 10 apres 10 cycles)." severity note;
    sim_done <= true;
    wait;
  end process;

end architecture sim;
