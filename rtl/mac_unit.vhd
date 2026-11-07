-- mac_unit.vhd
-- Unite multiply-accumulate : a chaque cycle ou en='1', multiplie w par x
-- (8 bits signes chacun) et ajoute le resultat a l'accumulateur 32 bits.
-- clear='1' charge le biais dans l'accumulateur (debut d'un neurone).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mac_unit is
  port (
    clk   : in  std_logic;
    rst   : in  std_logic;                      -- reset synchrone, actif haut
    clear : in  std_logic;                      -- charge le biais (debut d'un neurone)
    en    : in  std_logic;                      -- accumule w*x
    w     : in  signed(7 downto 0);
    x     : in  signed(7 downto 0);
    bias  : in  signed(31 downto 0);
    acc   : out signed(31 downto 0)
  );
end entity mac_unit;

architecture rtl of mac_unit is
  signal acc_r : signed(31 downto 0) := (others => '0');
begin

  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        acc_r <= (others => '0');
      elsif clear = '1' then
        acc_r <= bias;
      elsif en = '1' then
        acc_r <= acc_r + resize(w * x, 32);
      end if;
    end if;
  end process;

  acc <= acc_r;

end architecture rtl;
