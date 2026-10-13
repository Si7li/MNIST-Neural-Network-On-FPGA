library ieee;
use ieee.std_logic_1164.all;
use work.mlp_params.all;

entity mlp_par32 is
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
end entity mlp_par32;

architecture rtl of mlp_par32 is
  constant S_IDLE : std_logic_vector(2 downto 0) := "000";
  constant S_LOAD : std_logic_vector(2 downto 0) := "001";
  constant S_MAC1 : std_logic_vector(2 downto 0) := "010";
  constant S_FIN1 : std_logic_vector(2 downto 0) := "011";
  constant S_MAC2 : std_logic_vector(2 downto 0) := "100";
  constant S_FIN2 : std_logic_vector(2 downto 0) := "101";

  constant ZERO_INPUT : std_logic_vector(INPUT_W-1 downto 0) := (others => '0');
  constant ONE        : std_logic_vector(0 downto 0)         := "1";

  signal st, st_next : std_logic_vector(2 downto 0);
  signal is_idle, is_load, is_mac1, is_fin1, is_mac2, is_fin2 : std_logic;
  signal go : std_logic;

  signal i, i_inc, i_d : std_logic_vector(INPUT_W-1 downto 0);
  signal i_en, i_clear : std_logic;
  signal digit_en      : std_logic;
  signal last_pix, last_hid : std_logic;

  signal pix, pix_d, pix_rot          : std_logic_vector(N_IN*PIXEL_W-1 downto 0);
  signal hid, hid_d, hid_rot, hid_new : std_logic_vector(N_HIDDEN*HIDDEN_W-1 downto 0);
  signal pix_en, hid_en               : std_logic;

  signal w1_row : std_logic_vector(N_HIDDEN*WEIGHT_W-1 downto 0);
  signal w2_row : std_logic_vector(N_OUT*WEIGHT_W-1 downto 0);

  type w_array   is array (0 to N_HIDDEN-1) of std_logic_vector(WEIGHT_W-1 downto 0);
  type acc_array is array (0 to N_HIDDEN-1) of std_logic_vector(ACC_W-1 downto 0);
  signal x        : std_logic_vector(HIDDEN_W-1 downto 0);
  signal w        : w_array;
  signal bias     : acc_array;
  signal acc      : acc_array;
  signal mac_load : std_logic_vector(N_HIDDEN-1 downto 0);
  signal mac_en   : std_logic_vector(N_HIDDEN-1 downto 0);

  signal scores           : std_logic_vector(N_OUT*ACC_W-1 downto 0);
  signal best             : std_logic_vector(3 downto 0);
  signal digit_q          : std_logic_vector(3 downto 0);
  signal done_d, done_q   : std_logic_vector(0 downto 0);
  signal valid_d, valid_q : std_logic_vector(0 downto 0);
  signal valid_en         : std_logic;
begin
  is_idle <= '1' when st = S_IDLE else '0';
  is_load <= '1' when st = S_LOAD else '0';
  is_mac1 <= '1' when st = S_MAC1 else '0';
  is_fin1 <= '1' when st = S_FIN1 else '0';
  is_mac2 <= '1' when st = S_MAC2 else '0';
  is_fin2 <= '1' when st = S_FIN2 else '0';
  go      <= is_idle and start;

  last_pix <= '1' when i = LAST_PIXEL  else '0';
  last_hid <= '1' when i = LAST_HIDDEN else '0';

  st_next <= S_IDLE when rst = '1' else
             S_LOAD when go = '1' else
             S_MAC1 when is_load = '1' else
             S_FIN1 when is_mac1 = '1' and last_pix = '1' else
             S_MAC1 when is_mac1 = '1' else
             S_MAC2 when is_fin1 = '1' else
             S_FIN2 when is_mac2 = '1' and last_hid = '1' else
             S_MAC2 when is_mac2 = '1' else
             S_IDLE;
  st_reg : entity work.reg_n generic map (W => 3)
    port map (clk => clk, en => ce, d => st_next, q => st);

  i_add : entity work.adder_n generic map (N => INPUT_W)
    port map (a => i, b => ZERO_INPUT, cin => '1', s => i_inc);
  i_clear <= is_load or is_fin1;
  i_d     <= ZERO_INPUT when i_clear = '1' else i_inc;
  i_en    <= (i_clear or is_mac1 or is_mac2) and ce;
  i_reg : entity work.reg_n generic map (W => INPUT_W)
    port map (clk => clk, en => i_en, d => i_d, q => i);

  pix_rot <= pix(PIXEL_W-1 downto 0) & pix(N_IN*PIXEL_W-1 downto PIXEL_W);
  pix_d   <= pixels when go = '1' else pix_rot;
  pix_en  <= (go or is_mac1) and ce;
  pix_reg : entity work.reg_n generic map (W => N_IN*PIXEL_W)
    port map (clk => clk, en => pix_en, d => pix_d, q => pix);

  hid_rot <= hid(HIDDEN_W-1 downto 0) & hid(N_HIDDEN*HIDDEN_W-1 downto HIDDEN_W);
  hid_d   <= hid_new when is_fin1 = '1' else hid_rot;
  hid_en  <= (is_fin1 or is_mac2) and ce;
  hid_reg : entity work.reg_n generic map (W => N_HIDDEN*HIDDEN_W)
    port map (clk => clk, en => hid_en, d => hid_d, q => hid);

  x <= hid(HIDDEN_W-1 downto 0) when is_mac2 = '1' else
       (HIDDEN_W-1 downto PIXEL_W => '0') & pix(PIXEL_W-1 downto 0);

  rom1 : entity work.rom_l1 port map (i => i, w => w1_row);
  rom2 : entity work.rom_l2 port map (j => i(HADDR_W-1 downto 0), w => w2_row);

  macs : for j in 0 to N_HIDDEN-1 generate
    both : if j < N_OUT generate
      w(j)        <= w2_row((j+1)*WEIGHT_W-1 downto j*WEIGHT_W) when is_mac2 = '1' else
                     w1_row((j+1)*WEIGHT_W-1 downto j*WEIGHT_W);
      bias(j)     <= B2(j) when is_fin1 = '1' else B1(j);
      mac_load(j) <= (is_load or is_fin1) and ce;
      mac_en(j)   <= (is_mac1 or is_mac2) and ce;
    end generate;
    l1_only : if j >= N_OUT generate
      w(j)        <= w1_row((j+1)*WEIGHT_W-1 downto j*WEIGHT_W);
      bias(j)     <= B1(j);
      mac_load(j) <= is_load and ce;
      mac_en(j)   <= is_mac1 and ce;
    end generate;

    mac : entity work.mac_unit
      port map (clk => clk, load => mac_load(j), en => mac_en(j),
                w => w(j), x => x, bias => bias(j), acc => acc(j));

    act : entity work.relu_shift_sat
      generic map (WIN => ACC_W, SHIFT => SHIFT1, WOUT => HIDDEN_W)
      port map (x => acc(j), y => hid_new((j+1)*HIDDEN_W-1 downto j*HIDDEN_W));
  end generate;

  score_bits : for k in 0 to N_OUT-1 generate
    scores((k+1)*ACC_W-1 downto k*ACC_W) <= acc(k);
  end generate;

  pick : entity work.argmax10 generic map (W => ACC_W)
    port map (scores => scores, idx => best);

  digit_en <= is_fin2 and ce;
  digit_reg : entity work.reg_n generic map (W => 4)
    port map (clk => clk, en => digit_en, d => best, q => digit_q);

  done_d <= "1" when is_fin2 = '1' and rst = '0' else "0";
  done_reg : entity work.reg_n generic map (W => 1)
    port map (clk => clk, en => ce, d => done_d, q => done_q);

  valid_d  <= "0" when rst = '1' else ONE;
  valid_en <= (rst or is_fin2) and ce;
  valid_reg : entity work.reg_n generic map (W => 1)
    port map (clk => clk, en => valid_en, d => valid_d, q => valid_q);

  busy  <= not is_idle;
  done  <= done_q(0);
  valid <= valid_q(0);
  digit <= digit_q;
  hidden <= hid;
end architecture rtl;
