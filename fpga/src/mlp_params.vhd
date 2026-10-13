library ieee;
use ieee.std_logic_1164.all;

package mlp_params is
  constant N_IN      : integer := 64;
  constant N_HIDDEN  : integer := 32;
  constant N_OUT     : integer := 10;
  constant N_NEURONS : integer := 42;
  constant PIXEL_W   : integer := 4;
  constant WEIGHT_W  : integer := 8;
  constant HIDDEN_W  : integer := 8;
  constant ACC_W     : integer := 19;
  constant SHIFT1    : integer := 5;
  constant ADDR_W    : integer := 12;
  constant NEURON_W  : integer := 6;
  constant INPUT_W   : integer := 6;
  constant HADDR_W   : integer := 5;

  constant LAST_PIXEL  : std_logic_vector(INPUT_W-1 downto 0)  := "111111";
  constant LAST_HIDDEN : std_logic_vector(INPUT_W-1 downto 0)  := "011111";
  constant LAST_L1     : std_logic_vector(NEURON_W-1 downto 0) := "011111";
  constant LAST_NEURON : std_logic_vector(NEURON_W-1 downto 0) := "101001";

  type bias_array is array (natural range <>) of std_logic_vector(ACC_W-1 downto 0);
  constant B1 : bias_array(0 to N_HIDDEN-1) := (
    "0000000000000000100",
    "1111111111111111111",
    "0000000000001111010",
    "0000000000001010001",
    "0000000000011001010",
    "0000000000000011101",
    "0000000000010101011",
    "0000000000100000100",
    "0000000000011101110",
    "0000000000101001111",
    "0000000000001000010",
    "0000000000010101100",
    "0000000000110000000",
    "0000000000000000010",
    "0000000000000111100",
    "0000000000001110001",
    "1111111111111101111",
    "0000000000110111000",
    "0000000000011100111",
    "0000000000001001110",
    "0000000000001011010",
    "0000000000000011000",
    "0000000000001010110",
    "0000000000001100101",
    "0000000000000000000",
    "0000000000011010011",
    "0000000000010101100",
    "0000000000001000001",
    "0000000000001111110",
    "0000000000000100001",
    "0000000000100000011",
    "0000000000010111000"
  );
  constant B2 : bias_array(0 to N_OUT-1) := (
    "0000000000101011011",
    "1111111111100001010",
    "1111111111100011010",
    "0000000000010111100",
    "0000000000011110100",
    "1111111111100011111",
    "1111111111110010100",
    "1111111111110101000",
    "1111111111101100110",
    "1111111111101101001"
  );
end package mlp_params;
