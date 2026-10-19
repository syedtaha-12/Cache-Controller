
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity CacheSystem_tb is
end CacheSystem_tb;

architecture behavior of CacheSystem_tb is

    component CacheSystem
        port (
            clk : in std_logic;
            rst : in std_logic;
            trig : in std_logic;

            mem_dout : in std_logic_vector(7 downto 0);
            mem_din : out std_logic_vector(7 downto 0);
            mem_addr : out std_logic_vector(15 downto 0);
            mem_wr_rd : out std_logic;
            mem_strb : out std_logic;

            cpu_din : out std_logic_vector(7 downto 0);
            cpu_rdy : out std_logic;

            dbg_state : out std_logic_vector(3 downto 0);
            dbg_cs : out std_logic;
            dbg_wr_rd : out std_logic;
            dbg_cpu_addr : out std_logic_vector(15 downto 0);
            dbg_sram_addr : out std_logic_vector(7 downto 0);
            dbg_sram_wen : out std_logic
        );
    end component;

    signal clk : std_logic := '0';
    signal rst : std_logic := '1';
    signal trig : std_logic := '0';

    signal mem_dout : std_logic_vector(7 downto 0);
    signal mem_din : std_logic_vector(7 downto 0);
    signal mem_addr : std_logic_vector(15 downto 0);
    signal mem_wr_rd : std_logic;
    signal mem_strb : std_logic;

    signal cpu_din : std_logic_vector(7 downto 0);
    signal cpu_rdy : std_logic;

    constant clk_period : time := 10 ns;

    -- Simulated SDRAM: 65536 bytes
    type memory_type is array (0 to 65535) of
        std_logic_vector(7 downto 0);

    -- Initialize each address with its low 8 bits.
    function init_memory return memory_type is
        variable result : memory_type;
    begin
        for i in 0 to 65535 loop
            result(i) :=
                std_logic_vector(to_unsigned(i mod 256, 8));
        end loop;
        return result;
    end function;

    signal memory : memory_type := init_memory;

    -- Expected CPU read data for each transaction ("--" = write, no check)
    type exp_array is array (0 to 7) of std_logic_vector(7 downto 0);
    constant EXPECTED : exp_array := (
        "--------",  -- 1: write AA to 0x1100
        "--------",  -- 2: write BB to 0x1102
        x"AA",       -- 3: read 0x1100
        x"BB",       -- 4: read 0x1102
        x"46",       -- 5: read 0x3346 (fresh block from memory)
        x"44",       -- 6: read 0x4444 (fresh block from memory)
        "--------",  -- 7: write CC to 0x5504
        x"06"        -- 8: read 0x6606 (fresh block from memory)
    );

    signal read_count : integer := 0;
    signal write_count : integer := 0;

begin

    ---------------------------------------------------
    -- DEVICE UNDER TEST
    ---------------------------------------------------
    uut : CacheSystem
        port map (
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

            dbg_state => open,
            dbg_cs => open,
            dbg_wr_rd => open,
            dbg_cpu_addr => open,
            dbg_sram_addr => open,
            dbg_sram_wen => open
        );


    ---------------------------------------------------
    -- CLOCK GENERATOR
    ---------------------------------------------------
    clk_process : process
    begin
        clk <= '0';
        wait for clk_period / 2;
        clk <= '1';
        wait for clk_period / 2;
    end process;


    ---------------------------------------------------
    -- SIMULATED SDRAM READ
    ---------------------------------------------------
    -- This simple model exposes the addressed byte
    -- immediately, allowing the controller to read it.
    -- It is NOT a cycle-accurate SDRAM controller.

    mem_dout <= memory(to_integer(unsigned(mem_addr)));


    ---------------------------------------------------
    -- SIMULATED SDRAM WRITE AND TRANSACTION COUNTERS
    ---------------------------------------------------
    memory_process : process(clk)
    begin
        if rising_edge(clk) then

            if rst = '1' then
                read_count <= 0;
                write_count <= 0;

            elsif mem_strb = '1' then

                if mem_wr_rd = '1' then

                    memory(to_integer(unsigned(mem_addr)))
                        <= mem_din;

                    write_count <= write_count + 1;

                else

                    read_count <= read_count + 1;

                end if;

            end if;

        end if;
    end process;


    ---------------------------------------------------
    -- TEST STIMULUS
    ---------------------------------------------------
    stim_proc : process
    begin

        -- Reset system
        rst <= '1';
        trig <= '0';

        wait for 100 ns;
        wait until falling_edge(clk);
        rst <= '0';

        wait for 30 ns;

        -- CPU_gen contains eight predefined patterns.
        -- Trigger them one at a time.

        for i in 0 to 7 loop

            -- Wait until cache is ready
            if cpu_rdy /= '1' then
					wait until cpu_rdy = '1';
				end if;

            wait until falling_edge(clk);

            -- Trigger CPU generator
            trig <= '1';

            wait for 2 * clk_period;

            trig <= '0';

            -- Allow CPU_gen to assert CS and
            -- the controller to become busy.
            wait until cpu_rdy = '0';

            -- Wait for cache transaction completion
            if cpu_rdy /= '1' then
					wait until cpu_rdy = '1';
				end if;

            -- Check read data
            if EXPECTED(i) /= "--------" then
                assert cpu_din = EXPECTED(i)
                    report "Transaction " & integer'image(i + 1)
                        & ": WRONG read data"
                    severity error;
            end if;

            report "Transaction " & integer'image(i + 1)
                & " complete. SDRAM reads = "
                & integer'image(read_count)
                & ", SDRAM writes = "
                & integer'image(write_count);

            -- Give CPU_gen time to return to IDLE.
            wait for 5 * clk_period;

        end loop;

        -- Check the dirty blocks were written back to main memory
        assert memory(16#1100#) = x"AA" and memory(16#1102#) = x"BB"
            report "Write-back of block 0x1100 is WRONG" severity error;
        assert memory(16#5504#) = x"CC"
            report "Write-back of block 0x5500 is WRONG" severity error;

        report "All eight CPU transactions completed.";

        wait;
    end process;

end behavior;
