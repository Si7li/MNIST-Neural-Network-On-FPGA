library ieee;
use ieee.std_logic_1164.all;

entity neuron is
  generic (
    W0 : std_logic_vector(7 downto 0);
    W1 : std_logic_vector(7 downto 0);
    B  : std_logic_vector(7 downto 0)
  );
  port (
    x0 : in  std_logic;
    x1 : in  std_logic;
    y  : out std_logic
  );
end entity neuron;

architecture rtl of neuron is
  signal x0_vec, x1_vec : std_logic_vector(7 downto 0);
  signal p0, p1         : std_logic_vector(7 downto 0);
  signal p_sum          : std_logic_vector(7 downto 0);
  signal sum            : std_logic_vector(7 downto 0);
begin
  x0_vec <= "0000000" & x0;
  x1_vec <= "0000000" & x1;

  mult0 : entity work.multiplier_n
    generic map (N => 8)
    port map (a => W0, b => x0_vec, p => p0);

  mult1 : entity work.multiplier_n
    generic map (N => 8)
    port map (a => W1, b => x1_vec, p => p1);

  add0 : entity work.adder_n
    generic map (N => 8)
    port map (a => p0, b => p1, s => p_sum);

  add1 : entity work.adder_n
    generic map (N => 8)
    port map (a => p_sum, b => B, s => sum);

  y <= (not sum(7)) and (sum(6) or sum(5) or sum(4) or sum(3) or
                         sum(2) or sum(1) or sum(0));
end architecture rtl;
