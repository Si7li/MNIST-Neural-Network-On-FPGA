library ieee;
use ieee.std_logic_1164.all;

entity max2 is
  generic (
    W : integer := 19
  );
  port (
    a_val : in  std_logic_vector(W-1 downto 0);
    a_idx : in  std_logic_vector(3 downto 0);
    b_val : in  std_logic_vector(W-1 downto 0);
    b_idx : in  std_logic_vector(3 downto 0);
    val   : out std_logic_vector(W-1 downto 0);
    idx   : out std_logic_vector(3 downto 0)
  );
end entity max2;

architecture rtl of max2 is
  signal b_wins : std_logic;
begin
  cmp : entity work.comparator_gt
    generic map (W => W)
    port map (a => b_val, b => a_val, gt => b_wins);

  val <= b_val when b_wins = '1' else a_val;
  idx <= b_idx when b_wins = '1' else a_idx;
end architecture rtl;
