library ieee;
use ieee.std_logic_1164.all;
use work.bits_pkg.all;

entity uart_rx is
  generic (
    CLKS_PER_BIT : integer := 868
  );
  port (
    clk   : in  std_logic;
    rx    : in  std_logic;
    data  : out std_logic_vector(7 downto 0);
    valid : out std_logic
  );
end entity uart_rx;

architecture rtl of uart_rx is
  constant CNT_W   : integer := 10;
  constant FULL_M1 : std_logic_vector(CNT_W-1 downto 0) := to_bits(CLKS_PER_BIT - 1, CNT_W);
  constant HALF_M1 : std_logic_vector(CNT_W-1 downto 0) := to_bits(CLKS_PER_BIT / 2 - 1, CNT_W);
  constant ZERO    : std_logic_vector(CNT_W-1 downto 0) := (others => '0');
  constant ZERO3   : std_logic_vector(2 downto 0) := "000";

  constant S_IDLE  : std_logic_vector(1 downto 0) := "00";
  constant S_START : std_logic_vector(1 downto 0) := "01";
  constant S_DATA  : std_logic_vector(1 downto 0) := "10";
  constant S_STOP  : std_logic_vector(1 downto 0) := "11";
  constant ALWAYS  : std_logic := '1';

  signal rx_in, rx_s1, rx_s2 : std_logic_vector(0 downto 0);
  signal rx_bit              : std_logic;
  signal st, st_next         : std_logic_vector(1 downto 0);
  signal is_idle, is_start, is_data, is_stop : std_logic;
  signal half_end, full_end  : std_logic;
  signal sample              : std_logic;
  signal cnt, cnt_inc, cnt_d : std_logic_vector(CNT_W-1 downto 0);
  signal bitn, bitn_inc, bitn_d : std_logic_vector(2 downto 0);
  signal bitn_en             : std_logic;
  signal shreg, shreg_d      : std_logic_vector(7 downto 0);
  signal shreg_en            : std_logic;
  signal valid_d, valid_q    : std_logic_vector(0 downto 0);
begin
  rx_in(0) <= rx;
  sync1 : entity work.reg_n generic map (W => 1)
    port map (clk => clk, en => ALWAYS, d => rx_in, q => rx_s1);
  sync2 : entity work.reg_n generic map (W => 1)
    port map (clk => clk, en => ALWAYS, d => rx_s1, q => rx_s2);
  rx_bit <= rx_s2(0);

  is_idle  <= '1' when st = S_IDLE  else '0';
  is_start <= '1' when st = S_START else '0';
  is_data  <= '1' when st = S_DATA  else '0';
  is_stop  <= '1' when st = S_STOP  else '0';
  half_end <= '1' when cnt = HALF_M1 else '0';
  full_end <= '1' when cnt = FULL_M1 else '0';
  sample   <= (is_start and half_end) or ((is_data or is_stop) and full_end);

  st_next <= S_START when is_idle = '1' and rx_bit = '0' else
             S_DATA  when is_start = '1' and half_end = '1' and rx_bit = '0' else
             S_IDLE  when is_start = '1' and half_end = '1' else
             S_STOP  when is_data = '1' and full_end = '1' and bitn = "111" else
             S_IDLE  when is_stop = '1' and full_end = '1' else
             st;
  st_reg : entity work.reg_n generic map (W => 2)
    port map (clk => clk, en => ALWAYS, d => st_next, q => st);

  cnt_add : entity work.adder_n generic map (N => CNT_W)
    port map (a => cnt, b => ZERO, cin => '1', s => cnt_inc);
  cnt_d <= ZERO when is_idle = '1' or sample = '1' else cnt_inc;
  cnt_reg : entity work.reg_n generic map (W => CNT_W)
    port map (clk => clk, en => ALWAYS, d => cnt_d, q => cnt);

  bitn_add : entity work.adder_n generic map (N => 3)
    port map (a => bitn, b => ZERO3, cin => '1', s => bitn_inc);
  bitn_d  <= ZERO3 when is_start = '1' else bitn_inc;
  bitn_en <= sample and (is_start or is_data);
  bitn_reg : entity work.reg_n generic map (W => 3)
    port map (clk => clk, en => bitn_en, d => bitn_d, q => bitn);

  shreg_d  <= rx_bit & shreg(7 downto 1);
  shreg_en <= is_data and full_end;
  shreg_reg : entity work.reg_n generic map (W => 8)
    port map (clk => clk, en => shreg_en, d => shreg_d, q => shreg);

  valid_d <= "1" when is_stop = '1' and full_end = '1' and rx_bit = '1' else "0";
  valid_reg : entity work.reg_n generic map (W => 1)
    port map (clk => clk, en => ALWAYS, d => valid_d, q => valid_q);

  data  <= shreg;
  valid <= valid_q(0);
end architecture rtl;
