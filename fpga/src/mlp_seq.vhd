library ieee;
use ieee.std_logic_1164.all;
use work.mlp_params.all;

entity mlp_seq is
  port (
    clk    : in  std_logic;
    rst    : in  std_logic;
    ce     : in  std_logic := '1';
    start  : in  std_logic;
    pixels : in  std_logic_vector(N_IN*PIXEL_W-1 downto 0);
    busy   : out std_logic;
    done   : out std_logic;
    valid  : out std_logic;
    digit  : out std_logic_vector(3 downto 0);
    hidden : out std_logic_vector(N_HIDDEN*HIDDEN_W-1 downto 0)
  );
end entity mlp_seq;

architecture rtl of mlp_seq is
  constant S_IDLE : std_logic_vector(1 downto 0) := "00";
  constant S_LOAD : std_logic_vector(1 downto 0) := "01";
  constant S_MAC  : std_logic_vector(1 downto 0) := "10";
  constant S_FIN  : std_logic_vector(1 downto 0) := "11";

  constant ZERO_ADDR   : std_logic_vector(ADDR_W-1 downto 0)   := (others => '0');
  constant ZERO_NEURON : std_logic_vector(NEURON_W-1 downto 0) := (others => '0');
  constant ZERO_INPUT  : std_logic_vector(INPUT_W-1 downto 0)  := (others => '0');
  constant ZERO_DIGIT  : std_logic_vector(3 downto 0)          := (others => '0');
  constant ONE         : std_logic_vector(0 downto 0)          := "1";

  constant PROD_W : integer := WEIGHT_W + HIDDEN_W;

  signal st, st_next                 : std_logic_vector(1 downto 0);
  signal is_idle, is_load, is_mac, is_fin : std_logic;
  signal go                          : std_logic;
  signal n_en, i_en, a_en, l2_en, k_en : std_logic;

  signal n, n_inc, n_d : std_logic_vector(NEURON_W-1 downto 0);
  signal i, i_inc, i_d : std_logic_vector(INPUT_W-1 downto 0);
  signal a, a_inc, a_d : std_logic_vector(ADDR_W-1 downto 0);
  signal k, k_inc, k_d : std_logic_vector(3 downto 0);
  signal l2, l2_d      : std_logic_vector(0 downto 0);
  signal layer2        : std_logic;
  signal last_in, l1_end, last_n : std_logic;

  signal pix, pix_d, pix_rot          : std_logic_vector(N_IN*PIXEL_W-1 downto 0);
  signal hid, hid_d, hid_rot, hid_new : std_logic_vector(N_HIDDEN*HIDDEN_W-1 downto 0);
  signal pix_en, hid_en               : std_logic;

  signal w        : std_logic_vector(WEIGHT_W-1 downto 0);
  signal x        : std_logic_vector(HIDDEN_W-1 downto 0);
  signal prod     : std_logic_vector(PROD_W-1 downto 0);
  signal prod_ext : std_logic_vector(ACC_W-1 downto 0);
  signal bias     : std_logic_vector(ACC_W-1 downto 0);
  signal acc, acc_d, sum : std_logic_vector(ACC_W-1 downto 0);
  signal acc_en   : std_logic;
  signal relu_out : std_logic_vector(HIDDEN_W-1 downto 0);

  signal best, best_d       : std_logic_vector(ACC_W-1 downto 0);
  signal best_idx           : std_logic_vector(3 downto 0);
  signal gt, first_l2, wins : std_logic;
  signal best_en            : std_logic;
  signal digit_d, digit_q   : std_logic_vector(3 downto 0);
  signal finish             : std_logic;
  signal done_d, done_q     : std_logic_vector(0 downto 0);
  signal valid_d, valid_q   : std_logic_vector(0 downto 0);
  signal valid_en           : std_logic;
  signal digit_en           : std_logic;
begin
  is_idle <= '1' when st = S_IDLE else '0';
  is_load <= '1' when st = S_LOAD else '0';
  is_mac  <= '1' when st = S_MAC  else '0';
  is_fin  <= '1' when st = S_FIN  else '0';
  go     <= is_idle and start;

  layer2  <= l2(0);
  last_in <= '1' when (layer2 = '0' and i = LAST_PIXEL) or (layer2 = '1' and i = LAST_HIDDEN) else '0';
  l1_end <= '1' when n = LAST_L1 else '0';
  last_n  <= '1' when n = LAST_NEURON else '0';
  finish  <= is_fin and last_n;

  st_next <= S_IDLE when rst = '1' else
             S_LOAD when go = '1' else
             S_MAC  when is_load = '1' else
             S_FIN  when is_mac = '1' and last_in = '1' else
             S_MAC  when is_mac = '1' else
             S_IDLE when finish = '1' else
             S_LOAD when is_fin = '1' else
             S_IDLE;
  st_reg : entity work.reg_n generic map (W => 2)
    port map (clk => clk, en => ce, d => st_next, q => st);

  n_add : entity work.adder_n generic map (N => NEURON_W)
    port map (a => n, b => ZERO_NEURON, cin => '1', s => n_inc);
  n_d <= ZERO_NEURON when go = '1' else n_inc;
  n_en <= (go or is_fin) and ce;
  n_reg : entity work.reg_n generic map (W => NEURON_W)
    port map (clk => clk, en => n_en, d => n_d, q => n);

  i_add : entity work.adder_n generic map (N => INPUT_W)
    port map (a => i, b => ZERO_INPUT, cin => '1', s => i_inc);
  i_d <= ZERO_INPUT when is_load = '1' else i_inc;
  i_en <= (is_load or is_mac) and ce;
  i_reg : entity work.reg_n generic map (W => INPUT_W)
    port map (clk => clk, en => i_en, d => i_d, q => i);

  a_add : entity work.adder_n generic map (N => ADDR_W)
    port map (a => a, b => ZERO_ADDR, cin => '1', s => a_inc);
  a_d <= ZERO_ADDR when go = '1' else a_inc;
  a_en <= (go or is_mac) and ce;
  a_reg : entity work.reg_n generic map (W => ADDR_W)
    port map (clk => clk, en => a_en, d => a_d, q => a);

  l2_d <= "0" when go = '1' else ONE;
  l2_en <= (go or (is_fin and l1_end)) and ce;
  l2_reg : entity work.reg_n generic map (W => 1)
    port map (clk => clk, en => l2_en, d => l2_d, q => l2);

  k_add : entity work.adder_n generic map (N => 4)
    port map (a => k, b => ZERO_DIGIT, cin => '1', s => k_inc);
  k_d <= ZERO_DIGIT when go = '1' else k_inc;
  k_en <= (go or (is_fin and layer2)) and ce;
  k_reg : entity work.reg_n generic map (W => 4)
    port map (clk => clk, en => k_en, d => k_d, q => k);

  pix_rot <= pix(PIXEL_W-1 downto 0) & pix(N_IN*PIXEL_W-1 downto PIXEL_W);
  pix_d   <= pixels when go = '1' else pix_rot;
  pix_en  <= (go or (is_mac and not layer2)) and ce;
  pix_reg : entity work.reg_n generic map (W => N_IN*PIXEL_W)
    port map (clk => clk, en => pix_en, d => pix_d, q => pix);

  hid_new <= relu_out & hid(N_HIDDEN*HIDDEN_W-1 downto HIDDEN_W);
  hid_rot <= hid(HIDDEN_W-1 downto 0) & hid(N_HIDDEN*HIDDEN_W-1 downto HIDDEN_W);
  hid_d   <= hid_new when is_fin = '1' else hid_rot;
  hid_en  <= ((is_fin and not layer2) or (is_mac and layer2)) and ce;
  hid_reg : entity work.reg_n generic map (W => N_HIDDEN*HIDDEN_W)
    port map (clk => clk, en => hid_en, d => hid_d, q => hid);

  wrom : entity work.weights_rom port map (addr => a, w => w);
  brom : entity work.bias_rom    port map (n => n, b => bias);

  x <= hid(HIDDEN_W-1 downto 0) when layer2 = '1' else
       (HIDDEN_W-1 downto PIXEL_W => '0') & pix(PIXEL_W-1 downto 0);

  mult : entity work.mult_su generic map (WA => WEIGHT_W, WB => HIDDEN_W)
    port map (a => w, b => x, p => prod);

  prod_ext(PROD_W-1 downto 0) <= prod;
  ext : for b in PROD_W to ACC_W-1 generate
    prod_ext(b) <= prod(PROD_W-1);
  end generate;

  add : entity work.adder_n generic map (N => ACC_W)
    port map (a => acc, b => prod_ext, s => sum);

  acc_d  <= bias when is_load = '1' else sum;
  acc_en <= (is_load or is_mac) and ce;
  acc_reg : entity work.reg_n generic map (W => ACC_W)
    port map (clk => clk, en => acc_en, d => acc_d, q => acc);

  act : entity work.relu_shift_sat
    generic map (WIN => ACC_W, SHIFT => SHIFT1, WOUT => HIDDEN_W)
    port map (x => acc, y => relu_out);

  cmp : entity work.comparator_gt generic map (W => ACC_W)
    port map (a => acc, b => best, gt => gt);
  first_l2 <= '1' when k = ZERO_DIGIT else '0';
  wins     <= first_l2 or gt;
  best_en  <= is_fin and layer2 and wins and ce;

  best_reg : entity work.reg_n generic map (W => ACC_W)
    port map (clk => clk, en => best_en, d => acc, q => best);
  bidx_reg : entity work.reg_n generic map (W => 4)
    port map (clk => clk, en => best_en, d => k, q => best_idx);

  digit_d  <= k when wins = '1' else best_idx;
  digit_en <= finish and ce;
  digit_reg : entity work.reg_n generic map (W => 4)
    port map (clk => clk, en => digit_en, d => digit_d, q => digit_q);

  done_d <= "1" when finish = '1' and rst = '0' else "0";
  done_reg : entity work.reg_n generic map (W => 1)
    port map (clk => clk, en => ce, d => done_d, q => done_q);

  valid_d  <= "0" when rst = '1' else ONE;
  valid_en <= (rst or finish) and ce;
  valid_reg : entity work.reg_n generic map (W => 1)
    port map (clk => clk, en => valid_en, d => valid_d, q => valid_q);

  busy  <= not is_idle;
  done  <= done_q(0);
  valid <= valid_q(0);
  digit <= digit_q;
  hidden <= hid;
end architecture rtl;
