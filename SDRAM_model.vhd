----------------------------------------------------------------------------------
-- Company: Toronto Metropolitan University
-- Engineer: Anoosh Zaidi & Taha Syed
-- Project Name: Memory Hierarchy: Cache Controller (COE758 Project 1)
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Simple main memory for running on the FPGA (stands in for the SDRAM).
-- 2 KB, uses address bits 10-0: every block the CPU_gen patterns touch
-- (0x1100, 0x3340, 0x4440, 0x5500, 0x6600) maps to a different location.
-- Each byte starts as the low 8 bits of its address (0x3346 reads 0x46).
-- Read: data on dout one clock after addr. Write: on the rising edge when
-- memstrb = 1 and wr_rd = 1.

entity SDRAM_model is
	Port(
		clk		:	in STD_LOGIC;                        -- system clock
		addr		:	in STD_LOGIC_VECTOR(15 downto 0);    -- byte address from the controller
		wr_rd		:	in STD_LOGIC;                        -- 1 = write, 0 = read
		memstrb	:	in STD_LOGIC;                        -- strobe: one clock per byte
		din		:	in STD_LOGIC_VECTOR(7 downto 0);     -- write data (from MUX2)
		dout		:	out STD_LOGIC_VECTOR(7 downto 0)     -- read data (to MUX1)
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

	signal mem : mem_type := init_mem;                  -- memory array (inferred block RAM)

	signal index : integer range 0 to 2047;             -- addr bits 10-0 as an integer

begin

	index <= to_integer(unsigned(addr(10 downto 0)));

	-- Process: synchronous write on strobe, synchronous read every clock
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
