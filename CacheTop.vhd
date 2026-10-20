----------------------------------------------------------------------------------
-- Company: Toronto Metropolitan University
-- Engineer: Anoosh Zaidi & Taha Syed
-- Project Name: Memory Hierarchy: Cache Controller (COE758 Project 1)
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Hardware top level (set as TOP in ISE).
--   CacheSystem  - CPU_gen + cache controller + cache BRAM
--   SDRAM_model  - main memory (block RAM on the FPGA)
--   ICON / ILA / VIO - ChipScope hub, logic analyzer and virtual I/O
-- VIO ASYNC_OUT: bit 0 = rst, bit 1 = trig (1 then 0 fires one CPU request)
-- ILA TRIG0: 0 cs (trigger on rising edge), 1 cpu_rdy, 2 mem_strb, 3 wr_rd, 7-4 state
-- ILA DATA:  3-0 state, 4 cs, 5 cpu_rdy, 6 wr_rd, 7 mem_strb, 8 mem_wr_rd,
--            9 sram_wen, 17-10 sram_addr, 25-18 SRAM data out, 31-26 tag bits 13-8

entity CacheTop is
	Port(
		clk	:	in STD_LOGIC                         -- 50 MHz board oscillator (pin C9)
	);
end CacheTop;

architecture Structural of CacheTop is

	-- Component declaration: ChipScope ICON, JTAG hub with 2 control ports (ILA, VIO)
	component icon
		port(
			CONTROL0	:	inout STD_LOGIC_VECTOR(35 downto 0);
			CONTROL1	:	inout STD_LOGIC_VECTOR(35 downto 0)
		);
	end component;

	-- Component declaration: ChipScope ILA, logic analyzer (32 data bits, 8 trigger bits, 512 samples)
	component ila
		port(
			CONTROL	:	inout STD_LOGIC_VECTOR(35 downto 0);
			CLK		:	in STD_LOGIC;
			DATA		:	in STD_LOGIC_VECTOR(31 downto 0);
			TRIG0		:	in STD_LOGIC_VECTOR(7 downto 0)
		);
	end component;

	-- Component declaration: ChipScope VIO, 18 outputs driven from the PC
	component vio
		port(
			CONTROL		:	inout STD_LOGIC_VECTOR(35 downto 0);
			ASYNC_OUT	:	out STD_LOGIC_VECTOR(17 downto 0)
		);
	end component;

	-- ChipScope
	signal control0	:	STD_LOGIC_VECTOR(35 downto 0);   -- ICON <-> ILA
	signal control1	:	STD_LOGIC_VECTOR(35 downto 0);   -- ICON <-> VIO
	signal vio_out		:	STD_LOGIC_VECTOR(17 downto 0);   -- VIO outputs (bit 0 rst, bit 1 trig)
	signal ila_data	:	STD_LOGIC_VECTOR(31 downto 0);   -- signals captured by the ILA
	signal ila_trig	:	STD_LOGIC_VECTOR(7 downto 0);    -- ILA trigger inputs

	-- Control from VIO
	signal rst	:	STD_LOGIC;
	signal trig	:	STD_LOGIC;

	-- Cache <-> main memory
	signal mem_dout	:	STD_LOGIC_VECTOR(7 downto 0);
	signal mem_din		:	STD_LOGIC_VECTOR(7 downto 0);
	signal mem_addr	:	STD_LOGIC_VECTOR(15 downto 0);
	signal mem_wr_rd	:	STD_LOGIC;
	signal mem_strb	:	STD_LOGIC;

	-- CPU side + debug
	signal cpu_din		:	STD_LOGIC_VECTOR(7 downto 0);
	signal cpu_rdy		:	STD_LOGIC;
	signal state		:	STD_LOGIC_VECTOR(3 downto 0);
	signal cs			:	STD_LOGIC;
	signal wr_rd		:	STD_LOGIC;
	signal cpu_addr	:	STD_LOGIC_VECTOR(15 downto 0);
	signal sram_addr	:	STD_LOGIC_VECTOR(7 downto 0);
	signal sram_wen	:	STD_LOGIC;

begin

	rst <= vio_out(0);
	trig <= vio_out(1);

	-- Instantiation: cache system (CPU + controller + cache BRAM + muxes)
	CACHE : entity work.CacheSystem
		port map(
			clk => clk,
			rst => rst,
			trig => trig,
			mem_dout => mem_dout,
			mem_din => mem_din,
			mem_addr => mem_addr,
			mem_wr_rd => mem_wr_rd,
			mem_strb => mem_strb,
			cpu_din => cpu_din,
			cpu_rdy => cpu_rdy,
			dbg_state => state,
			dbg_cs => cs,
			dbg_wr_rd => wr_rd,
			dbg_cpu_addr => cpu_addr,
			dbg_sram_addr => sram_addr,
			dbg_sram_wen => sram_wen
		);

	-- Instantiation: main memory (on-chip block RAM with the SDRAM controller interface)
	MAIN_MEM : entity work.SDRAM_model
		port map(
			clk => clk,
			addr => mem_addr,
			wr_rd => mem_wr_rd,
			memstrb => mem_strb,
			din => mem_din,
			dout => mem_dout
		);

	-- ChipScope signal mapping
	ila_trig(0) <= cs;
	ila_trig(1) <= cpu_rdy;
	ila_trig(2) <= mem_strb;
	ila_trig(3) <= wr_rd;
	ila_trig(7 downto 4) <= state;

	ila_data(3 downto 0) <= state;
	ila_data(4) <= cs;
	ila_data(5) <= cpu_rdy;
	ila_data(6) <= wr_rd;
	ila_data(7) <= mem_strb;
	ila_data(8) <= mem_wr_rd;
	ila_data(9) <= sram_wen;
	ila_data(17 downto 10) <= sram_addr;
	ila_data(25 downto 18) <= cpu_din or mem_din;  -- only one is non-zero
	ila_data(31 downto 26) <= mem_addr(13 downto 8);

	-- Instantiation: ChipScope cores (ICON hub -> ILA on CONTROL0, VIO on CONTROL1)
	ICON_UNIT : icon
		port map(
			CONTROL0 => control0,
			CONTROL1 => control1
		);

	ILA_UNIT : ila
		port map(
			CONTROL => control0,
			CLK => clk,
			DATA => ila_data,
			TRIG0 => ila_trig
		);

	VIO_UNIT : vio
		port map(
			CONTROL => control1,
			ASYNC_OUT => vio_out
		);

end Structural;
