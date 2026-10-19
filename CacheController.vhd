----------------------------------------------------------------------------------
-- Company: Toronto Metropolitan University
-- Engineer: Anoosh Zaidi & Taha Syed
-- 
-- Create Date:    18:43:06 10/06/2026 
-- Design Name: 
-- Module Name:    CacheController - Behavioral 
-- Project Name: Memory Hierarchy: Cache Controller
-- Target Devices: 
-- Tool versions: 
-- Description: 
--
-- Dependencies: 
--
-- Revision: 
-- Revision 0.01 - File Created
-- Additional Comments: 
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity CacheController is
	Port(
		clk	:	in STD_LOGIC;
		rst	:	in STD_LOGIC;
		cpu_addr	:	in STD_LOGIC_VECTOR(15 downto 0);
		cpu_wr_rd	:	in STD_LOGIC;
		cpu_cs	:	in STD_LOGIC;
		cpu_rdy	:	out STD_LOGIC;
		sdram_addr	:	out STD_LOGIC_VECTOR(15 downto 0);
		sdram_wr_rd	:	out STD_LOGIC;
		sdram_mstrb	:	out STD_LOGIC;
		sram_addr	:	out STD_LOGIC_VECTOR(7 downto 0);
		sram_wen	:	out STD_LOGIC;
		mux1_sel	:	out STD_LOGIC;
		mux2_sel	: out STD_LOGIC;
		-- Debug: current FSM state as a number (for ChipScope)
		state_dbg	:	out STD_LOGIC_VECTOR(3 downto 0)
	);
end CacheController;

architecture Behavioral of CacheController is

signal valid_bits	:	STD_LOGIC_VECTOR(7 downto 0);
signal dirty_bits	:	STD_LOGIC_VECTOR(7 downto 0);

--Creating a new data type since TAG has 8 blocks of 8 bits.
type tag_array is array (0 to 7) of STD_LOGIC_VECTOR(7 downto 0);
--Declare the signal using that new data type
signal stored_tag	:	tag_array;

signal saved_addr	:	STD_LOGIC_VECTOR(15 downto 0);
signal saved_wr_rd	:	STD_LOGIC;

signal cpu_tag	: STD_LOGIC_VECTOR(7 downto 0);
signal cpu_index	:	STD_LOGIC_VECTOR(2 downto 0);
signal cpu_offset	:	STD_LOGIC_VECTOR(4 downto 0);

signal block_index	:	integer range 0 to 7;

signal cache_hit	:	STD_LOGIC;

signal byte_counter	:	integer range 0 to 31;

type state_type is (
	IDLE,
	CHECK,
	
	WB_SETUP,
	WB_WAIT,
	WB_STROBE,
	WB_NEXT,
	
	FETCH_SETUP,
	FETCH_STROBE,
	FETCH_WAIT,
	FETCH_WRITE,
	FETCH_NEXT,
	
	READ_SETUP,
	READ_WAIT,
	COMPLETE_READ,
	COMPLETE_WRITE,
	WAIT_RELEASE
);

signal current_state	:	state_type;

signal transfer_offset	:	std_logic_vector(4 downto 0);

begin

-- State number for ChipScope (IDLE=0, CHECK=1, WB_SETUP=2 ... WAIT_RELEASE=15)
state_dbg <= STD_LOGIC_VECTOR(to_unsigned(state_type'pos(current_state), 4));

cpu_tag <= saved_addr(15 downto 8);
cpu_index <= saved_addr(7 downto 5);
cpu_offset <= saved_addr(4 downto 0);

block_index <= to_integer(unsigned(cpu_index));

transfer_offset <= 
	STD_LOGIC_VECTOR(to_unsigned(byte_counter, 5));
	
cache_hit <= '1' when (
	valid_bits(block_index) = '1' and cpu_tag = stored_tag(block_index)
) else '0';

process(clk, rst)
begin 
	if rst = '1' then
		valid_bits <= "00000000";
		dirty_bits <= "00000000";
		
		saved_addr <= (others => '0');
		saved_wr_rd <= '0';
		
		byte_counter <= 0;
		current_state <= IDLE;
		
	elsif rising_edge(clk) then
	
		case current_state is
		
		when IDLE =>
			if cpu_cs = '1' then
				saved_addr <= cpu_addr;
				saved_wr_rd <= cpu_wr_rd;
				current_state <= CHECK;
			end if;
			
		when CHECK =>
			byte_counter <= 0;
			
			if cache_hit = '1' then
				if saved_wr_rd = '1' then
					current_state <= COMPLETE_WRITE;
				else
					current_state <= READ_SETUP;
			end if;
			
			elsif valid_bits(block_index) = '1'
			and dirty_bits(block_index) = '1' then
				current_state <= WB_SETUP;
				
			else
				current_state <= FETCH_SETUP;
			end if;
			
		when WB_SETUP =>
			current_state <= WB_WAIT;
			
		when WB_WAIT =>
			current_state <= WB_STROBE;
			
		when WB_STROBE =>
			current_state <= WB_NEXT;
			
		when WB_NEXT =>
			if byte_counter = 31 then
				byte_counter <= 0;
				current_state <= FETCH_SETUP;
			else
				byte_counter <= byte_counter + 1;
				current_state <= WB_SETUP;
			end if;
			
		when FETCH_SETUP =>
			current_state <= FETCH_STROBE;
			
		when FETCH_STROBE =>
			current_state <= FETCH_WAIT;
			
		when FETCH_WAIT =>
			current_state <= FETCH_WRITE;
			
		when FETCH_WRITE =>
			current_state <= FETCH_NEXT;
			
		when FETCH_NEXT =>
			if byte_counter = 31 then
				
				stored_tag(block_index) <= cpu_tag;
				valid_bits(block_index) <= '1';
				dirty_bits(block_index) <= '0';
				
				byte_counter <= 0;
				
				if saved_wr_rd = '1' then
					current_state <= COMPLETE_WRITE;
				else
					current_state <= READ_SETUP;
				end if;

			else
				byte_counter <= byte_counter + 1;
				current_state <= FETCH_SETUP;
			end if;


-- COMPLETE ORIGINAL CPU REQUEST

		when READ_SETUP => 
			current_state <= READ_WAIT;
			
		when READ_WAIT =>
			current_state <= COMPLETE_READ;
			
		when COMPLETE_READ =>
			current_state <=  WAIT_RELEASE;
			
		when COMPLETE_WRITE =>
			dirty_bits(block_index) <= '1';
			valid_bits(block_index) <= '1';
			current_state <= WAIT_RELEASE;

		when WAIT_RELEASE =>
			if cpu_cs = '0' then
				current_state <= IDLE;
			end if;

		end case;
		
	end if;
end process;

-- MEMORY CONTROL OUTPUTS

process(current_state, cpu_index, cpu_offset, stored_tag, block_index, cpu_tag, transfer_offset)

begin

	-- Safe defaults
	cpu_rdy <= '0';

	sram_addr <= (others => '0');
	sram_wen <= '0';

	sdram_addr <= (others => '0');
	sdram_wr_rd <= '0';
	sdram_mstrb <= '0';

	mux1_sel <= '0';
	mux2_sel <= '1';


	case current_state is

		when IDLE =>
			cpu_rdy <= '1';

		when CHECK =>
			null;


	-- WRITE BACK
	when WB_SETUP | WB_WAIT | WB_STROBE | WB_NEXT =>

		sram_addr <= cpu_index & transfer_offset;

		sdram_addr <= stored_tag(block_index) & cpu_index & transfer_offset;

		sram_wen <= '0';
		sdram_wr_rd <= '1';

	-- SRAM DOUT -> SDRAM DIN
		mux2_sel <= '0';

		if current_state = WB_STROBE then
			sdram_mstrb <= '1';
		end if;


	-- FETCH
	when FETCH_SETUP | FETCH_STROBE |FETCH_WAIT | FETCH_WRITE |FETCH_NEXT =>

		sram_addr <= cpu_index & transfer_offset;

		sdram_addr <= cpu_tag & cpu_index & transfer_offset;

		sdram_wr_rd <= '0';

		-- SDRAM DOUT -> SRAM DIN
		mux1_sel <= '1';

		if current_state = FETCH_STROBE then
		sdram_mstrb <= '1';
		end if;

		if current_state = FETCH_WRITE then
			sram_wen <= '1';
		end if;


	-- CPU READ
	when READ_SETUP | READ_WAIT | COMPLETE_READ =>

		sram_addr <= cpu_index & cpu_offset;
		sram_wen <= '0';

		-- SRAM DOUT -> CPU DIN
		mux2_sel <= '1';


	-- CPU WRITE
	when COMPLETE_WRITE =>

		sram_addr <= cpu_index & cpu_offset;
		sram_wen <= '1';

	-- CPU DOUT -> SRAM DIN
		mux1_sel <= '0';


	when WAIT_RELEASE =>
		cpu_rdy <= '1';

		sram_addr <= cpu_index & cpu_offset;
		mux2_sel <= '1';

	end case;

	end process;

end Behavioral;


