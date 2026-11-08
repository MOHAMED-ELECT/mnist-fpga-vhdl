-- mlp_top_n_synth.vhd
-- Meme role que mlp_top_synth.vhd, pour la famille mlp_top_n.vhd (etape 5,
-- generique en N_MAC) : expose seulement les 9 signaux officiels, sans
-- scores_debug, pour pouvoir synthetiser chaque variante (N=1,2,4,8,16,32)
-- sans faire exploser le nombre de broches d'E/S. Sert a comparer LUT et
-- Fmax entre architectures (etape 5/6 combinees, "1 MAC ou 32 MAC ? le
-- compromis en chiffres").

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.weights_pkg.all;

entity mlp_top_n_synth is
  generic (
    N_MAC : positive := 1
  );
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
end entity mlp_top_n_synth;

architecture rtl of mlp_top_n_synth is
  signal scores_unused : work.argmax_pkg.score_array;
begin

  dut : entity work.mlp_top_n
    generic map (N_MAC => N_MAC)
    port map (
      clk => clk, rst => rst,
      pix_we => pix_we, pix_addr => pix_addr, pix_data => pix_data,
      start => start, busy => busy, done => done, digit => digit,
      scores_debug => scores_unused
    );

end architecture rtl;
