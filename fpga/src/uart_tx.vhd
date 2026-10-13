library ieee;
use ieee.std_logic_1164.all;
use work.bits_pkg.all;

entity uart_tx is
  generic (
    CLKS_PER_BIT : integer := 868
  );
  port (
    clk  : in  std_logic;
    send : in  std_logic;
    data : in  std_logic_vector(7 downto 0);
    tx   : out std_logic;
    busy : out std_logic
  );
end entity uart_tx;

architecture rtl of uart_tx is
  constant CNT_W   : integer := 10;
  constant FULL_M1 : std_logic_vector(CNT_W-1 downto 0) := to_bits(CLKS_PER_BIT - 1, CNT_W);
  constant ZERO    : std_logic_vector(CNT_W-1 downto 0) := (others => '0');
  constant ZERO4   : std_logic_vector(3 downto 0) := "0000";
  constant LAST    : std_logic_vector(3 downto 0) := "1001";
  constant ALWAYS  : std_logic := '1';

  signal busy_d, busy_q      : std_logic_vector(0 downto 0);
  signal sending, go, full_end, last_end : std_logic;
  signal cnt, cnt_inc, cnt_d : std_logic_vector(CNT_W-1 downto 0);
  signal nbit, nbit_inc, nbit_d : std_logic_vector(3 downto 0);
  signal shreg, shreg_d      : std_logic_vector(9 downto 0);
  signal step                : std_logic;
begin
  sending  <= busy_q(0);
  go       <= send and not sending;
  full_end <= '1' when cnt = FULL_M1 else '0';
  last_end <= '1' when sending = '1' and full_end = '1' and nbit = LAST else '0';
  step     <= go or (sending and full_end);

  busy_d <= "1" when go = '1' else
            "0" when last_end = '1' else
            busy_q;
  busy_reg : entity work.reg_n generic map (W => 1)
    port map (clk => clk, en => ALWAYS, d => busy_d, q => busy_q);

  cnt_add : entity work.adder_n generic map (N => CNT_W)
    port map (a => cnt, b => ZERO, cin => '1', s => cnt_inc);
  cnt_d <= ZERO when sending = '0' or full_end = '1' else cnt_inc;
  cnt_reg : entity work.reg_n generic map (W => CNT_W)
    port map (clk => clk, en => ALWAYS, d => cnt_d, q => cnt);

  nbit_add : entity work.adder_n generic map (N => 4)
    port map (a => nbit, b => ZERO4, cin => '1', s => nbit_inc);
  nbit_d <= ZERO4 when go = '1' else nbit_inc;
  nbit_reg : entity work.reg_n generic map (W => 4)
    port map (clk => clk, en => step, d => nbit_d, q => nbit);

  shreg_d <= '1' & data & '0' when go = '1' else '1' & shreg(9 downto 1);
  shreg_reg : entity work.reg_n generic map (W => 10)
    port map (clk => clk, en => step, d => shreg_d, q => shreg);

  tx   <= shreg(0) when sending = '1' else '1';
  busy <= sending;
end architecture rtl;
