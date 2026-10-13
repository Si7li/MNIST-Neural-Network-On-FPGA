library ieee;
use ieee.std_logic_1164.all;
use work.mlp_params.all;

entity nexys3_top is
  generic (
    CLKS_PER_BIT : integer := 868
  );
  port (
    clk     : in  std_logic;
    btn_rst : in  std_logic;
    rxd     : in  std_logic;
    txd     : out std_logic;
    seg     : out std_logic_vector(6 downto 0);
    dp      : out std_logic;
    an      : out std_logic_vector(3 downto 0);
    led     : out std_logic_vector(7 downto 0)
  );
end entity nexys3_top;

architecture structural of nexys3_top is
  constant ALWAYS : std_logic := '1';
  constant ZERO3  : std_logic_vector(2 downto 0) := "000";

  signal btn_in, rst_s1, rst_s2 : std_logic_vector(0 downto 0);
  signal rst                    : std_logic;
  signal div, div_inc           : std_logic_vector(2 downto 0);
  signal ce                     : std_logic;

  signal byte                   : std_logic_vector(7 downto 0);
  signal byte_ok                : std_logic;
  signal pixels                 : std_logic_vector(N_IN*PIXEL_W-1 downto 0);
  signal start, receiving       : std_logic;
  signal busy, done, valid      : std_logic;
  signal hidden                 : std_logic_vector(N_HIDDEN*HIDDEN_W-1 downto 0);
  signal digit                  : std_logic_vector(3 downto 0);
begin
  btn_in(0) <= btn_rst;
  rst_r1 : entity work.reg_n generic map (W => 1)
    port map (clk => clk, en => ALWAYS, d => btn_in, q => rst_s1);
  rst_r2 : entity work.reg_n generic map (W => 1)
    port map (clk => clk, en => ALWAYS, d => rst_s1, q => rst_s2);
  rst <= rst_s2(0);

  div_add : entity work.adder_n generic map (N => 3)
    port map (a => div, b => ZERO3, cin => '1', s => div_inc);
  div_reg : entity work.reg_n generic map (W => 3)
    port map (clk => clk, en => ALWAYS, d => div_inc, q => div);
  ce <= div(2) and div(1) and div(0);

  urx : entity work.uart_rx generic map (CLKS_PER_BIT => CLKS_PER_BIT)
    port map (clk => clk, rx => rxd, data => byte, valid => byte_ok);

  frame : entity work.frame_rx
    port map (clk => clk, rst => rst, byte => byte, byte_ok => byte_ok,
              core_busy => busy, pixels => pixels, start => start,
              receiving => receiving);

  core : entity work.mlp_par32
    port map (clk => clk, rst => rst, ce => ce, start => start, pixels => pixels,
              busy => busy, done => done, valid => valid, digit => digit,
              hidden => hidden);

  to_pc : entity work.hidden_tx generic map (CLKS_PER_BIT => CLKS_PER_BIT)
    port map (clk => clk, rst => rst, send => done, hidden => hidden, tx => txd);

  display : entity work.seg7
    port map (digit => digit, valid => valid, seg => seg, dp => dp, an => an);

  led(3 downto 0) <= digit;
  led(5 downto 4) <= "00";
  led(6)          <= receiving;
  led(7)          <= valid;
end architecture structural;
