-- weight_rom_n.vhd
-- Variante de weight_rom.vhd a N_PORTS voies de lecture paralleles : les
-- N_PORTS unites MAC de mac_array.vhd ont chacune besoin, au meme cycle,
-- du poids ET du biais d'un neurone DIFFERENT -- d'ou N_PORTS adresses et
-- N_PORTS donnees independantes par couche. Les donnees elles-memes
-- viennent des memes constantes que weight_rom.vhd (weights_pkg.vhd,
-- genere par python/gen_vhdl_pkg.py) : seul le nombre de ports change,
-- pas le contenu.
--
-- Cout materiel : N_PORTS voies = N_PORTS fois plus de logique de
-- decodage d'adresse (et donc de LUT a l'etape 6), meme si le contenu de
-- la ROM reste le meme. C'est exactement le "lien entre N MAC et la
-- surface occupee" que l'etape 5 demande de mettre en evidence.
--
-- Piege (comme weight_rom.vhd) : la lecture est synchrone, donc *_data
-- n'est valide qu'un cycle APRES avoir presente *_addr.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.weights_pkg.all;
use work.parallel_pkg.all;

entity weight_rom_n is
  generic (
    N_PORTS : positive      -- nombre de voies paralleles (= N_MAC)
  );
  port (
    clk : in std_logic;

    -- couche 1 (784 entrees -> 32 neurones)
    w1_addr : in  addr_array_t(0 to N_PORTS - 1);
    w1_data : out data8_array_t(0 to N_PORTS - 1);
    b1_addr : in  addr_array_t(0 to N_PORTS - 1);
    b1_data : out data32_array_t(0 to N_PORTS - 1);

    -- couche 2 (32 entrees -> 10 sorties)
    w2_addr : in  addr_array_t(0 to N_PORTS - 1);
    w2_data : out data8_array_t(0 to N_PORTS - 1);
    b2_addr : in  addr_array_t(0 to N_PORTS - 1);
    b2_data : out data32_array_t(0 to N_PORTS - 1)
  );
end entity weight_rom_n;

architecture rtl of weight_rom_n is
begin

  process (clk)
  begin
    if rising_edge(clk) then
      for p in 0 to N_PORTS - 1 loop
        w1_data(p) <= to_signed(W1_ROM(w1_addr(p)), 8);
        b1_data(p) <= to_signed(B1_ROM(b1_addr(p)), 32);
        w2_data(p) <= to_signed(W2_ROM(w2_addr(p)), 8);
        b2_data(p) <= to_signed(B2_ROM(b2_addr(p)), 32);
      end loop;
    end if;
  end process;

end architecture rtl;
