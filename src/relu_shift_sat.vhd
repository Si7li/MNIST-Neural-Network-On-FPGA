library ieee;
use ieee.std_logic_1164.all;

entity relu_shift_sat is
  generic (
    WIN   : integer := 15;
    SHIFT : integer := 5;
    WOUT  : integer := 8
  );
  port (
    x : in  std_logic_vector(WIN-1 downto 0);
    y : out std_logic_vector(WOUT-1 downto 0)
  );
end entity relu_shift_sat;

architecture gates of relu_shift_sat is
  signal neg : std_logic;
  signal ovf : std_logic;
  signal or_chain : std_logic_vector(WIN-1 downto 0);
begin
  neg <= x(WIN-1);

  or_chain(WIN-1) <= '0';
  ochain : for k in WIN-2 downto 0 generate
    or_chain(k) <= or_chain(k+1) or x(k);
  end generate;

  has_ovf : if SHIFT + WOUT <= WIN-2 generate
    ovf <= or_chain(SHIFT + WOUT);
  end generate;
  no_ovf : if SHIFT + WOUT > WIN-2 generate
    ovf <= '0';
  end generate;

  bits : for k in 0 to WOUT-1 generate
    in_range : if SHIFT + k <= WIN-2 generate
      y(k) <= (not neg) and (x(SHIFT + k) or ovf);
    end generate;
    out_range : if SHIFT + k > WIN-2 generate
      y(k) <= (not neg) and ovf;
    end generate;
  end generate;
end architecture gates;
