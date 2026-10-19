----------------------------------------------------------------------------------
-- Company: Toronto Metropolitan University
-- Engineer: Anoosh Zaidi & Taha Syed
--
-- Module Name:    CacheTop - Structural
-- Project Name:   Memory Hierarchy: Cache Controller
-- Target Device:  XC3S500E (Spartan-3E, FG320)
-- Description:    Hardware top level. Set this as the TOP module in ISE.
--
--                 CacheSystem  - CPU_gen + cache controller + cache BRAM
--                 SDRAM_model  - main memory (block RAM on the FPGA)
--                 ICON         - ChipScope JTAG hub (2 control ports)
--                 VIO          - lets you drive rst and trig from the PC
--                 ILA          - captures the signals for the waveform
--
-- VIO ASYNC_OUT:  bit 0 = rst   (set to 1 then back to 0 to reset)
--                 bit 1 = trig  (set 1 then 0 to fire one CPU transaction)
--
-- ILA TRIG0 (8 bits):
--   0     cs           <- trigger on this rising edge
--   1     cpu_rdy
--   2     mem_strb
--   3     cpu_wr_rd
--   7..4  state
--
-- ILA DATA (32 bits):
--   3..0    state      (0=IDLE 1=CHECK 2-5=WB_* 6-10=FETCH_*
--                       11=READ_SETUP 12=READ_WAIT 13=COMPLETE_READ
--                       14=COMPLETE_WRITE 15=WAIT_RELEASE)
--   4       cs
--   5       cpu_rdy
--   6       cpu_wr_rd
--   7       mem_strb
--   8       mem_wr_rd
--   9       sram_wen
--   17..10  sram_addr  (index & offset)
--   25..18  sram dout  (= data to CPU and data to SDRAM)
--   31..26  mem_addr(13..8)  (low 6 bits of the tag sent to SDRAM)
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity CacheTop is
	Port(
		clk	:	in STD_LOGIC
	);
end CacheTop;

architecture Structural of CacheTop is

	component icon
		port(
			CONTROL0	:	inout STD_LOGIC_VECTOR(35 downto 0);
			CONTROL1	:	inout STD_LOGIC_VECTOR(35 downto 0)
		);
	end component;

	component ila
		port(
			CONTROL	:	inout STD_LOGIC_VECTOR(35 downto 0);
			CLK		:	in STD_LOGIC;
			DATA		:	in STD_LOGIC_VECTOR(31 downto 0);
			TRIG0		:	in STD_LOGIC_VECTOR(7 downto 0)
		);
	end component;

	component vio
		port(
			CONTROL		:	inout STD_LOGIC_VECTOR(35 downto 0);
			ASYNC_OUT	:	out STD_LOGIC_VECTOR(17 downto 0)
		);
	end component;

	-- ChipScope
	signal control0	:	STD_LOGIC_VECTOR(35 downto 0);
	signal control1	:	STD_LOGIC_VECTOR(35 downto 0);
	signal vio_out		:	STD_LOGIC_VECTOR(17 downto 0);
	signal ila_data	:	STD_LOGIC_VECTOR(31 downto 0);
	signal ila_trig	:	STD_LOGIC_VECTOR(7 downto 0);

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

	-- Cache system (CPU + controller + cache BRAM)
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

	-- Main memory
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
	ila_data(25 downto 18) <= cpu_din;
	ila_data(31 downto 26) <= mem_addr(13 downto 8);

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
