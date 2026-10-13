library ieee;
use ieee.std_logic_1164.all;
use work.mlp_params.all;

entity hidden_tx is
  generic (
    CLKS_PER_BIT : integer := 868
  );
  port (
    clk    : in  std_logic;
    rst    : in  std_logic;
    send   : in  std_logic;
    hidden : in  std_logic_vector(N_HIDDEN*HIDDEN_W-1 downto 0);
    tx     : out std_logic
  );
end entity hidden_tx;

architecture rtl of hidden_tx is
  constant PACKET_BYTES : integer := N_HIDDEN + 2;
  constant HEADER : std_logic_vector(7 downto 0) := "10100101";
  constant FOOTER : std_logic_vector(7 downto 0) := "01011010";
  constant LAST   : std_logic_vector(5 downto 0) := "100001";
  constant ZERO6  : std_logic_vector(5 downto 0) := "000000";
  constant ALWAYS : std_logic := '1';

  signal active_d, active_q : std_logic_vector(0 downto 0);
  signal active, start, tx_go, tx_busy : std_logic;
  signal buf, buf_d         : std_logic_vector(PACKET_BYTES*8-1 downto 0);
  signal buf_en             : std_logic;
  signal n, n_inc, n_d      : std_logic_vector(5 downto 0);
  signal n_en, last_byte    : std_logic;
begin
  active    <= active_q(0);
  start     <= send and not active;
  tx_go     <= active and not tx_busy;
  last_byte <= '1' when n = LAST else '0';

  active_d <= "0" when rst = '1' else
              "1" when start = '1' else
              "0" when tx_go = '1' and last_byte = '1' else
              active_q;
  active_reg : entity work.reg_n generic map (W => 1)
    port map (clk => clk, en => ALWAYS, d => active_d, q => active_q);

  buf_d  <= FOOTER & hidden & HEADER when start = '1' else
            x"00" & buf(PACKET_BYTES*8-1 downto 8);
  buf_en <= start or tx_go;
  buf_reg : entity work.reg_n generic map (W => PACKET_BYTES*8)
    port map (clk => clk, en => buf_en, d => buf_d, q => buf);

  n_add : entity work.adder_n generic map (N => 6)
    port map (a => n, b => ZERO6, cin => '1', s => n_inc);
  n_d  <= ZERO6 when start = '1' else n_inc;
  n_en <= start or tx_go;
  n_reg : entity work.reg_n generic map (W => 6)
    port map (clk => clk, en => n_en, d => n_d, q => n);

  utx : entity work.uart_tx generic map (CLKS_PER_BIT => CLKS_PER_BIT)
    port map (clk => clk, send => tx_go, data => buf(7 downto 0), tx => tx, busy => tx_busy);
end architecture rtl;
