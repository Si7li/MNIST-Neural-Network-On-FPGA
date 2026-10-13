library ieee;
use ieee.std_logic_1164.all;
use work.mlp_params.all;

entity frame_rx is
  port (
    clk       : in  std_logic;
    rst       : in  std_logic;
    byte      : in  std_logic_vector(7 downto 0);
    byte_ok   : in  std_logic;
    core_busy : in  std_logic;
    pixels    : out std_logic_vector(N_IN*PIXEL_W-1 downto 0);
    start     : out std_logic;
    receiving : out std_logic
  );
end entity frame_rx;

architecture rtl of frame_rx is
  constant SYNC       : std_logic_vector(7 downto 0) := "10000000";
  constant ZERO_COUNT : std_logic_vector(INPUT_W-1 downto 0) := (others => '0');
  constant ALWAYS     : std_logic := '1';

  signal is_sync, is_pixel, take_pixel, frame_end : std_logic;
  signal recv_d, recv_q   : std_logic_vector(0 downto 0);
  signal start_d, start_q : std_logic_vector(0 downto 0);
  signal cnt, cnt_inc, cnt_d : std_logic_vector(INPUT_W-1 downto 0);
  signal cnt_en           : std_logic;
  signal buf, buf_d       : std_logic_vector(N_IN*PIXEL_W-1 downto 0);
begin
  is_sync    <= '1' when byte = SYNC else '0';
  is_pixel   <= '1' when byte(7 downto PIXEL_W) = "0000" else '0';
  take_pixel <= byte_ok and recv_q(0) and is_pixel;
  frame_end <= '1' when cnt = LAST_PIXEL else '0';

  recv_d <= "0" when rst = '1' else
            "1" when byte_ok = '1' and is_sync = '1' else
            "0" when take_pixel = '1' and frame_end = '1' else
            "0" when byte_ok = '1' and is_pixel = '0' else
            recv_q;
  recv_reg : entity work.reg_n generic map (W => 1)
    port map (clk => clk, en => ALWAYS, d => recv_d, q => recv_q);

  cnt_add : entity work.adder_n generic map (N => INPUT_W)
    port map (a => cnt, b => ZERO_COUNT, cin => '1', s => cnt_inc);
  cnt_d  <= ZERO_COUNT when is_sync = '1' else cnt_inc;
  cnt_en <= (byte_ok and is_sync) or take_pixel;
  cnt_reg : entity work.reg_n generic map (W => INPUT_W)
    port map (clk => clk, en => cnt_en, d => cnt_d, q => cnt);

  buf_d <= byte(PIXEL_W-1 downto 0) & buf(N_IN*PIXEL_W-1 downto PIXEL_W);
  buf_reg : entity work.reg_n generic map (W => N_IN*PIXEL_W)
    port map (clk => clk, en => take_pixel, d => buf_d, q => buf);

  start_d <= "0" when rst = '1' or core_busy = '1' else
             "1" when take_pixel = '1' and frame_end = '1' else
             start_q;
  start_reg : entity work.reg_n generic map (W => 1)
    port map (clk => clk, en => ALWAYS, d => start_d, q => start_q);

  pixels    <= buf;
  start     <= start_q(0);
  receiving <= recv_q(0);
end architecture rtl;
