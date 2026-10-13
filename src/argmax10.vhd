library ieee;
use ieee.std_logic_1164.all;

entity argmax10 is
  generic (
    W : integer := 19
  );
  port (
    scores : in  std_logic_vector(10*W-1 downto 0);
    idx    : out std_logic_vector(3 downto 0)
  );
end entity argmax10;

architecture tree of argmax10 is
  type val_array is array (0 to 9) of std_logic_vector(W-1 downto 0);
  type idx_array is array (0 to 9) of std_logic_vector(3 downto 0);
  constant LEAF_IDX : idx_array := ("0000", "0001", "0010", "0011", "0100",
                                    "0101", "0110", "0111", "1000", "1001");
  signal v           : val_array;
  signal v1          : val_array;
  signal i1          : idx_array;
  signal v2a, v2b    : std_logic_vector(W-1 downto 0);
  signal i2a, i2b    : std_logic_vector(3 downto 0);
  signal v3          : std_logic_vector(W-1 downto 0);
  signal i3          : std_logic_vector(3 downto 0);
  signal v4          : std_logic_vector(W-1 downto 0);
begin
  split : for k in 0 to 9 generate
    v(k) <= scores((k+1)*W-1 downto k*W);
  end generate;

  l1 : for k in 0 to 4 generate
    m : entity work.max2
      generic map (W => W)
      port map (a_val => v(2*k),   a_idx => LEAF_IDX(2*k),
                b_val => v(2*k+1), b_idx => LEAF_IDX(2*k+1),
                val   => v1(k),    idx   => i1(k));
  end generate;

  l2a : entity work.max2
    generic map (W => W)
    port map (a_val => v1(0), a_idx => i1(0), b_val => v1(1), b_idx => i1(1),
              val => v2a, idx => i2a);
  l2b : entity work.max2
    generic map (W => W)
    port map (a_val => v1(2), a_idx => i1(2), b_val => v1(3), b_idx => i1(3),
              val => v2b, idx => i2b);

  l3 : entity work.max2
    generic map (W => W)
    port map (a_val => v2a, a_idx => i2a, b_val => v2b, b_idx => i2b,
              val => v3, idx => i3);

  l4 : entity work.max2
    generic map (W => W)
    port map (a_val => v3, a_idx => i3, b_val => v1(4), b_idx => i1(4),
              val => v4, idx => idx);
end architecture tree;
