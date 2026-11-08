-- tb_layer1.vhd
-- Teste la couche 1 seule (784 entrees -> 32 neurones) sur 10 images de
-- test reelles. Charge chaque image depuis data/test_images.hex (ecrit par
-- python/export_hex.py), lance le calcul, et compare les 32 activations
-- obtenues a la reference calculee par le modele Python
-- (data/layer1_golden_h.txt, ecrit par python/export_layer1_ref.py).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all;
use std.textio.all;
use work.weights_pkg.all;

entity tb_layer1 is
end entity tb_layer1;

architecture sim of tb_layer1 is
  constant CLK_PERIOD : time := 10 ns;
  constant N_IMAGES   : natural := 10;

  constant IMAGES_PATH : string := "data/test_images.hex";
  constant GOLDEN_PATH : string := "data/layer1_golden_h.txt";

  signal clk, rst, start, busy, done : std_logic := '0';

  -- image_ram
  signal img_we    : std_logic := '0';
  signal img_waddr : natural range 0 to N_IN - 1 := 0;
  signal img_wdata : signed(7 downto 0) := (others => '0');
  signal img_raddr : natural range 0 to N_IN - 1;
  signal img_rdata : signed(7 downto 0);

  -- weight_rom (seule la region couche 1 est utilisee ici)
  signal w1_addr : natural range 0 to N_IN * N_HIDDEN - 1;
  signal w1_data : signed(7 downto 0);
  signal b1_addr : natural range 0 to N_HIDDEN - 1;
  signal b1_data : signed(31 downto 0);
  signal w2_addr : natural range 0 to N_HIDDEN * N_OUT - 1 := 0;
  signal w2_data : signed(7 downto 0);
  signal b2_addr : natural range 0 to N_OUT - 1 := 0;
  signal b2_data : signed(31 downto 0);

  -- act_ram (sortie de la couche 1)
  signal act_we    : std_logic;
  signal act_waddr : natural range 0 to N_HIDDEN - 1;
  signal act_wdata : signed(7 downto 0);
  signal act_raddr : natural range 0 to N_HIDDEN - 1 := 0;
  signal act_rdata : signed(7 downto 0);

  signal m1 : unsigned(15 downto 0) := to_unsigned(M1_CONST, 16);
  signal s1 : natural range 0 to 31 := S1_CONST;

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

  img : entity work.image_ram
    generic map (DEPTH => N_IN)
    port map (clk => clk, we => img_we, waddr => img_waddr, wdata => img_wdata,
               raddr => img_raddr, rdata => img_rdata);

  wrom : entity work.weight_rom
    port map (clk => clk, w1_addr => w1_addr, w1_data => w1_data,
               b1_addr => b1_addr, b1_data => b1_data,
               w2_addr => w2_addr, w2_data => w2_data,
               b2_addr => b2_addr, b2_data => b2_data);

  act : entity work.act_ram
    generic map (DEPTH => N_HIDDEN)
    port map (clk => clk, we => act_we, waddr => act_waddr, wdata => act_wdata,
               raddr => act_raddr, rdata => act_rdata);

  eng : entity work.layer_engine
    generic map (N_IN => N_IN, N_HIDDEN => N_HIDDEN, M_WIDTH => 16)
    port map (
      clk => clk, rst => rst, start => start, busy => busy, done => done,
      in_addr => img_raddr, in_data => img_rdata,
      w_addr => w1_addr, w_data => w1_data,
      b_addr => b1_addr, b_data => b1_data,
      m => m1, s => s1,
      out_we => act_we, out_addr => act_waddr, out_data => act_wdata,
      out_data_raw => open
    );

  stim : process
    file img_file    : text open read_mode is IMAGES_PATH;
    file golden_file : text open read_mode is GOLDEN_PATH;
    variable line_v     : line;
    variable pixel_slv  : std_logic_vector(7 downto 0);
    variable expected_i : integer;
    variable n_tests, n_fail : natural := 0;
  begin
    rst <= '1';
    wait until rising_edge(clk);
    wait for 1 ns;
    rst <= '0';

    for img_idx in 0 to N_IMAGES - 1 loop

      -- charge l'image courante (784 pixels, lecture hexadecimale)
      for k in 0 to N_IN - 1 loop
        readline(img_file, line_v);
        hread(line_v, pixel_slv);
        img_we    <= '1';
        img_waddr <= k;
        img_wdata <= signed(pixel_slv);
        wait until rising_edge(clk);
      end loop;
      img_we <= '0';

      -- lance le calcul de la couche 1
      start <= '1';
      wait until rising_edge(clk);
      start <= '0';

      wait until done = '1';
      wait until rising_edge(clk);
      wait for 1 ns;

      -- relit les 32 activations et compare a la reference Python
      for k in 0 to N_HIDDEN - 1 loop
        act_raddr <= k;
        wait until rising_edge(clk);
        wait for 1 ns;

        readline(golden_file, line_v);
        read(line_v, expected_i);

        n_tests := n_tests + 1;
        if to_integer(act_rdata) /= expected_i then
          n_fail := n_fail + 1;
          report "ECHEC image " & integer'image(img_idx) &
                 " neurone " & integer'image(k) &
                 " : attendu=" & integer'image(expected_i) &
                 " obtenu=" & integer'image(to_integer(act_rdata))
            severity error;
        end if;
      end loop;

    end loop;

    if n_fail = 0 then
      report "tb_layer1 : " & integer'image(N_IMAGES) & " images, " &
             integer'image(n_tests) & " activations, toutes correctes." severity note;
    else
      report "tb_layer1 : " & integer'image(n_fail) & "/" &
             integer'image(n_tests) & " ECHECS." severity error;
    end if;

    sim_done <= true;
    wait;
  end process;

end architecture sim;
