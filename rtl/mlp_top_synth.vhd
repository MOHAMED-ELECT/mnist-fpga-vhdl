-- mlp_top_synth.vhd
-- Enveloppe de synthese autour de mlp_top.vhd : expose UNIQUEMENT les 9
-- signaux officiels de l'interface (section 3.6 du plan), sans le port de
-- debug scores_debug (10 x 32 bits = 320 broches, qui ferait exploser le
-- nombre d'E/S lors du placement sur un vrai boitier FPGA -- scores_debug
-- n'a de sens qu'en simulation, pour comparer au modele Python).
--
-- C'est CE fichier qu'on synthetise (voir synth/synth.ys), pas
-- directement mlp_top.vhd : la logique interne est strictement identique
-- (une seule instance de mlp_top, scores_debug simplement laisse non
-- connecte a l'exterieur), seul le nombre de broches change.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.weights_pkg.all;
use work.argmax_pkg.all;

entity mlp_top_synth is
  port (
    clk : in std_logic;
    rst : in std_logic;

    pix_we   : in std_logic;
    pix_addr : in natural range 0 to N_IN - 1;
    pix_data : in signed(7 downto 0);

    start : in  std_logic;
    busy  : out std_logic;
    done  : out std_logic;
    digit : out unsigned(3 downto 0)
  );
end entity mlp_top_synth;

architecture rtl of mlp_top_synth is
  signal scores_unused : score_array;  -- non connecte a l'exterieur
begin

  dut : entity work.mlp_top
    port map (
      clk => clk, rst => rst,
      pix_we => pix_we, pix_addr => pix_addr, pix_data => pix_data,
      start => start, busy => busy, done => done, digit => digit,
      scores_debug => scores_unused
    );

end architecture rtl;
