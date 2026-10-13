library ieee;
use ieee.std_logic_1164.all;

package bits_pkg is
  function to_bits(value : natural; width : positive) return std_logic_vector;
end package bits_pkg;

package body bits_pkg is
  function to_bits(value : natural; width : positive) return std_logic_vector is
    variable v : natural := value;
    variable r : std_logic_vector(width-1 downto 0) := (others => '0');
  begin
    for b in 0 to width-1 loop
      if v mod 2 = 1 then
        r(b) := '1';
      end if;
      v := v / 2;
    end loop;
    return r;
  end function;
end package body bits_pkg;
