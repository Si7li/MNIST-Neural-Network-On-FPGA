library ieee;
use ieee.std_logic_1164.all;

entity multiplier_n is
  generic (
    N : integer := 8
  );
  port (
    a : in  std_logic_vector(N-1 downto 0);
    b : in  std_logic_vector(N-1 downto 0);
    p : out std_logic_vector(N-1 downto 0)
  );
end entity multiplier_n;

architecture array_mult of multiplier_n is
  type vec_array is array (0 to N-1) of std_logic_vector(N-1 downto 0);
  signal pp  : vec_array;
  signal acc : vec_array;
begin
  row : for i in 0 to N-1 generate
    col : for j in 0 to N-1 generate
      low : if j < i generate
        pp(i)(j) <= '0';
      end generate;
      high : if j >= i generate
        pp(i)(j) <= a(j-i) and b(i);
      end generate;
    end generate;
  end generate;

  acc(0) <= pp(0);

  sum : for i in 1 to N-1 generate
    add : entity work.adder_n
      generic map (N => N)
      port map (a => acc(i-1), b => pp(i), s => acc(i));
  end generate;

  p <= acc(N-1);
end architecture array_mult;
