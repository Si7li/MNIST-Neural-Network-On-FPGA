library ieee;
use ieee.std_logic_1164.all;

entity seg7 is
  port (
    digit : in  std_logic_vector(3 downto 0);
    valid : in  std_logic;
    seg   : out std_logic_vector(6 downto 0);
    dp    : out std_logic;
    an    : out std_logic_vector(3 downto 0)
  );
end entity seg7;

architecture table of seg7 is
  signal pattern : std_logic_vector(6 downto 0);
begin
  with digit select pattern <=
    "1000000" when "0000",
    "1111001" when "0001",
    "0100100" when "0010",
    "0110000" when "0011",
    "0011001" when "0100",
    "0010010" when "0101",
    "0000010" when "0110",
    "1111000" when "0111",
    "0000000" when "1000",
    "0010000" when "1001",
    "0111111" when others;

  seg <= pattern when valid = '1' else "0111111";
  dp  <= '1';
  an  <= "1110";
end architecture table;
