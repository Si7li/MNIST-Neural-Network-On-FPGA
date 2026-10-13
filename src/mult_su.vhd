library ieee;
use ieee.std_logic_1164.all;

entity mult_su is
  generic (
    WA : integer := 8;
    WB : integer := 4
  );
  port (
    a : in  std_logic_vector(WA-1 downto 0);
    b : in  std_logic_vector(WB-1 downto 0);
    p : out std_logic_vector(WA+WB-1 downto 0)
  );
end entity mult_su;

architecture array_mult of mult_su is
  constant WP : integer := WA + WB;
  type vec_array is array (0 to WB-1) of std_logic_vector(WP-1 downto 0);
  signal a_ext : std_logic_vector(WP-1 downto 0);
  signal pp    : vec_array;
  signal acc   : vec_array;
begin
  a_ext(WA-1 downto 0) <= a;
  ext : for j in WA to WP-1 generate
    a_ext(j) <= a(WA-1);
  end generate;

  row : for i in 0 to WB-1 generate
    col : for j in 0 to WP-1 generate
      low : if j < i generate
        pp(i)(j) <= '0';
      end generate;
      high : if j >= i generate
        pp(i)(j) <= a_ext(j-i) and b(i);
      end generate;
    end generate;
  end generate;

  acc(0) <= pp(0);

  sum : for i in 1 to WB-1 generate
    add : entity work.adder_n
      generic map (N => WP)
      port map (a => acc(i-1), b => pp(i), s => acc(i));
  end generate;

  p <= acc(WB-1);
end architecture array_mult;
