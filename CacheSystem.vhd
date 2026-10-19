----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date:    19:51:33 10/16/2026 
-- Design Name: 
-- Module Name:    CacheSystem - Behavioral 
-- Project Name: 
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

entity CacheSystem is
    Port (
        clk : in STD_LOGIC;
        rst : in STD_LOGIC;
        trig : in STD_LOGIC;

        -- SDRAM controller interface
        mem_dout : in STD_LOGIC_VECTOR(7 downto 0);
        mem_din : out STD_LOGIC_VECTOR(7 downto 0);
        mem_addr : out STD_LOGIC_VECTOR(15 downto 0);
        mem_wr_rd : out STD_LOGIC;
        mem_strb : out STD_LOGIC;

        -- CPU response
        cpu_din : out STD_LOGIC_VECTOR(7 downto 0);
        cpu_rdy : out STD_LOGIC;

        -- Debug outputs (for ChipScope on hardware)
        dbg_state : out STD_LOGIC_VECTOR(3 downto 0);
        dbg_cs : out STD_LOGIC;
        dbg_wr_rd : out STD_LOGIC;
        dbg_cpu_addr : out STD_LOGIC_VECTOR(15 downto 0);
        dbg_sram_addr : out STD_LOGIC_VECTOR(7 downto 0);
        dbg_sram_wen : out STD_LOGIC
    );
end CacheSystem;

architecture Structural of CacheSystem is

    COMPONENT bram
        PORT (
            clka : IN STD_LOGIC;
            wea : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
            addra : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
            dina : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
            douta : OUT STD_LOGIC_VECTOR(7 DOWNTO 0)
        );
    END COMPONENT;

    signal cpu_addr_s : STD_LOGIC_VECTOR(15 downto 0);
    signal cpu_data_s : STD_LOGIC_VECTOR(7 downto 0);
	 signal saved_cpu_data	:	STD_LOGIC_VECTOR(7 downto 0);
	 signal cpu_cs_prev		:	STD_LOGIC := '0';
    signal cpu_wr_rd_s : STD_LOGIC;
    signal cpu_cs_s : STD_LOGIC;

    signal sram_addr_s : STD_LOGIC_VECTOR(7 downto 0);
    signal sram_wen_s : STD_LOGIC;
    signal sram_we_vec : STD_LOGIC_VECTOR(0 downto 0);
    signal sram_din_s : STD_LOGIC_VECTOR(7 downto 0);
    signal sram_dout_s : STD_LOGIC_VECTOR(7 downto 0);

    signal mux1_sel_s : STD_LOGIC;
    signal mux2_sel_s : STD_LOGIC;

begin

	process(clk, rst)
	begin
		if rst = '1' then
			saved_cpu_data <= (others => '0');
			cpu_cs_prev <= '0';
			
		elsif rising_edge(clk) then
			cpu_cs_prev <= cpu_cs_s;
			
			if cpu_cs_s = '1' and cpu_cs_prev = '0' then
				saved_cpu_data <= cpu_data_s;
			end if;
		end if;
	end process;

    -- CPU transaction generator
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

    -- Cache controller
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

    -- Debug connections
    dbg_cs <= cpu_cs_s;
    dbg_wr_rd <= cpu_wr_rd_s;
    dbg_cpu_addr <= cpu_addr_s;
    dbg_sram_addr <= sram_addr_s;
    dbg_sram_wen <= sram_wen_s;

    -- MUX1: selects data written into SRAM
    sram_din_s <= cpu_data_s when mux1_sel_s = '0'
                  else mem_dout;

    -- MUX2 (demux): sends SRAM output to the CPU (sel = 1)
    -- or to the SDRAM (sel = 0), like Figure 3.
    cpu_din <= sram_dout_s when mux2_sel_s = '1' else (others => '0');
    mem_din <= sram_dout_s when mux2_sel_s = '0' else (others => '0');

    -- Convert scalar write enable to 1-bit vector
    sram_we_vec(0) <= sram_wen_s;

    -- Cache SRAM
    CACHE_RAM : bram
        port map (
            clka => clk,
            wea => sram_we_vec,
            addra => sram_addr_s,
            dina => sram_din_s,
            douta => sram_dout_s
        );

end Structural;
