library ieee;
use ieee.std_logic_1164.all;

entity adder_tree is
  generic (
    N : integer := 64;
    W : integer := 15
  );
  port (
    x : in  std_logic_vector(N*W-1 downto 0);
    s : out std_logic_vector(W-1 downto 0)
  );
end entity adder_tree;

architecture heap of adder_tree is
  type node_array is array (0 to 2*N-2) of std_logic_vector(W-1 downto 0);
  signal node : node_array;
begin
  leaves : for i in 0 to N-1 generate
    node(N-1+i) <= x((i+1)*W-1 downto i*W);
  end generate;

  adders : for k in 0 to N-2 generate
    add : entity work.adder_n
      generic map (N => W)
      port map (a => node(2*k+1), b => node(2*k+2), s => node(k));
  end generate;

  s <= node(0);
end architecture heap;
