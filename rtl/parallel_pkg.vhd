-- parallel_pkg.vhd
-- Types "tableau" utilises par les blocs a N voies paralleles de l'etape 5
-- (mac_array.vhd, controller_fsm_n.vhd, weight_rom_n.vhd). Les elements
-- sont de type "natural" (sans borne haute figee dans le type) : chaque
-- entite qui les utilise contraint la LONGUEUR du tableau via un generique
-- (N_MAC), et GHDL verifie a l'execution que les index restent dans les
-- bornes des ROM/tableaux reellement indexes (voir weight_rom_n.vhd).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package parallel_pkg is
  type addr_array_t   is array (natural range <>) of natural;
  type data8_array_t  is array (natural range <>) of signed(7 downto 0);
  type data32_array_t is array (natural range <>) of signed(31 downto 0);
end package parallel_pkg;
