
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
            cpu_rdy : out std_logic
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
            cpu_rdy => cpu_rdy
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

            report "Transaction " & integer'image(i + 1)
                & " complete. SDRAM reads = "
                & integer'image(read_count)
                & ", SDRAM writes = "
                & integer'image(write_count);

            -- Give CPU_gen time to return to IDLE.
            wait for 5 * clk_period;

        end loop;

        report "All eight CPU transactions completed.";

        wait;
    end process;

end behavior;
