----------------------------------------------------------------------------------
-- Company: Toronto Metropolitan University
-- Engineer: Anoosh Zaidi & Taha Syed
--
-- Module Name:    SDRAM_model - Behavioral
-- Project Name:   Memory Hierarchy: Cache Controller
-- Description:    Simple "main memory" for running on the FPGA.
--                 The board's real SDRAM is not used, so this block RAM
--                 stands in for it. It follows the same interface as the
--                 SDRAM controller in the handout (ADD, WR/RD, MEMSTRB,
--                 DIN, DOUT).
--
--                 Size: 2 KB (uses address bits 10..0). This is enough
--                 because every block the CPU_gen patterns touch
--                 (0x1100, 0x3340, 0x4440, 0x5500, 0x6600) lands in a
--                 different spot in the lower 11 bits.
--
--                 Each byte starts as the low 8 bits of its address
--                 (same as the testbench), so a fresh read of 0x3346
--                 returns 0x46.
--
--                 Read: data shows up on DOUT one clock after ADD is set.
--                 Write: happens on the rising edge when MEMSTRB = 1
--                        and WR/RD = 1.
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity SDRAM_model is
	Port(
		clk		:	in STD_LOGIC;
		addr		:	in STD_LOGIC_VECTOR(15 downto 0);
		wr_rd		:	in STD_LOGIC;
		memstrb	:	in STD_LOGIC;
		din		:	in STD_LOGIC_VECTOR(7 downto 0);
		dout		:	out STD_LOGIC_VECTOR(7 downto 0)
	);
end SDRAM_model;

architecture Behavioral of SDRAM_model is

	type mem_type is array (0 to 2047) of STD_LOGIC_VECTOR(7 downto 0);

	-- Fill each byte with the low 8 bits of its address
	function init_mem return mem_type is
		variable m : mem_type;
	begin
		for i in 0 to 2047 loop
			m(i) := STD_LOGIC_VECTOR(to_unsigned(i mod 256, 8));
		end loop;
		return m;
	end function;

	signal mem : mem_type := init_mem;

	signal index : integer range 0 to 2047;

begin

	index <= to_integer(unsigned(addr(10 downto 0)));

	process(clk)
	begin
		if rising_edge(clk) then
			if memstrb = '1' and wr_rd = '1' then
				mem(index) <= din;
			end if;
			dout <= mem(index);
		end if;
	end process;

end Behavioral;
