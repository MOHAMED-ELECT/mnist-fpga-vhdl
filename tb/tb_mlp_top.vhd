-- tb_mlp_top.vhd
-- Teste le reseau complet (mlp_top : couche 1 + couche 2 + argmax) sur
-- N_IMAGES images de test reelles. Charge chaque image depuis
-- data/test_images.hex (ecrit par python/export_hex.py), lance
-- l'inference via l'interface officielle (pix_we/pix_addr/pix_data puis
-- start/done/digit, section 3.6 du plan), et compare :
--   1) les 10 scores bruts (port de debug scores_debug) a la reference
--      Python, ligne par ligne, dans data/golden_outputs.txt -- 0 ecart
--      exige sur les 10 scores, pas seulement sur le chiffre predit ;
--   2) le chiffre predit (digit) au chiffre reellement attendu
--      (y_test), pour calculer la precision materielle globale.
--
-- Le nombre d'images testees est un generique (N_IMAGES) pour permettre
-- deux modes :
--   make sim_fast  -> N_IMAGES=50   (iteration rapide en developpement)
--   make sim_full  -> N_IMAGES=1000 (validation complete de l'etape 4)

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all;
use std.textio.all;
use work.weights_pkg.all;
use work.argmax_pkg.all;

entity tb_mlp_top is
  generic (
    N_IMAGES : positive := 1000
  );
end entity tb_mlp_top;

architecture sim of tb_mlp_top is
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

  dut : entity work.mlp_top
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

    -- "n_img_done" (pas "n_images") pour ne pas masquer le generique
    -- N_IMAGES : VHDL n'est pas sensible a la casse.
    variable n_img_done     : natural := 0;
    variable n_score_fail   : natural := 0;  -- images avec >=1 score different
    variable n_digit_vs_ref : natural := 0;  -- digit materiel != predicted Python
    variable n_correct      : natural := 0;  -- digit materiel == label reel
    variable any_mismatch   : boolean;
  begin
    rst <= '1';
    wait until rising_edge(clk);
    wait for 1 ns;
    rst <= '0';

    -- la premiere ligne de golden_outputs.txt est un en-tete ("# ...")
    readline(golden_file, line_v);

    for img_idx in 0 to N_IMAGES - 1 loop

      -- charge l'image courante (784 pixels, lecture hexadecimale)
      for k in 0 to N_IN - 1 loop
        readline(img_file, line_v);
        hread(line_v, pixel_slv);
        pix_we   <= '1';
        pix_addr <= k;
        pix_data <= signed(pixel_slv);
        wait until rising_edge(clk);
      end loop;
      pix_we <= '0';

      -- lance l'inference
      start <= '1';
      wait until rising_edge(clk);
      start <= '0';

      wait until done = '1';
      wait for 1 ns;

      -- lit la ligne de reference correspondante : idx label predicted score0..score9
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

    report "tb_mlp_top : " & integer'image(n_img_done) & " images testees.";
    report "  images avec un ecart sur les scores : " & integer'image(n_score_fail);
    report "  images avec digit != reference Python : " & integer'image(n_digit_vs_ref);
    report "  precision materielle (vs label reel) : " &
           integer'image(n_correct) & "/" & integer'image(n_img_done);

    if n_score_fail = 0 and n_digit_vs_ref = 0 then
      report "tb_mlp_top : SUCCES -- 0 ecart avec le modele de reference." severity note;
    else
      report "tb_mlp_top : ECHEC -- des ecarts subsistent, voir ci-dessus." severity error;
    end if;

    sim_done <= true;
    wait;
  end process;

end architecture sim;
