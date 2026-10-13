library ieee;
use ieee.std_logic_1164.all;
use work.weights_pkg.all;

entity mlp_digits is
  port (
    pixels : in  std_logic_vector(N_IN*PIXEL_W-1 downto 0);
    digit  : out std_logic_vector(3 downto 0);
    hidden : out std_logic_vector(N_HIDDEN*HIDDEN_W-1 downto 0);
    scores : out std_logic_vector(N_OUT*ACC2_W-1 downto 0)
  );
end entity mlp_digits;

architecture structural of mlp_digits is
  type acc1_array is array (0 to N_HIDDEN-1) of std_logic_vector(ACC1_W-1 downto 0);
  signal acc1   : acc1_array;
  signal h      : std_logic_vector(N_HIDDEN*HIDDEN_W-1 downto 0);
  signal s      : std_logic_vector(N_OUT*ACC2_W-1 downto 0);
begin
  layer1 : for j in 0 to N_HIDDEN-1 generate
    n : entity work.neuron_n
      generic map (N => N_IN, IN_W => PIXEL_W, ACC_W => ACC1_W,
                   W => W1(j), B => B1(j))
      port map (x => pixels, acc => acc1(j));

    act : entity work.relu_shift_sat
      generic map (WIN => ACC1_W, SHIFT => SHIFT1, WOUT => HIDDEN_W)
      port map (x => acc1(j), y => h((j+1)*HIDDEN_W-1 downto j*HIDDEN_W));
  end generate;

  layer2 : for k in 0 to N_OUT-1 generate
    n : entity work.neuron_n
      generic map (N => N_HIDDEN, IN_W => HIDDEN_W, ACC_W => ACC2_W,
                   W => W2(k), B => B2(k))
      port map (x => h, acc => s((k+1)*ACC2_W-1 downto k*ACC2_W));
  end generate;

  pick : entity work.argmax10
    generic map (W => ACC2_W)
    port map (scores => s, idx => digit);

  hidden <= h;
  scores <= s;
end architecture structural;
