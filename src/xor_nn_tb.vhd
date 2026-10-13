library ieee;
use ieee.std_logic_1164.all;

entity xor_nn_tb is
end entity xor_nn_tb;

architecture sim of xor_nn_tb is
  signal a, b, y : std_logic;
begin
  dut : entity work.xor_nn
    port map (a => a, b => b, y => y);

  a <= '0', '1' after 20 ns, '0' after 40 ns;
  b <= '0', '1' after 10 ns, '0' after 20 ns, '1' after 30 ns, '0' after 40 ns;
end architecture sim;
