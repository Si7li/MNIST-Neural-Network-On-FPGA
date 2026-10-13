library ieee;
use ieee.std_logic_1164.all;

entity xor_nn is
  port (
    a : in  std_logic;
    b : in  std_logic;
    y : out std_logic
  );
end entity xor_nn;

architecture structural of xor_nn is
  signal h0, h1 : std_logic;
begin
  hidden0 : entity work.neuron
    generic map (W0 => "00000010", W1 => "00000010", B => "11111111")
    port map (x0 => a, x1 => b, y => h0);

  hidden1 : entity work.neuron
    generic map (W0 => "11111110", W1 => "11111110", B => "00000011")
    port map (x0 => a, x1 => b, y => h1);

  output0 : entity work.neuron
    generic map (W0 => "00000010", W1 => "00000010", B => "11111101")
    port map (x0 => h0, x1 => h1, y => y);
end architecture structural;
