-- cpu.vhd: Simple 8-bit CPU (BrainFuck interpreter)
-- Copyright (C) 2022 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): xhubin04
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
 port (
   CLK   : in std_logic;  -- hodinovy signal
   RESET : in std_logic;  -- asynchronni reset procesoru
   EN    : in std_logic;  -- povoleni cinnosti procesoru
 
   -- synchronni pamet RAM
   DATA_ADDR  : out std_logic_vector(12 downto 0); -- adresa do pameti
   DATA_WDATA : out std_logic_vector(7 downto 0); -- mem[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
   DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
   DATA_RDWR  : out std_logic;                    -- cteni (0) / zapis (1)
   DATA_EN    : out std_logic;                    -- povoleni cinnosti
   
   -- vstupni port
   IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA <- stav klavesnice pokud IN_VLD='1' a IN_REQ='1'
   IN_VLD    : in std_logic;                      -- data platna
   IN_REQ    : out std_logic;                     -- pozadavek na vstup data
   
   -- vystupni port
   OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
   OUT_BUSY : in std_logic;                       -- LCD je zaneprazdnen (1), nelze zapisovat
   OUT_WE   : out std_logic                       -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'
 );
end cpu;


-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of cpu is
  -- program counter
  signal pc_dout : std_logic_vector(12 downto 0);
  signal pc_inc : std_logic;
  signal pc_dec : std_logic;
  -- pointer counter
  signal ptr_dout : std_logic_vector(12 downto 0);
  signal ptr_inc : std_logic;
  signal ptr_dec : std_logic;
  -- cycle counter
  signal cnt_dout : std_logic_vector(12 downto 0);
  signal cnt_inc : std_logic;
  signal cnt_dec : std_logic;
  -- first MX
  signal mx_1_sel : std_logic;
  -- second MX
  signal mx_2_sel : std_logic_vector(1 downto 0);
  -- EQ
  signal eq_out : std_logic;
  -- 
  type STATE_TYPE is (
    s_start, 
    s_init, 
    s_fetch, 
    s_exec, 
    s_inc, 
    s_dec, 
    s_print_1, 
    s_print_2, 
    s_scan_1, s_scan_2, 
    s_stop, 
    s_while_start_1, s_while_start_2, s_while_start_3,
    s_while_end_1, s_while_end_2, s_while_end_3, s_while_end_4, s_while_end_5
    ); 
  signal curr_state : STATE_TYPE := s_start;
  signal next_state : STATE_TYPE := s_fetch;

begin
  -- Program Counter
  PC: process(CLK, RESET)
  begin
    if (RESET = '1') then 
      pc_dout <= (others => '0');
    elsif (rising_edge(CLK)) then
      if (pc_inc = '1') then
        pc_dout <= pc_dout + 1;
      elsif (pc_dec = '1') then 
        pc_dout <= pc_dout - 1;
      end if;
    end if; 
  end process PC; 

  -- Pointer to data memory 
  PTR: process(CLK, RESET)  
  begin 
    if (RESET = '1') then
      ptr_dout <= (12 => '1', others => '0');
    elsif (rising_edge(CLK)) then
      if (ptr_inc = '1') then
        ptr_dout <= ptr_dout + 1;
      elsif (ptr_dec = '1') then
        ptr_dout <= ptr_dout - 1;
      end if;
    end if;  
    ptr_dout(12) <= '1';
  end process PTR;

  -- Cycle counter
  CNT: process(CLK, RESET)
  begin 
    if (RESET = '1') then
      cnt_dout <= (others => '0');
    elsif (rising_edge(CLK)) then
      if (cnt_inc = '1') then
        cnt_dout <= cnt_dout + 1;
      elsif (cnt_dec = '1') then
        cnt_dout <= cnt_dout - 1;
      end if;
    end if;  
  end process CNT;

  -- MX1
  with mx_1_sel select
    DATA_ADDR <= pc_dout when '0',
            ptr_dout when '1',
            (others => '0') when others;

  -- MX2
  with mx_2_sel select
    DATA_WDATA <= IN_DATA when "00",
            DATA_RDATA + 1 when "01",
            DATA_RDATA - 1 when "10",
            (others => '0') when others;

  -- EQ
  EQ: process(CLK, RESET) 
  begin
    if (RESET = '1') then
      eq_out <= '0';
    elsif (rising_edge(CLK)) then
      if (cnt_dout = 0) then
        eq_out <= '0';
      else 
        eq_out <= '1';
      end if;
    end if;
  end process EQ;

  -- FSM
  state_logic: process(CLK, RESET, EN) is   
  begin
    if (RESET = '1') then 
      curr_state <= s_init;
    elsif (rising_edge(CLK)) then
      if (EN = '1') then
        curr_state <= next_state;
      end if;
    end if; 
  end process;

  FSM: process(CLK, RESET, curr_state, next_state)
  begin
    pc_inc <= '0';
    pc_dec <= '0';
    ptr_inc <= '0';
    ptr_dec <= '0';
    cnt_inc <= '0';
    cnt_dec <= '0';
    mx_1_sel <= '0';
    mx_2_sel <= "00";
    DATA_EN <= '0';
    DATA_RDWR <= '0';
    OUT_WE <= '0';
    IN_REQ <= '0';

    case curr_state is 
      when s_start =>
        next_state <= s_fetch;

      when s_init =>
        next_state <= s_fetch;

      when s_fetch =>
        DATA_EN <= '1';
        DATA_RDWR <= '0';
        mx_1_sel <= '0';
        next_state <= s_exec;

      when s_stop => 
        next_state <= s_stop;

      when s_exec =>
        case DATA_RDATA is 
          when x"3E" => 
            ptr_inc <= '1';
            pc_inc <= '1';
            next_state <= s_fetch;
          when x"3C" => 
            ptr_dec <= '1';
            pc_inc <= '1';
            next_state <= s_fetch;
          when x"2B" =>
            DATA_EN <= '1';
            DATA_RDWR <= '0';
            mx_1_sel <= '1';
            pc_inc <= '1';
            next_state <= s_inc;
          when x"2D" =>
            DATA_EN <= '1';
            DATA_RDWR <= '0';
            mx_1_sel <= '1';
            pc_inc <= '1'; 
            next_state <= s_dec;
          when x"2E" =>
            pc_inc <= '1';
            next_state <= s_print_1;
          when x"2C" =>
            pc_inc <= '1';
            next_state <= s_scan_1;
          when x"5B" => 
            pc_inc <= '1';
            DATA_EN <= '1';
            DATA_RDWR <= '0';
            mx_1_sel <= '1';
            next_state <= s_while_start_1;
          when x"5D" | x"29" => 
            DATA_EN <= '1';
            DATA_RDWR <= '0';
            mx_1_sel <= '1';
            next_state <= s_while_end_1;
          when x"28" =>
            pc_inc <= '1';
            next_state <= s_fetch;
          when x"00" => -- stop
            next_state <= s_stop;
          when others => 
            pc_inc <= '1';
            next_state <= s_fetch;
        end case;

    -- INC
    when s_inc =>
      DATA_EN <= '1';
      DATA_RDWR <= '1';
      mx_1_sel <= '1';
      mx_2_sel <= "01";
      next_state <= s_fetch;

    -- DEC
    when s_dec =>
      DATA_EN <= '1';
      DATA_RDWR <= '1';
      mx_1_sel <= '1';
      mx_2_sel <= "10";
      next_state <= s_fetch;

    -- PRINT
    when s_print_1 =>
      mx_1_sel <= '1';
      DATA_EN <= '1';
      DATA_RDWR <= '0';
      next_state <= s_print_2;

    when s_print_2 =>
      if (OUT_BUSY = '0') then
        OUT_WE <= '1';
        OUT_DATA <= DATA_RDATA;
        next_state <= s_fetch;
      else 
        next_state <= s_print_2;
      end if;

    -- SCAN
    when s_scan_1 =>
      IN_REQ <= '1';
      DATA_EN <= '1';
      DATA_RDWR <= '0';
      mx_1_sel <= '1';
      mx_2_sel <= "00";
      next_state <= s_scan_2;
      
    when s_scan_2 =>
      IN_REQ <= '1';
      DATA_EN <= '1';
      DATA_RDWR <= '1';
      mx_1_sel <= '1';
      mx_2_sel <= "00";
      if (IN_VLD /= '1') then
        next_state <= s_scan_1;
      else 
        next_state <= s_fetch;
      end if;

    -- WHILE_START, DOWHILE_END
    when s_while_start_1 =>
      if (DATA_RDATA = 0) then
        cnt_inc <= '1';
        next_state <= s_while_start_2;
      else
        next_state <= s_fetch;
      end if;

    when s_while_start_2 =>
      if (cnt_dout /= 0) then
        DATA_EN <= '1';
        DATA_RDWR <= '0';
        mx_1_sel <= '0';
        next_state <= s_while_start_3;
      else 
        next_state <= s_fetch;
      end if;

    when s_while_start_3 => 
      if ((DATA_RDATA = x"5B") or (DATA_RDATA = x"28")) then
        cnt_inc <= '1';
      elsif ((DATA_RDATA = x"5D") or (DATA_RDATA = x"29")) then
        cnt_dec <= '1';
      end if;
      pc_inc <= '1';
      next_state <= s_while_start_2;

    -- WHILE_END
    when s_while_end_1 =>
      if (DATA_RDATA = 0) then
        pc_inc <= '1';
        next_state <= s_fetch;
      else
        cnt_inc <= '1';
        pc_dec <= '1';
        next_state <= s_while_end_2;
      end if;
    
    when s_while_end_2 => 
      if (cnt_dout /= 0) then
        DATA_EN <= '1';
        DATA_RDWR <= '0';
        mx_1_sel <= '0';
        next_state <= s_while_end_3;
      else 
        next_state <= s_fetch;
      end if;

    when s_while_end_3 =>
      if ((DATA_RDATA = x"5B") or (DATA_RDATA = x"28")) then
        cnt_dec <= '1';
      elsif ((DATA_RDATA = x"5D") or (DATA_RDATA = x"29")) then
        cnt_inc <= '1';
      end if;
      next_state <= s_while_end_4;

    when s_while_end_4 =>
      if (cnt_dout = 0) then
        pc_inc <= '1';
        next_state <= s_fetch;
      else 
        pc_dec <= '1';
        next_state <= s_while_end_5;
      end if;

    when s_while_end_5 =>
      DATA_EN <= '1';
      DATA_RDWR <= '0';
      mx_1_sel <= '0';
      next_state <= s_while_end_2;

    when others => null;
    end case;
  end process FSM;
end behavioral;