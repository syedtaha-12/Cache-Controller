----------------------------------------------------------------------------------
-- Company: Toronto Metropolitan University
-- Engineer: Anoosh Zaidi & Taha Syed
--
-- Module Name:    CacheHW_tb - Behavioral (testbench)
-- Project Name:   Memory Hierarchy: Cache Controller
-- Description:    Testbench that matches the hardware setup: CacheSystem is
--                 connected to SDRAM_model (on-chip main memory) exactly as in
--                 CacheTop, with a 20 ns (50 MHz) clock. It sends all 8 CPU_gen
--                 requests, checks the read data and reports how many clocks
--                 each request takes from cs rising to cpu_rdy rising.
--                 Used to produce the timing diagrams (Figures 5 to 7).
--                 Expected: T1 67, T2 3, T3 5, T4 5, T5 69, T6 69, T7 131, T8 133.
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity CacheHW_tb is
end CacheHW_tb;

architecture Behavioral of CacheHW_tb is

    constant CLK_PERIOD : time := 20 ns;                 -- 50 MHz, same as the board

    signal clk  : std_logic := '0';
    signal rst  : std_logic := '1';
    signal trig : std_logic := '0';

    -- Cache <-> main memory
    signal mem_dout  : std_logic_vector(7 downto 0);
    signal mem_din   : std_logic_vector(7 downto 0);
    signal mem_addr  : std_logic_vector(15 downto 0);
    signal mem_wr_rd : std_logic;
    signal mem_strb  : std_logic;

    -- CPU side
    signal cpu_din : std_logic_vector(7 downto 0);
    signal cpu_rdy : std_logic;
    signal cs      : std_logic;
    signal state   : std_logic_vector(3 downto 0);

    signal cycle : integer := 0;                         -- free-running clock counter

    -- Expected read data per transaction (-1 = write, no check)
    type exp_array is array (0 to 7) of integer;
    constant EXPECTED : exp_array := (-1, -1, 16#AA#, 16#BB#, 16#46#, 16#44#, -1, 16#06#);

begin

    clk <= not clk after CLK_PERIOD / 2;

    -- Count clocks so each transaction can be timed
    process(clk)
    begin
        if rising_edge(clk) then
            cycle <= cycle + 1;
        end if;
    end process;

    -- Device under test: cache system (CPU_gen + controller + cache BRAM)
    UUT : entity work.CacheSystem
        port map (
            clk => clk, rst => rst, trig => trig,
            mem_dout => mem_dout, mem_din => mem_din, mem_addr => mem_addr,
            mem_wr_rd => mem_wr_rd, mem_strb => mem_strb,
            cpu_din => cpu_din, cpu_rdy => cpu_rdy,
            dbg_state => state, dbg_cs => cs, dbg_wr_rd => open,
            dbg_cpu_addr => open, dbg_sram_addr => open, dbg_sram_wen => open
        );

    -- Main memory, as on the board
    MEM : entity work.SDRAM_model
        port map (
            clk => clk, addr => mem_addr, wr_rd => mem_wr_rd,
            memstrb => mem_strb, din => mem_din, dout => mem_dout
        );

    -- Stimulus: reset, then fire the 8 CPU_gen requests one at a time
    stim : process
        variable start_cycle : integer;
    begin
        wait for 100 ns;
        wait until falling_edge(clk);
        rst <= '0';
        wait for 60 ns;

        for i in 0 to 7 loop
            wait until falling_edge(clk);
            trig <= '1';
            wait for 2 * CLK_PERIOD;
            trig <= '0';

            wait until cs = '1';
            start_cycle := cycle;
            wait until cpu_rdy = '0';
            wait until cpu_rdy = '1';

            if EXPECTED(i) >= 0 then
                assert to_integer(unsigned(cpu_din)) = EXPECTED(i)
                    report "T" & integer'image(i + 1) & ": WRONG read data"
                    severity error;
            end if;

            report "T" & integer'image(i + 1) & ": cs -> rdy = "
                & integer'image(cycle - start_cycle) & " cycles";

            wait for 10 * CLK_PERIOD;
        end loop;

        report "All 8 transactions done.";
        wait;
    end process;

end Behavioral;
