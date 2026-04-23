import mini_minecraft_pkg::*;

module spi_lcd (
    input  logic                      clk,
    output logic [$clog2(GAME_W)-1:0] vram_x,
    output logic [$clog2(GAME_H)-1:0] vram_y,
    input  logic [3:0]                vram_data,
    
    output logic spi_sck, spi_sda, spi_cs, spi_dc, spi_res,
    output logic vsync
);
    // Display geometry and scaling
    localparam WIN_W   = GAME_W * ZOOM;
    localparam WIN_H   = GAME_H * ZOOM;
    localparam START_X = HW_OFF_X + GAME_X;
    localparam START_Y = HW_OFF_Y + GAME_Y;
    localparam END_X   = START_X + WIN_W - 1;
    localparam END_Y   = START_Y + WIN_H - 1;

    localparam TOTAL_PHYS_PIXELS = PHYS_W * PHYS_H;
    
    // Hardware delay timer (100ms) based on system clock
    localparam TIMER_MAX = CLK_FREQ / 10;

    logic [15:0] PALETTE [0:15];
    initial $readmemh("hex/palette.hex", PALETTE);

    // Initialization sequence ROM for display controller
    localparam INIT_LEN = 17;
    logic [9:0] current_init_cmd;
    always_comb begin
        case (rom_idx)
            0:  current_init_cmd = {2'b10, 8'h11};
            1:  current_init_cmd = {2'b00, 8'h3A};
            2:  current_init_cmd = {2'b01, 8'h05};
            3:  current_init_cmd = {2'b00, 8'h36};
            4:  current_init_cmd = {2'b01, 8'h08}; // BGR mode
            
            // CASET (Column Address Set)
            5:  current_init_cmd = {2'b00, 8'h2A};
            6:  current_init_cmd = {2'b01, 8'h00};
            7:  current_init_cmd = {2'b01, HW_OFF_X[7:0]};
            8:  current_init_cmd = {2'b01, 8'h00};
            9:  current_init_cmd = {2'b01, 8'(HW_OFF_X + PHYS_W - 1)};
            
            // RASET (Row Address Set)
            10: current_init_cmd = {2'b00, 8'h2B};
            11: current_init_cmd = {2'b01, 8'h00};
            12: current_init_cmd = {2'b01, HW_OFF_Y[7:0]};
            13: current_init_cmd = {2'b01, 8'h00};
            14: current_init_cmd = {2'b01, 8'(HW_OFF_Y + PHYS_H - 1)};
            
            15: current_init_cmd = {2'b00, 8'h21}; // Display inversion ON
            16: current_init_cmd = {2'b10, 8'h29}; // Display ON
            default: current_init_cmd = 10'h000;
        endcase
    end

    // Window configuration ROM for the active game area
    localparam WIN_LEN = 10;
    logic [8:0] current_win_cmd;
    always_comb begin
        case (rom_idx)
            0: current_win_cmd = {1'b0, 8'h2A};
            1: current_win_cmd = {1'b1, 8'h00};
            2: current_win_cmd = {1'b1, START_X[7:0]};
            3: current_win_cmd = {1'b1, 8'h00};
            4: current_win_cmd = {1'b1, END_X[7:0]};
            5: current_win_cmd = {1'b0, 8'h2B};
            6: current_win_cmd = {1'b1, 8'h00};
            7: current_win_cmd = {1'b1, START_Y[7:0]};
            8: current_win_cmd = {1'b1, 8'h00};
            9: current_win_cmd = {1'b1, END_Y[7:0]};
            default: current_win_cmd = 9'h000;
        endcase
    end

    typedef enum logic [3:0] {
        HW_RESET,
        SEND_INIT,
        CLEAR_SCREEN,
        SET_WINDOW,
        START_DRAW,
        DRAW_GAME
    } state_t;
    state_t state = HW_RESET;

    // Tightly sized registers to prevent wasted logic elements
    logic [$clog2(TIMER_MAX)-1:0]             timer = 0;
    logic [$clog2(TOTAL_PHYS_PIXELS + 1)-1:0] black_cnt = 0;
    
    localparam MAX_ROM_LEN = (INIT_LEN > WIN_LEN) ? INIT_LEN : WIN_LEN;
    logic [$clog2(MAX_ROM_LEN)-1:0]           rom_idx = 0;
    
    logic [$clog2(WIN_W)-1:0] px = 0;
    logic [$clog2(WIN_H)-1:0] py = 0;
    
    // Hardware division is optimized away by synthesis if ZOOM is a power of 2
    assign vram_x = px / ZOOM;
    assign vram_y = py / ZOOM;

    // SPI Serializer state
    logic [15:0] shift_reg = 0;
    logic [4:0]  bits_left = 0;
    logic        sending = 0;
    logic [1:0]  clk_div = 0;
    logic        sck_reg = 0;

    assign spi_cs  = 0;
    assign spi_sck = sck_reg;
    assign spi_sda = shift_reg[15];

    always_ff @(posedge clk) begin
        // SPI Bit-banging Engine
        if (sending) begin
            vsync <= 0;
            clk_div <= clk_div + 1;
            
            if (clk_div == 2'b01) sck_reg <= 1;
            else if (clk_div == 2'b11) begin
                sck_reg <= 0;
                shift_reg <= {shift_reg[14:0], 1'b0};
                bits_left <= bits_left - 1;
                if (bits_left == 1) sending <= 0;
            end
        end
        // Main State Machine
        else begin
            sck_reg <= 0;
            clk_div <= 0;
            vsync <= 0;

            case (state)
                HW_RESET: begin
                    timer <= timer + 1;
                    spi_res <= (timer > (TIMER_MAX / 2));
                    if (timer == TIMER_MAX - 1) begin
                        timer <= 0;
                        state <= SEND_INIT;
                    end
                end

                SEND_INIT: begin
                    if (timer > 0) begin
                        timer <= timer + 1;
                        if (timer == TIMER_MAX / 2) timer <= 0;
                    end else begin
                        spi_dc <= current_init_cmd[8];
                        shift_reg <= {current_init_cmd[7:0], 8'h00};
                        bits_left <= 8; 
                        sending <= 1;
                        
                        // ROM bit 9 acts as a delay flag
                        if (current_init_cmd[9]) timer <= 1;
                        
                        if (rom_idx == INIT_LEN - 1) begin
                            rom_idx <= 0;
                            state <= CLEAR_SCREEN;
                        end else rom_idx <= rom_idx + 1;
                    end
                end

                CLEAR_SCREEN: begin
                    if (black_cnt == 0) begin
                        spi_dc <= 0; 
                        shift_reg <= 16'h2C00; 
                        bits_left <= 8;
                    end else begin
                        spi_dc <= 1; 
                        shift_reg <= 16'h0000; 
                        bits_left <= 16;
                    end
                    sending <= 1;
                    
                    if (black_cnt == TOTAL_PHYS_PIXELS) state <= SET_WINDOW;
                    else black_cnt <= black_cnt + 1;
                end

                SET_WINDOW: begin
                    spi_dc <= current_win_cmd[8];
                    shift_reg <= {current_win_cmd[7:0], 8'h00};
                    bits_left <= 8; 
                    sending <= 1;
                    
                    if (rom_idx == WIN_LEN - 1) state <= START_DRAW;
                    else rom_idx <= rom_idx + 1;
                end

                START_DRAW: begin
                    spi_dc <= 0;
                    shift_reg <= 16'h2C00; // RAMWR
                    bits_left <= 8; 
                    sending <= 1;
                    px <= 0; py <= 0;
                    state <= DRAW_GAME;
                end

                DRAW_GAME: begin
                    spi_dc <= 1;
                    shift_reg <= PALETTE[vram_data];
                    bits_left <= 16; 
                    sending <= 1;
                    
                    if (px == WIN_W - 1) begin
                        px <= 0;
                        if (py == WIN_H - 1) begin
                            py <= 0;
                            state <= START_DRAW;
                            vsync <= 1;
                        end
                        else py <= py + 1;
                    end else px <= px + 1;
                end
            endcase
        end
    end
endmodule