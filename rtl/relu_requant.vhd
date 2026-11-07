-- relu_requant.vhd
-- ReLU + remise a l'echelle entiere : prend l'accumulateur brut (32 bits,
-- sortie du MAC), le multiplie par un entier M et le decale de S bits
-- (division entiere par 2**S), puis sature le resultat dans [0, 127].
-- La borne basse 0 realise le ReLU ; la borne haute 127 sature sur 8 bits.
-- Bloc purement combinatoire.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity relu_requant is
  generic (
    M_WIDTH : positive := 16          -- largeur du multiplicateur entier M
  );
  port (
    acc : in  signed(31 downto 0);                 -- accumulateur brut (sortie du MAC)
    m   : in  unsigned(M_WIDTH - 1 downto 0);       -- multiplicateur entier (M1, M2, ...)
    s   : in  natural range 0 to 31;                -- decalage associe (S1, S2, ...)
    q   : out signed(7 downto 0)                    -- resultat, sature dans [0, 127]
  );
end entity relu_requant;

architecture rtl of relu_requant is
begin

  process (acc, m, s)
    variable m_signed    : signed(M_WIDTH downto 0);        -- un bit de plus : toujours positif
    variable product_nat : signed(32 + M_WIDTH downto 0);   -- largeur naturelle de acc * m_signed
    variable product      : signed(63 downto 0);              -- marge large avant le decalage
    variable shifted       : signed(63 downto 0);
    variable result_int   : integer;
  begin
    m_signed    := signed('0' & std_logic_vector(m));
    product_nat := acc * m_signed;
    product      := resize(product_nat, 64);
    shifted       := shift_right(product, s);

    if shifted < 0 then
      result_int := 0;                                       -- ReLU : ecrete en dessous de 0
    elsif shifted > 127 then
      result_int := 127;                                      -- saturation haute sur 8 bits
    else
      result_int := to_integer(shifted);
    end if;

    q <= to_signed(result_int, 8);
  end process;

end architecture rtl;
