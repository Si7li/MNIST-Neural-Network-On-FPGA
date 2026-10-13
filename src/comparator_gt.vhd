library ieee;
use ieee.std_logic_1164.all;

entity comparator_gt is
  generic (
    W : integer := 19
  );
  port (
    a  : in  std_logic_vector(W-1 downto 0);
    b  : in  std_logic_vector(W-1 downto 0);
    gt : out std_logic
  );
end entity comparator_gt;

architecture sub of comparator_gt is
  signal a_inv, b_ext, diff : std_logic_vector(W downto 0);
begin
  a_inv <= not (a(W-1) & a);
  b_ext <= b(W-1) & b;

  sub0 : entity work.adder_n
    generic map (N => W + 1)
    port map (a => b_ext, b => a_inv, cin => '1', s => diff);

  gt <= diff(W);
end architecture sub;
