library ieee;
use ieee.std_logic_1164.all;
use work.mlp_params.all;

entity mac_unit is
  port (
    clk  : in  std_logic;
    load : in  std_logic;
    en   : in  std_logic;
    w    : in  std_logic_vector(WEIGHT_W-1 downto 0);
    x    : in  std_logic_vector(HIDDEN_W-1 downto 0);
    bias : in  std_logic_vector(ACC_W-1 downto 0);
    acc  : out std_logic_vector(ACC_W-1 downto 0)
  );
end entity mac_unit;

architecture rtl of mac_unit is
  constant PROD_W : integer := WEIGHT_W + HIDDEN_W;
  signal prod     : std_logic_vector(PROD_W-1 downto 0);
  signal prod_ext : std_logic_vector(ACC_W-1 downto 0);
  signal sum      : std_logic_vector(ACC_W-1 downto 0);
  signal acc_q    : std_logic_vector(ACC_W-1 downto 0);
  signal acc_d    : std_logic_vector(ACC_W-1 downto 0);
  signal acc_en   : std_logic;
begin
  mult : entity work.mult_su generic map (WA => WEIGHT_W, WB => HIDDEN_W)
    port map (a => w, b => x, p => prod);

  prod_ext(PROD_W-1 downto 0) <= prod;
  ext : for b in PROD_W to ACC_W-1 generate
    prod_ext(b) <= prod(PROD_W-1);
  end generate;

  add : entity work.adder_n generic map (N => ACC_W)
    port map (a => acc_q, b => prod_ext, s => sum);

  acc_d  <= bias when load = '1' else sum;
  acc_en <= load or en;
  acc_reg : entity work.reg_n generic map (W => ACC_W)
    port map (clk => clk, en => acc_en, d => acc_d, q => acc_q);

  acc <= acc_q;
end architecture rtl;
