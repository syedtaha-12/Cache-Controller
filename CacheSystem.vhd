----------------------------------------------------------------------------------
-- Company: Toronto Metropolitan University
-- Engineer: Anoosh Zaidi & Taha Syed
-- Project Name: Memory Hierarchy: Cache Controller (COE758 Project 1)
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Complete cache system from Figure 3 of the handout.
-- Connects the CPU (CPU_gen), the cache controller, the local cache SRAM
-- (bram core) and the two data multiplexers. The SDRAM side is brought out
-- as ports so it can connect to the testbench memory (simulation) or
-- SDRAM_model (hardware).

entity CacheSystem is
    Port (
        clk : in STD_LOGIC;                              -- system clock
        rst : in STD_LOGIC;                              -- reset for CPU_gen and controller
        trig : in STD_LOGIC;                             -- rising edge = CPU sends its next request

        -- SDRAM controller interface
        mem_dout : in STD_LOGIC_VECTOR(7 downto 0);      -- data read from main memory
        mem_din : out STD_LOGIC_VECTOR(7 downto 0);      -- data written to main memory
        mem_addr : out STD_LOGIC_VECTOR(15 downto 0);    -- main memory byte address
        mem_wr_rd : out STD_LOGIC;                       -- 1 = write, 0 = read
        mem_strb : out STD_LOGIC;                        -- MEMSTRB, one clock per byte

        -- CPU response
        cpu_din : out STD_LOGIC_VECTOR(7 downto 0);      -- read data going back to the CPU
        cpu_rdy : out STD_LOGIC;                         -- RDY from the controller

        -- Debug outputs (for ChipScope on hardware)
        dbg_state : out STD_LOGIC_VECTOR(3 downto 0);    -- controller FSM state number
        dbg_cs : out STD_LOGIC;                          -- CPU cs
        dbg_wr_rd : out STD_LOGIC;                       -- CPU wr_rd
        dbg_cpu_addr : out STD_LOGIC_VECTOR(15 downto 0);-- CPU address
        dbg_sram_addr : out STD_LOGIC_VECTOR(7 downto 0);-- cache SRAM address
        dbg_sram_wen : out STD_LOGIC                     -- cache SRAM write enable
    );
end CacheSystem;

architecture Structural of CacheSystem is

    -- Component declaration: 256 x 8 single-port Block RAM (CORE Generator)
    -- used as the local cache SRAM. Read data appears one clock after addra.
    COMPONENT bram
        PORT (
            clka : IN STD_LOGIC;                         -- clock
            wea : IN STD_LOGIC_VECTOR(0 DOWNTO 0);       -- write enable
            addra : IN STD_LOGIC_VECTOR(7 DOWNTO 0);     -- address (Index & Offset)
            dina : IN STD_LOGIC_VECTOR(7 DOWNTO 0);      -- data in
            douta : OUT STD_LOGIC_VECTOR(7 DOWNTO 0)     -- data out
        );
    END COMPONENT;

    -- CPU -> controller / SRAM signals
    signal cpu_addr_s : STD_LOGIC_VECTOR(15 downto 0);   -- CPU address
    signal cpu_data_s : STD_LOGIC_VECTOR(7 downto 0);    -- CPU write data (DOut)
    signal cpu_wr_rd_s : STD_LOGIC;                      -- CPU read/write
    signal cpu_cs_s : STD_LOGIC;                         -- CPU request strobe

    -- Cache SRAM signals
    signal sram_addr_s : STD_LOGIC_VECTOR(7 downto 0);   -- SRAM address from controller
    signal sram_wen_s : STD_LOGIC;                       -- SRAM write enable from controller
    signal sram_we_vec : STD_LOGIC_VECTOR(0 downto 0);   -- write enable as the 1-bit vector bram needs
    signal sram_din_s : STD_LOGIC_VECTOR(7 downto 0);    -- SRAM data in (MUX1 output)
    signal sram_dout_s : STD_LOGIC_VECTOR(7 downto 0);   -- SRAM data out (into MUX2)

    -- Data path selects from controller
    signal mux1_sel_s : STD_LOGIC;                       -- 0 = CPU data, 1 = SDRAM data
    signal mux2_sel_s : STD_LOGIC;                       -- 1 = to CPU, 0 = to SDRAM

begin

    -- Instantiation: CPU transaction generator (given by the course).
    -- Sends one of 8 fixed read/write requests on each rising edge of trig.
    CPU_UNIT : entity work.CPU_gen
        port map (
            clk => clk,
            rst => rst,
            trig => trig,
            Address => cpu_addr_s,
            wr_rd => cpu_wr_rd_s,
            cs => cpu_cs_s,
            DOut => cpu_data_s
        );

    -- Instantiation: cache controller (our design)
    CONTROLLER_UNIT : entity work.CacheController
        port map (
            clk => clk,
            rst => rst,
            cpu_addr => cpu_addr_s,
            cpu_wr_rd => cpu_wr_rd_s,
            cpu_cs => cpu_cs_s,
            cpu_rdy => cpu_rdy,
            sdram_addr => mem_addr,
            sdram_wr_rd => mem_wr_rd,
            sdram_mstrb => mem_strb,
            sram_addr => sram_addr_s,
            sram_wen => sram_wen_s,
            mux1_sel => mux1_sel_s,
            mux2_sel => mux2_sel_s,
            state_dbg => dbg_state
        );

    -- Debug connections to the top level (ChipScope)
    dbg_cs <= cpu_cs_s;
    dbg_wr_rd <= cpu_wr_rd_s;
    dbg_cpu_addr <= cpu_addr_s;
    dbg_sram_addr <= sram_addr_s;
    dbg_sram_wen <= sram_wen_s;

    -- MUX1: selects the data written into the SRAM
    -- (input 0 = CPU DOut for a CPU write, input 1 = SDRAM data for a block fetch)
    sram_din_s <= cpu_data_s when mux1_sel_s = '0'
                  else mem_dout;

    -- MUX2 (demux): sends the SRAM output to the CPU (sel = 1, read)
    -- or to the SDRAM (sel = 0, write-back), like Figure 3.
    cpu_din <= sram_dout_s when mux2_sel_s = '1' else (others => '0');
    mem_din <= sram_dout_s when mux2_sel_s = '0' else (others => '0');

    -- Convert scalar write enable to the 1-bit vector the bram core expects
    sram_we_vec(0) <= sram_wen_s;

    -- Instantiation: local cache SRAM (256 bytes = 8 blocks x 32 bytes)
    CACHE_RAM : bram
        port map (
            clka => clk,
            wea => sram_we_vec,
            addra => sram_addr_s,
            dina => sram_din_s,
            douta => sram_dout_s
        );

end Structural;
