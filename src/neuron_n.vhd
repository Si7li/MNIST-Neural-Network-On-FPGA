library ieee;
use ieee.std_logic_1164.all;
use work.weights_pkg.all;

entity neuron_n is
  generic (
    N     : integer;
    IN_W  : integer;
    ACC_W : integer;
    W     : weight_array;
    B     : std_logic_vector
  );
  port (
    x   : in  std_logic_vector(N*IN_W-1 downto 0);
    acc : out std_logic_vector(ACC_W-1 downto 0)
  );
end entity neuron_n;

architecture rtl of neuron_n is
  constant PROD_W : integer := WEIGHT_W + IN_W;
  type prod_array is array (0 to N-1) of std_logic_vector(PROD_W-1 downto 0);
  signal prod   : prod_array;
  signal leaves : std_logic_vector((N+1)*ACC_W-1 downto 0);
begin
  mults : for i in 0 to N-1 generate
    m : entity work.mult_su
      generic map (WA => WEIGHT_W, WB => IN_W)
      port map (a => W(W'low + i),
                b => x((i+1)*IN_W-1 downto i*IN_W),
                p => prod(i));

    leaves(i*ACC_W + PROD_W-1 downto i*ACC_W) <= prod(i);
    ext : for k in PROD_W to ACC_W-1 generate
      leaves(i*ACC_W + k) <= prod(i)(PROD_W-1);
    end generate;
  end generate;

  leaves((N+1)*ACC_W-1 downto N*ACC_W) <= B;

  tree : entity work.adder_tree
    generic map (N => N+1, W => ACC_W)
    port map (x => leaves, s => acc);
end architecture rtl;
