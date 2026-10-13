library ieee;
use ieee.std_logic_1164.all;

entity adder_n is
  generic (
    N : integer := 8
  );
  port (
    a    : in  std_logic_vector(N-1 downto 0);
    b    : in  std_logic_vector(N-1 downto 0);
    cin  : in  std_logic := '0';
    s    : out std_logic_vector(N-1 downto 0);
    cout : out std_logic
  );
end entity adder_n;

architecture ripple of adder_n is
  signal c : std_logic_vector(N downto 0);
begin
  c(0) <= cin;

  stage : for i in 0 to N-1 generate
    fa : entity work.full_adder
      port map (a => a(i), b => b(i), cin => c(i), s => s(i), cout => c(i+1));
  end generate;

  cout <= c(N);
end architecture ripple;
