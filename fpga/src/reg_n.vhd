library ieee;
use ieee.std_logic_1164.all;

entity reg_n is
  generic (
    W : integer := 8
  );
  port (
    clk : in  std_logic;
    en  : in  std_logic;
    d   : in  std_logic_vector(W-1 downto 0);
    q   : out std_logic_vector(W-1 downto 0) := (others => '0')
  );
end entity reg_n;

architecture dff of reg_n is
begin
  q <= d when rising_edge(clk) and en = '1';
end architecture dff;
