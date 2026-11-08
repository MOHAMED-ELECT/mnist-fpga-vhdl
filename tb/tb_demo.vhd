-- tb_demo.vhd
-- Testbench d'une SEULE image, pour la demo de l'etape 7. Contrairement a
-- tb_mlp_top.vhd/tb_mlp_top_n.vhd (qui comparent a data/golden_outputs.txt
-- sur un lot d'images), ce testbench ne fait QUE charger une image, lancer
-- l'inference, mesurer les cycles, et ECRIRE LE RESULTAT dans un fichier
-- texte (RESULT_PATH) -- c'est demo/demo.py qui relit ce fichier et
-- l'affiche a l'ecran (idee de demo du plan, section "Etape 7" : "faire
-- ecrire les resultats du testbench dans un fichier texte, que Python
-- relit").
--
-- IMAGE_PATH pointe par defaut vers data/demo_image.hex, ecrit par
-- demo/demo.py juste avant de lancer GHDL (784 lignes hexadecimales,
-- meme format qu'un bloc de data/test_images.hex).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all;
use std.textio.all;
use work.weights_pkg.all;

entity tb_demo is
  generic (
    IMAGE_PATH  : string := "data/demo_image.hex";
    RESULT_PATH : string := "results/demo_result.txt"
  );
end entity tb_demo;

architecture sim of tb_demo is
  constant CLK_PERIOD : time := 10 ns;

  signal clk, rst : std_logic := '0';

  signal pix_we   : std_logic := '0';
  signal pix_addr : natural range 0 to N_IN - 1 := 0;
  signal pix_data : signed(7 downto 0) := (others => '0');

  signal start : std_logic := '0';
  signal busy  : std_logic;
  signal done  : std_logic;
  signal digit : unsigned(3 downto 0);

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

  -- mlp_top_synth (pas mlp_top) : exactement l'interface officielle de la
  -- section 3.6 du plan, la meme que celle qui serait synthetisee -- la
  -- demo doit piloter exactement ce que "verrait" une vraie carte FPGA.
  dut : entity work.mlp_top_synth
    port map (
      clk => clk, rst => rst,
      pix_we => pix_we, pix_addr => pix_addr, pix_data => pix_data,
      start => start, busy => busy, done => done, digit => digit
    );

  stim : process
    file img_file    : text open read_mode is IMAGE_PATH;
    file result_file : text open write_mode is RESULT_PATH;
    variable line_v    : line;
    variable out_line  : line;
    variable pixel_slv : std_logic_vector(7 downto 0);

    variable t_start, t_done : time;
    variable n_cycles        : natural;
  begin
    rst <= '1';
    wait until rising_edge(clk);
    wait for 1 ns;
    rst <= '0';

    -- charge l'unique image (784 pixels, lecture hexadecimale)
    for k in 0 to N_IN - 1 loop
      readline(img_file, line_v);
      hread(line_v, pixel_slv);
      pix_we   <= '1';
      pix_addr <= k;
      pix_data <= signed(pixel_slv);
      wait until rising_edge(clk);
    end loop;
    pix_we <= '0';

    -- lance l'inference et mesure les cycles (start -> done)
    t_start := now;
    start   <= '1';
    wait until rising_edge(clk);
    start   <= '0';

    wait until done = '1';
    t_done := now;
    n_cycles := (t_done - t_start) / CLK_PERIOD;
    wait for 1 ns;

    -- un seul resultat lisible par demo.py : "<chiffre> <cycles>"
    write(out_line, to_integer(digit));
    write(out_line, string'(" "));
    write(out_line, n_cycles);
    writeline(result_file, out_line);

    report "tb_demo : chiffre predit=" & integer'image(to_integer(digit)) &
           " cycles=" & integer'image(n_cycles);

    sim_done <= true;
    wait;
  end process;

end architecture sim;
