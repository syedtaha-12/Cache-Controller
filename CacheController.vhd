----------------------------------------------------------------------------------
-- Company: Toronto Metropolitan University
-- Engineer: Anoosh Zaidi & Taha Syed
-- Project Name: Memory Hierarchy: Cache Controller (COE758 Project 1)
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Direct-mapped, write-back cache controller.
-- 8 blocks x 32 bytes (256 B). Address = Tag(15-8) | Index(7-5) | Offset(4-0).
-- Handles 4 cases: write hit, read hit, miss with dirty = 0
-- (fetch block) and miss with dirty = 1 (write back, then fetch).

entity CacheController is
	Port(
		clk	:	in STD_LOGIC;                        -- system clock (50 MHz on board)
		rst	:	in STD_LOGIC;                        -- async reset: clears valid/dirty bits, FSM to IDLE
		-- CPU interface
		cpu_addr	:	in STD_LOGIC_VECTOR(15 downto 0); -- address from CPU
		cpu_wr_rd	:	in STD_LOGIC;                  -- 1 = write, 0 = read
		cpu_cs	:	in STD_LOGIC;                     -- CPU request strobe (high for 4 clocks)
		cpu_rdy	:	out STD_LOGIC;                    -- 1 = idle / request finished, 0 = busy
		-- SDRAM controller interface
		sdram_addr	:	out STD_LOGIC_VECTOR(15 downto 0); -- byte address in main memory
		sdram_wr_rd	:	out STD_LOGIC;                 -- 1 = write to SDRAM, 0 = read from SDRAM
		sdram_mstrb	:	out STD_LOGIC;                 -- memory strobe, one clock per byte
		-- Local cache SRAM (Block RAM) interface
		sram_addr	:	out STD_LOGIC_VECTOR(7 downto 0);  -- Index & Offset
		sram_wen	:	out STD_LOGIC;                    -- SRAM write enable
		-- Data path selects
		mux1_sel	:	out STD_LOGIC;                    -- SRAM DIN: 0 = CPU data, 1 = SDRAM data
		mux2_sel	: out STD_LOGIC;                     -- SRAM DOUT: 1 = to CPU, 0 = to SDRAM
		-- Debug: current FSM state as a number (for ChipScope)
		state_dbg	:	out STD_LOGIC_VECTOR(3 downto 0)
	);
end CacheController;

architecture Behavioral of CacheController is

-- Block status bits, one per cache block (bit n = block n)
signal valid_bits	:	STD_LOGIC_VECTOR(7 downto 0);   -- 1 = block holds real data
signal dirty_bits	:	STD_LOGIC_VECTOR(7 downto 0);   -- 1 = block changed since it was loaded

-- Tag storage: 8 blocks x 8-bit tag
type tag_array is array (0 to 7) of STD_LOGIC_VECTOR(7 downto 0);
signal stored_tag	:	tag_array;                        -- tag of the memory block held in each cache block

-- Address Word Register (AWR): CPU request saved when cs is seen
signal saved_addr	:	STD_LOGIC_VECTOR(15 downto 0);  -- saved CPU address
signal saved_wr_rd	:	STD_LOGIC;                      -- saved read/write flag

-- AWR fields
signal cpu_tag	: STD_LOGIC_VECTOR(7 downto 0);         -- address bits 15-8
signal cpu_index	:	STD_LOGIC_VECTOR(2 downto 0);     -- address bits 7-5 (which block)
signal cpu_offset	:	STD_LOGIC_VECTOR(4 downto 0);     -- address bits 4-0 (which byte)

signal block_index	:	integer range 0 to 7;           -- cpu_index as an integer, for array lookups

signal cache_hit	:	STD_LOGIC;                        -- 1 = valid block with matching tag

signal byte_counter	:	integer range 0 to 31;         -- byte number during write-back / fetch

type state_type is (
	IDLE,
	CHECK,
	-- Write-back: 2 clocks per byte (set address, then strobe)
	WB_SETUP,
	WB_STROBE,
	-- Fetch: 2 clocks per byte (set address, then strobe + write SRAM)
	FETCH_SETUP,
	FETCH_STROBE,
	READ_SETUP,
	READ_WAIT,
	COMPLETE_READ,
	COMPLETE_WRITE,
	WAIT_RELEASE
);

signal current_state	:	state_type;                    -- FSM state register

signal transfer_offset	:	std_logic_vector(4 downto 0);  -- byte_counter as a 5-bit offset

begin

-- State number for ChipScope:
-- 0=IDLE 1=CHECK 2=WB_SETUP 3=WB_STROBE 4=FETCH_SETUP 5=FETCH_STROBE
-- 6=READ_SETUP 7=READ_WAIT 8=COMPLETE_READ 9=COMPLETE_WRITE 10=WAIT_RELEASE
state_dbg <= STD_LOGIC_VECTOR(to_unsigned(state_type'pos(current_state), 4));

-- Split the AWR into its fields
cpu_tag <= saved_addr(15 downto 8);
cpu_index <= saved_addr(7 downto 5);
cpu_offset <= saved_addr(4 downto 0);

block_index <= to_integer(unsigned(cpu_index));

transfer_offset <= 
	STD_LOGIC_VECTOR(to_unsigned(byte_counter, 5));

-- Hit = selected block is valid AND its stored tag matches the CPU tag
cache_hit <= '1' when (
	valid_bits(block_index) = '1' and cpu_tag = stored_tag(block_index)
) else '0';

----------------------------------------------------------------------------------
-- Process 1: state register and next-state logic (clocked)
-- Also updates the AWR, byte counter, tags, valid bits and dirty bits.
----------------------------------------------------------------------------------
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

		-- Wait for a CPU request, then save it in the AWR
		when IDLE =>
			if cpu_cs = '1' then
				saved_addr <= cpu_addr;
				saved_wr_rd <= cpu_wr_rd;
				current_state <= CHECK;
			end if;

		-- Decide: hit (read/write), miss + dirty (write back), or miss + clean (fetch)
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

		-- Address goes out here. SRAM data is ready next clock.
		when WB_SETUP =>
			current_state <= WB_STROBE;

		-- Strobe SDRAM to write the byte, then move to the next one
		when WB_STROBE =>
			if byte_counter = 31 then
				byte_counter <= 0;
				current_state <= FETCH_SETUP;
			else
				byte_counter <= byte_counter + 1;
				current_state <= WB_SETUP;
			end if;

		-- Address goes out here. SDRAM data is ready next clock.
		when FETCH_SETUP =>
			current_state <= FETCH_STROBE;

		-- Strobe SDRAM and write its data into the cache SRAM
		when FETCH_STROBE =>
			if byte_counter = 31 then
				-- Last byte: block is now loaded, record its tag and status
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

		-- Finish the original CPU request (now a hit)

		-- Read: put Index & Offset on the SRAM, wait 1 clock for data, hold it for the CPU
		when READ_SETUP => 
			current_state <= READ_WAIT;

		when READ_WAIT =>
			current_state <= COMPLETE_READ;

		when COMPLETE_READ =>
			current_state <=  WAIT_RELEASE;

		-- Write: byte written into SRAM this clock; block is now changed (dirty)
		when COMPLETE_WRITE =>
			dirty_bits(block_index) <= '1';
			valid_bits(block_index) <= '1';
			current_state <= WAIT_RELEASE;

		-- Request done (rdy = 1); wait for the CPU to drop cs before taking a new one
		when WAIT_RELEASE =>
			if cpu_cs = '0' then
				current_state <= IDLE;
			end if;

		end case;
	end if;
end process;

----------------------------------------------------------------------------------
-- Process 2: output logic (combinational, Moore: outputs depend on the state only)
-- Drives RDY, the SRAM and SDRAM addresses/controls and the mux selects.
----------------------------------------------------------------------------------
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

		-- WRITE BACK: old block -> SDRAM at stored Tag & Index & byte
		when WB_SETUP | WB_STROBE =>
			sram_addr <= cpu_index & transfer_offset;
			sdram_addr <= stored_tag(block_index) & cpu_index & transfer_offset;
			sram_wen <= '0';
			sdram_wr_rd <= '1';
			mux2_sel <= '0';                  -- SRAM DOUT -> SDRAM DIN
			if current_state = WB_STROBE then
				sdram_mstrb <= '1';
			end if;

		-- FETCH: new block <- SDRAM at CPU Tag & Index & byte
		when FETCH_SETUP | FETCH_STROBE =>
			sram_addr <= cpu_index & transfer_offset;
			sdram_addr <= cpu_tag & cpu_index & transfer_offset;
			sdram_wr_rd <= '0';
			mux1_sel <= '1';                  -- SDRAM DOUT -> SRAM DIN
			if current_state = FETCH_STROBE then
				sdram_mstrb <= '1';
				sram_wen <= '1';
			end if;

		-- CPU READ: SRAM at Index & Offset -> CPU
		when READ_SETUP | READ_WAIT | COMPLETE_READ =>
			sram_addr <= cpu_index & cpu_offset;
			sram_wen <= '0';
			mux2_sel <= '1';                  -- SRAM DOUT -> CPU DIN

		-- CPU WRITE: CPU byte -> SRAM at Index & Offset
		when COMPLETE_WRITE =>
			sram_addr <= cpu_index & cpu_offset;
			sram_wen <= '1';
			mux1_sel <= '0';                  -- CPU DOUT -> SRAM DIN

		when WAIT_RELEASE =>
			cpu_rdy <= '1';
			sram_addr <= cpu_index & cpu_offset;
			mux2_sel <= '1';

	end case;
end process;

end Behavioral;
