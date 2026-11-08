-- tb_mlp_top_n.vhd
-- Testbench parametre (N_MAC, N_IMAGES) pour mlp_top_n.vhd (etape 5). Pour
-- chaque image : charge les pixels, lance l'inference, verifie les 10
-- scores bruts et le chiffre contre data/golden_outputs.txt (meme
-- reference que l'etape 4 -- l'architecture change, pas le resultat
-- attendu), ET mesure le nombre de cycles d'horloge entre l'impulsion
-- start et l'impulsion done (hors chargement des pixels, pour comparer
-- directement a la formule theorique de la Figure 7 du plan).
--
-- A la fin, imprime UNE ligne "RESULAT ..." facile a extraire avec
-- grep/awk (utilisee par scripts/run_sweep.sh pour remplir
-- results/results.csv).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all;
use std.textio.all;
use work.weights_pkg.all;
use work.argmax_pkg.all;

entity tb_mlp_top_n is
  generic (
    N_MAC    : positive := 1;
    N_IMAGES : positive := 20
  );
end entity tb_mlp_top_n;

architecture sim of tb_mlp_top_n is
  constant CLK_PERIOD : time := 10 ns;

  constant IMAGES_PATH : string := "data/test_images.hex";
  constant GOLDEN_PATH : string := "data/golden_outputs.txt";

  signal clk, rst : std_logic := '0';

  signal pix_we   : std_logic := '0';
  signal pix_addr : natural range 0 to N_IN - 1 := 0;
  signal pix_data : signed(7 downto 0) := (others => '0');

  signal start : std_logic := '0';
  signal busy  : std_logic;
  signal done  : std_logic;
  signal digit : unsigned(3 downto 0);

  signal scores_debug : score_array;

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

  dut : entity work.mlp_top_n
    generic map (N_MAC => N_MAC)
    port map (
      clk => clk, rst => rst,
      pix_we => pix_we, pix_addr => pix_addr, pix_data => pix_data,
      start => start, busy => busy, done => done, digit => digit,
      scores_debug => scores_debug
    );

  stim : process
    file img_file    : text open read_mode is IMAGES_PATH;
    file golden_file : text open read_mode is GOLDEN_PATH;
    variable line_v     : line;
    variable pixel_slv  : std_logic_vector(7 downto 0);

    variable idx_i, label_i, predicted_i : integer;
    variable score_i : integer;

    variable n_img_done     : natural := 0;
    variable n_score_fail   : natural := 0;
    variable n_digit_vs_ref : natural := 0;
    variable n_correct      : natural := 0;
    variable any_mismatch   : boolean;

    variable t_start, t_done : time;
    variable n_cycles        : natural;
    variable total_cycles    : natural := 0;
  begin
    rst <= '1';
    wait until rising_edge(clk);
    wait for 1 ns;
    rst <= '0';

    readline(golden_file, line_v);  -- en-tete

    for img_idx in 0 to N_IMAGES - 1 loop

      for k in 0 to N_IN - 1 loop
        readline(img_file, line_v);
        hread(line_v, pixel_slv);
        pix_we   <= '1';
        pix_addr <= k;
        pix_data <= signed(pixel_slv);
        wait until rising_edge(clk);
      end loop;
      pix_we <= '0';

      -- mesure du nombre de cycles de l'inference seule (hors chargement
      -- des pixels), pour comparer directement a la Figure 7 du plan
      t_start := now;
      start   <= '1';
      wait until rising_edge(clk);
      start   <= '0';

      wait until done = '1';
      t_done := now;
      n_cycles     := (t_done - t_start) / CLK_PERIOD;
      total_cycles := total_cycles + n_cycles;
      wait for 1 ns;

      readline(golden_file, line_v);
      read(line_v, idx_i);
      read(line_v, label_i);
      read(line_v, predicted_i);

      any_mismatch := false;
      for k in 0 to 9 loop
        read(line_v, score_i);
        if to_integer(scores_debug(k)) /= score_i then
          any_mismatch := true;
          report "ECHEC image " & integer'image(img_idx) &
                 " score[" & integer'image(k) & "] : attendu=" &
                 integer'image(score_i) & " obtenu=" &
                 integer'image(to_integer(scores_debug(k)))
            severity error;
        end if;
      end loop;

      n_img_done := n_img_done + 1;
      if any_mismatch then
        n_score_fail := n_score_fail + 1;
      end if;

      if to_integer(digit) /= predicted_i then
        n_digit_vs_ref := n_digit_vs_ref + 1;
        report "ECHEC image " & integer'image(img_idx) &
               " digit : reference Python=" & integer'image(predicted_i) &
               " materiel=" & integer'image(to_integer(digit))
          severity error;
      end if;

      if to_integer(digit) = label_i then
        n_correct := n_correct + 1;
      end if;

    end loop;

    report "tb_mlp_top_n : N_MAC=" & integer'image(N_MAC) & " " &
           integer'image(n_img_done) & " images testees.";
    report "  images avec un ecart sur les scores : " & integer'image(n_score_fail);
    report "  images avec digit != reference Python : " & integer'image(n_digit_vs_ref);
    report "  cycles moyens par image (start->done) : " &
           integer'image(total_cycles / n_img_done);

    -- ligne facile a extraire par scripts/run_sweep.sh (grep "RESULAT")
    report "RESULAT N_MAC=" & integer'image(N_MAC) &
           " N_IMAGES=" & integer'image(n_img_done) &
           " CYCLES_AVG=" & integer'image(total_cycles / n_img_done) &
           " SCORE_FAIL=" & integer'image(n_score_fail) &
           " DIGIT_FAIL=" & integer'image(n_digit_vs_ref);

    if n_score_fail = 0 and n_digit_vs_ref = 0 then
      report "tb_mlp_top_n : SUCCES -- 0 ecart avec le modele de reference." severity note;
    else
      report "tb_mlp_top_n : ECHEC -- des ecarts subsistent, voir ci-dessus." severity error;
    end if;

    sim_done <= true;
    wait;
  end process;

end architecture sim;
