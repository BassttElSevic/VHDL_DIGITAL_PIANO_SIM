-- =====================================================================
-- 第一部分：优先编码器元件 (保持不变)
-- =====================================================================
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;

ENTITY CODER IS
    PORT (
        K1IN : IN STD_LOGIC; K2IN : IN STD_LOGIC; K3IN : IN STD_LOGIC;
        K4IN : IN STD_LOGIC; K5IN : IN STD_LOGIC; K6IN : IN STD_LOGIC; K7IN : IN STD_LOGIC;
        CODER_OUTPUT : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
        KEY_PRESSED  : OUT STD_LOGIC  -- 新增：指示是否有键按下
    );
END ENTITY CODER;

ARCHITECTURE BEHAVIOR OF CODER IS
BEGIN
    -- 简单的按键按下检测 (假设低电平有效按键)
    KEY_PRESSED <= '1' WHEN (K1IN='0' OR K2IN='0' OR K3IN='0' OR K4IN='0' OR K5IN='0' OR K6IN='0' OR K7IN='0') ELSE '0';

    CODER_OUTPUT <= 
        "000" WHEN K1IN = '0' ELSE
        "001" WHEN K2IN = '0' ELSE
        "010" WHEN K3IN = '0' ELSE
        "011" WHEN K4IN = '0' ELSE
        "100" WHEN K5IN = '0' ELSE
        "101" WHEN K6IN = '0' ELSE
        "110" WHEN K7IN = '0' ELSE
        "111"; -- 111 代表无按键
END ARCHITECTURE BEHAVIOR;

-- =====================================================================
-- 第二部分：方波发生器元件 (保持不变)
-- =====================================================================
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;

ENTITY PULSE_GENERATOR IS
    PORT (
        CLK_IN      : IN STD_LOGIC;
        BINARY_CODE : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
        ENABLE      : IN STD_LOGIC; -- 新增：使能信号，用于静音控制
        PULSE_OUT   : OUT STD_LOGIC
    );
END ENTITY PULSE_GENERATOR;

ARCHITECTURE BEHAVIORAL OF PULSE_GENERATOR IS
    CONSTANT DO_COUNT    : INTEGER := 95556; CONSTANT RE_COUNT    : INTEGER := 85131;
    CONSTANT MI_COUNT    : INTEGER := 75843; CONSTANT FA_COUNT    : INTEGER := 71586;
    CONSTANT SOL_COUNT   : INTEGER := 63776; CONSTANT LA_COUNT    : INTEGER := 56818;
    CONSTANT TI_COUNT    : INTEGER := 50607;
    SIGNAL counter       : INTEGER RANGE 0 TO 100000 := 0;
    SIGNAL max_count     : INTEGER RANGE 0 TO 100000 := 0;
    SIGNAL pulse_reg     : STD_LOGIC := '0';
BEGIN
    PROCESS(BINARY_CODE)
    BEGIN
        CASE BINARY_CODE IS
            WHEN "000" => max_count <= DO_COUNT;
            WHEN "001" => max_count <= RE_COUNT;
            WHEN "010" => max_count <= MI_COUNT;
            WHEN "011" => max_count <= FA_COUNT;
            WHEN "100" => max_count <= SOL_COUNT;
            WHEN "101" => max_count <= LA_COUNT;
            WHEN "110" => max_count <= TI_COUNT;
            WHEN OTHERS => max_count <= 0;
        END CASE;
    END PROCESS;
    
    PROCESS(CLK_IN)
    BEGIN
        IF RISING_EDGE(CLK_IN) THEN
            IF ENABLE = '0' OR max_count = 0 THEN
                pulse_reg <= '0'; counter <= 0;
            ELSE
                IF counter >= max_count - 1 THEN
                    counter <= 0; pulse_reg <= NOT pulse_reg;
                ELSE
                    counter <= counter + 1;
                END IF;
            END IF;
        END IF;
    END PROCESS;
    PULSE_OUT <= pulse_reg;
END ARCHITECTURE BEHAVIORAL;

-- =====================================================================
-- 最终版：用锁定计时器解决抖动，不增加复杂状态
-- =====================================================================
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE. NUMERIC_STD. ALL;

ENTITY RECORDER_PLAYER IS
    PORT (
        CLK         : IN STD_LOGIC;
        RESET       : IN STD_LOGIC;
        KEY_CODE_IN : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
        KEY_PRESSED : IN STD_LOGIC;
        AGAIN_BTN   :  IN STD_LOGIC;
        
        AUDIO_CODE_OUT : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
        AUDIO_ENABLE   : OUT STD_LOGIC;
        
        LCD_CHAR_CODE : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
        LCD_WRITE_REQ : OUT STD_LOGIC;
        LCD_CLEAR_REQ : OUT STD_LOGIC
    );
END ENTITY RECORDER_PLAYER;

ARCHITECTURE BEHAVIOR OF RECORDER_PLAYER IS
    TYPE MEMORY_ARRAY IS ARRAY (0 TO 31) OF STD_LOGIC_VECTOR(2 DOWNTO 0);
    SIGNAL notes_memory : MEMORY_ARRAY := (OTHERS => "111");
    SIGNAL write_ptr    : INTEGER RANGE 0 TO 31 := 0;
    SIGNAL read_ptr     : INTEGER RANGE 0 TO 31 := 0;
    SIGNAL note_count   : INTEGER RANGE 0 TO 32 := 0;
    
    -- 简单状态机
    TYPE STATE_TYPE IS (IDLE, PLAYBACK, FINISH_CLEAR);
    SIGNAL state : STATE_TYPE := IDLE;
    
    SIGNAL timer : INTEGER RANGE 0 TO 30000000 := 0;
    
    -- 边沿检测
    SIGNAL key_prev   : STD_LOGIC := '0';
    SIGNAL again_prev : STD_LOGIC := '1';
    
    -- 关键：锁定计时器（按键后锁定一段时间，忽略所有输入）
    SIGNAL lockout_timer : INTEGER RANGE 0 TO 5000000 := 0;  -- 100ms @ 50MHz
    CONSTANT LOCKOUT_TIME : INTEGER := 5000000;
    
    -- 锁存的键码
    SIGNAL latched_code : STD_LOGIC_VECTOR(2 DOWNTO 0) := "111";
    
BEGIN
    PROCESS(CLK)
    BEGIN
        IF RISING_EDGE(CLK) THEN
            LCD_WRITE_REQ <= '0';
            LCD_CLEAR_REQ <= '0';
            
            CASE state IS
                WHEN IDLE =>
                    -- 锁定期间：继续发声，但忽略新的按键边沿
                    IF lockout_timer > 0 THEN
                        lockout_timer <= lockout_timer - 1;
                        -- 锁定期间使用锁存的键码发声
                        AUDIO_CODE_OUT <= latched_code;
                        AUDIO_ENABLE <= KEY_PRESSED;
                        -- 更新边沿检测（保持同步）
                        key_prev <= KEY_PRESSED;
                        again_prev <= AGAIN_BTN;
                    ELSE
                        -- 正常模式：透传并检测边沿
                        AUDIO_CODE_OUT <= KEY_CODE_IN;
                        AUDIO_ENABLE <= KEY_PRESSED;
                        
                        -- 检测 Again 按钮下降沿
                        IF again_prev = '1' AND AGAIN_BTN = '0' AND note_count > 0 THEN
                            state <= PLAYBACK;
                            read_ptr <= 0;
                            timer <= 0;
                        -- 检测音符键上升沿
                        ELSIF key_prev = '0' AND KEY_PRESSED = '1' THEN
                            IF note_count < 32 THEN
                                -- 锁存键码
                                latched_code <= KEY_CODE_IN;
                                -- 记录
                                notes_memory(write_ptr) <= KEY_CODE_IN;
                                IF write_ptr < 31 THEN
                                    write_ptr <= write_ptr + 1;
                                END IF;
                                note_count <= note_count + 1;
                                -- LCD显示
                                LCD_CHAR_CODE <= KEY_CODE_IN;
                                LCD_WRITE_REQ <= '1';
                                -- 启动锁定计时器
                                lockout_timer <= LOCKOUT_TIME;
                            END IF;
                        END IF;
                        
                        -- 更新边沿检测
                        key_prev <= KEY_PRESSED;
                        again_prev <= AGAIN_BTN;
                    END IF;
                    
                WHEN PLAYBACK =>
                    AUDIO_ENABLE <= '1';
                    AUDIO_CODE_OUT <= notes_memory(read_ptr);
                    
                    IF timer < 25000000 THEN
                        timer <= timer + 1;
                    ELSE
                        timer <= 0;
                        IF read_ptr + 1 < note_count THEN
                            read_ptr <= read_ptr + 1;
                        ELSE
                            state <= FINISH_CLEAR;
                        END IF;
                    END IF;
                    
                WHEN FINISH_CLEAR =>
                    AUDIO_ENABLE <= '0';
                    LCD_CLEAR_REQ <= '1';
                    write_ptr <= 0;
                    note_count <= 0;
                    read_ptr <= 0;
                    key_prev <= KEY_PRESSED;
                    again_prev <= AGAIN_BTN;
                    lockout_timer <= 0;
                    state <= IDLE;
                    
                WHEN OTHERS =>
                    state <= IDLE;
                    
            END CASE;
        END IF;
    END PROCESS;
END ARCHITECTURE BEHAVIOR;

-- =====================================================================
-- 第三部分：LCDDISPLAYER (修改版)
-- 功能：改为事件驱动，响应外部的写入请求和清屏请求
-- =====================================================================
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.STD_LOGIC_UNSIGNED.ALL;

ENTITY LCDDISPLAYER IS
    PORT (
        CLK           : IN STD_LOGIC;
        DATA_IN       : IN STD_LOGIC_VECTOR(2 DOWNTO 0); -- 要显示的字符编码
        WRITE_REQ     : IN STD_LOGIC; -- 写入请求脉冲
        CLEAR_REQ     : IN STD_LOGIC; -- 清屏请求脉冲
        
        DIS_DATA      : OUT STD_LOGIC_VECTOR(7 DOWNTO 0); -- 合并数据总线
        RS            : OUT STD_LOGIC;
        LCD_E         : OUT STD_LOGIC
    );
END ENTITY LCDDISPLAYER;

ARCHITECTURE LCD_DISPLAY OF LCDDISPLAYER IS
    TYPE STATE_TYPE IS (POWER_ON, INIT_FUNC, INIT_DISPLAY, INIT_CLEAR, INIT_ENTRY, IDLE, 
                        CMD_CLEAR, WRITE_CHAR_SET_ADDR, WRITE_CHAR_DATA, EXECUTE_CMD);
    SIGNAL state : STATE_TYPE := POWER_ON;
    SIGNAL return_state : STATE_TYPE := IDLE; -- 执行完命令后返回的状态
    
    SIGNAL timer : INTEGER RANGE 0 TO 1000000 := 0;
    SIGNAL data_reg : STD_LOGIC_VECTOR(7 DOWNTO 0);
    SIGNAL rs_reg : STD_LOGIC := '0';
    SIGNAL e_reg : STD_LOGIC := '0';
    
    -- 缓存请求信号，防止脉冲丢失
    SIGNAL write_pending : STD_LOGIC := '0';
    SIGNAL clear_pending : STD_LOGIC := '0';
    SIGNAL pending_data  : STD_LOGIC_VECTOR(2 DOWNTO 0);
    
    -- 字符转换函数
    FUNCTION CODE_TO_ASCII(code : STD_LOGIC_VECTOR) RETURN STD_LOGIC_VECTOR IS
    BEGIN
        CASE code IS
            WHEN "000" => RETURN X"31"; -- '1'
            WHEN "001" => RETURN X"32"; -- '2'
            WHEN "010" => RETURN X"33"; -- '3'
            WHEN "011" => RETURN X"34"; -- '4'
            WHEN "100" => RETURN X"35"; -- '5'
            WHEN "101" => RETURN X"36"; -- '6'
            WHEN "110" => RETURN X"37"; -- '7'
            WHEN OTHERS => RETURN X"20";
        END CASE;
    END FUNCTION;

BEGIN
    DIS_DATA <= data_reg;
    RS <= rs_reg;
    LCD_E <= e_reg;

    PROCESS(CLK)
    BEGIN
        IF RISING_EDGE(CLK) THEN
            -- 捕捉外部请求
            IF WRITE_REQ = '1' THEN
                write_pending <= '1';
                pending_data <= DATA_IN;
            END IF;
            IF CLEAR_REQ = '1' THEN
                clear_pending <= '1';
            END IF;

            CASE state IS
                -- === 初始化序列 ===
                WHEN POWER_ON =>
                    IF timer < 750000 THEN timer <= timer + 1; -- 15ms
                    ELSE timer <= 0; state <= INIT_FUNC; END IF;
                    
                WHEN INIT_FUNC =>
                    data_reg <= X"38"; rs_reg <= '0'; -- Function Set
                    return_state <= INIT_DISPLAY;
                    state <= EXECUTE_CMD;
                    
                WHEN INIT_DISPLAY =>
                    data_reg <= X"0C"; rs_reg <= '0'; -- Display On
                    return_state <= INIT_CLEAR;
                    state <= EXECUTE_CMD;
                    
                WHEN INIT_CLEAR =>
                    data_reg <= X"01"; rs_reg <= '0'; -- Clear
                    return_state <= INIT_ENTRY;
                    state <= EXECUTE_CMD;
                    
                WHEN INIT_ENTRY =>
                    data_reg <= X"06"; rs_reg <= '0'; -- Entry Mode (Auto Increment)
                    return_state <= IDLE;
                    state <= EXECUTE_CMD;
                    
                -- === 空闲状态：处理请求 ===
                WHEN IDLE =>
                    IF clear_pending = '1' THEN
                        clear_pending <= '0';
                        data_reg <= X"01"; rs_reg <= '0'; -- Clear Command
                        return_state <= IDLE;
                        state <= EXECUTE_CMD;
                    ELSIF write_pending = '1' THEN
                        write_pending <= '0';
                        -- 直接写数据，利用LCD的自动光标右移功能
                        data_reg <= CODE_TO_ASCII(pending_data); 
                        rs_reg <= '1'; -- Data Mode
                        return_state <= IDLE;
                        state <= EXECUTE_CMD;
                    END IF;
                    
                -- === 通用命令执行状态 ===
                WHEN EXECUTE_CMD =>
                    -- 产生E脉冲：低->高->低
                    IF timer = 0 THEN e_reg <= '1'; timer <= timer + 1;
                    ELSIF timer < 5000 THEN timer <= timer + 1; -- 保持脉冲宽一点 (100us)
                    ELSE 
                        e_reg <= '0'; 
                        timer <= 0;
                        -- 命令执行等待时间
                        IF data_reg = X"01" THEN -- Clear命令需要长等待
                             state <= CMD_CLEAR; -- 跳转去长等待
                        ELSE
                             state <= return_state; -- 普通命令直接返回
                        END IF;
                    END IF;
                    
                WHEN CMD_CLEAR =>
                    IF timer < 100000 THEN timer <= timer + 1; -- 2ms wait for clear
                    ELSE timer <= 0; state <= return_state; END IF;
                    
                WHEN OTHERS => state <= IDLE;
            END CASE;
        END IF;
    END PROCESS;
END ARCHITECTURE LCD_DISPLAY;

-- =====================================================================
-- 第四部分：顶层实体 FINAL (更新版)
-- =====================================================================
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;

ENTITY FINAL IS
    PORT (
        K1, K2, K3, K4, K5, K6, K7 : IN STD_LOGIC;
        Again    : IN STD_LOGIC;
        CLK      : IN STD_LOGIC;
        WAVE_OUT : OUT STD_LOGIC;
        CODE_OUT : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
        -- LCD接口
        LCD_DB0, LCD_DB1, LCD_DB2, LCD_DB3, LCD_DB4, LCD_DB5, LCD_DB6, LCD_DB7 : OUT STD_LOGIC;
        LCD_RS, LCD_E : OUT STD_LOGIC
    );
END ENTITY FINAL;

ARCHITECTURE LOGIC OF FINAL IS
    -- 信号定义
    SIGNAL raw_key_code : STD_LOGIC_VECTOR(2 DOWNTO 0);
    SIGNAL key_pressed_flag : STD_LOGIC;
    
    SIGNAL audio_code : STD_LOGIC_VECTOR(2 DOWNTO 0);
    SIGNAL audio_en   : STD_LOGIC;
    
    SIGNAL lcd_char_code : STD_LOGIC_VECTOR(2 DOWNTO 0);
    SIGNAL lcd_wr_req    : STD_LOGIC;
    SIGNAL lcd_clr_req   : STD_LOGIC;
    
    SIGNAL lcd_data_bus : STD_LOGIC_VECTOR(7 DOWNTO 0);

    COMPONENT CODER IS
        PORT (
            K1IN, K2IN, K3IN, K4IN, K5IN, K6IN, K7IN : IN STD_LOGIC;
            CODER_OUTPUT : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
            KEY_PRESSED  : OUT STD_LOGIC
        );
    END COMPONENT;
    
    COMPONENT PULSE_GENERATOR IS
        PORT (
            CLK_IN      : IN STD_LOGIC;
            BINARY_CODE : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
            ENABLE      : IN STD_LOGIC;
            PULSE_OUT   : OUT STD_LOGIC
        );
    END COMPONENT;
    
    COMPONENT RECORDER_PLAYER IS
        PORT (
            CLK, RESET, KEY_PRESSED, AGAIN_BTN : IN STD_LOGIC;
            KEY_CODE_IN : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
            AUDIO_CODE_OUT : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
            AUDIO_ENABLE   : OUT STD_LOGIC;
            LCD_CHAR_CODE  : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
            LCD_WRITE_REQ, LCD_CLEAR_REQ : OUT STD_LOGIC
        );
    END COMPONENT;
    
    COMPONENT LCDDISPLAYER IS
        PORT (
            CLK : IN STD_LOGIC;
            DATA_IN : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
            WRITE_REQ, CLEAR_REQ : IN STD_LOGIC;
            DIS_DATA : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
            RS, LCD_E : OUT STD_LOGIC
        );
    END COMPONENT;

BEGIN
    -- 1. 编码器
    U_CODER: CODER PORT MAP(
        K1IN=>K1, K2IN=>K2, K3IN=>K3, K4IN=>K4, K5IN=>K5, K6IN=>K6, K7IN=>K7,
        CODER_OUTPUT => raw_key_code,
        KEY_PRESSED  => key_pressed_flag
    );
    
    -- 2. 录音与回放控制器
    U_RECORDER: RECORDER_PLAYER PORT MAP(
        CLK => CLK, RESET => '0',
        KEY_CODE_IN => raw_key_code,
        KEY_PRESSED => key_pressed_flag,
        AGAIN_BTN   => Again,
        AUDIO_CODE_OUT => audio_code,
        AUDIO_ENABLE   => audio_en,
        LCD_CHAR_CODE  => lcd_char_code,
        LCD_WRITE_REQ  => lcd_wr_req,
        LCD_CLEAR_REQ  => lcd_clr_req
    );
    
    -- 3. 发声模块 (现在由 Recorder 控制)
    U_SOUND: PULSE_GENERATOR PORT MAP(
        CLK_IN => CLK,
        BINARY_CODE => audio_code,
        ENABLE => audio_en,
        PULSE_OUT => WAVE_OUT
    );
    
    -- 4. LCD显示模块
    U_LCD: LCDDISPLAYER PORT MAP(
        CLK => CLK,
        DATA_IN => lcd_char_code,
        WRITE_REQ => lcd_wr_req,
        CLEAR_REQ => lcd_clr_req,
        DIS_DATA => lcd_data_bus,
        RS => LCD_RS,
        LCD_E => LCD_E
    );
    
    -- 连接LCD数据总线
    LCD_DB0 <= lcd_data_bus(0); LCD_DB1 <= lcd_data_bus(1);
    LCD_DB2 <= lcd_data_bus(2); LCD_DB3 <= lcd_data_bus(3);
    LCD_DB4 <= lcd_data_bus(4); LCD_DB5 <= lcd_data_bus(5);
    LCD_DB6 <= lcd_data_bus(6); LCD_DB7 <= lcd_data_bus(7);
    
    CODE_OUT <= raw_key_code; -- 调试用
    
END ARCHITECTURE LOGIC;