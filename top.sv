import mini_minecraft_pkg::*;

module top (
    input  logic clk,
    input  logic uart_rx,
    
    // PMOD-LCD interface
    output logic spi_sck, spi_sda, spi_cs, spi_dc, spi_res,
    
    // Debug and status
    output logic led
);
    // Internal signal definitions
    logic [$clog2(GAME_W)-1:0] vl_x, vg_x;
    logic [$clog2(GAME_H)-1:0] vl_y, vg_y;
    logic [3:0] vl_d, vg_d;
    logic w_vsync, v_swap, v_we;
    
    logic [$clog2(ANGLE_STEPS)-1:0] gpu_angle_h, gpu_angle_v;
    logic signed [TRIG_TOTAL_BITS-1:0] trig_s_h, trig_c_h, trig_s_v, trig_c_v;
    logic [$clog2(WORLD_SIZE)-1:0] gpu_world_addr;
    logic [$clog2(NUM_BLOCKS)-1:0] gpu_world_data, tex_id;
    logic tex_face;
    logic [$clog2(TEX_SIZE)-1:0] tex_u, tex_v;
    logic [3:0] tex_color;
    
    logic gpu_start = 0;
    logic gpu_done, gpu_is_running = 0;

    // UART Receiver
    logic uart_rx_valid;
    logic [7:0] uart_rx_data;
    
    uart_rx my_uart (
        .clk(clk),
        .reset(1'b0),
        .rx(uart_rx),
        .valid(uart_rx_valid),
        .data(uart_rx_data)
    );

    // Toggle LED on every valid UART byte received for debugging
    logic led_state = 0;
    always_ff @(posedge clk) begin
        if (uart_rx_valid) begin
            led_state <= ~led_state;
        end
    end
    assign led = led_state;

    // CPU and Memory
    logic [$clog2(NUM_INST)-1:0] cpu_inst_addr;
    logic [15:0] cpu_inst_data;
    logic [7:0] cpu_ram_addr, cpu_ram_data_out, cpu_ram_data_in;
    logic cpu_ram_we;

    firmware_rom my_rom (
        .clk(clk),
        .addr(cpu_inst_addr[7:0]),
        .data(cpu_inst_data)
    );

    mini_cpu my_cpu (
        .clk(clk), .reset(reset),
        .inst_addr(cpu_inst_addr), .inst_data(cpu_inst_data),
        .ram_addr(cpu_ram_addr), .ram_data_in(cpu_ram_data_in),
        .ram_data_out(cpu_ram_data_out), .ram_we(cpu_ram_we)
    );

    // MMIO Registers for player state
    logic [7:0] mmio_player_x = 144;
    logic [7:0] mmio_player_y = 32;
    logic [7:0] mmio_player_z = 144;
    logic [7:0] mmio_angle_h  = 0;
    logic [7:0] mmio_angle_v  = 0;

    logic [7:0] real_bram [0:15];
    logic [7:0] real_bram_out, world_ram_out;

    // Memory mapping logic
    logic cpu_we_bram  = cpu_ram_we && (cpu_ram_addr < 16);
    logic cpu_we_mmio  = cpu_ram_we && (cpu_ram_addr >= 16) && (cpu_ram_addr < 32);
    logic cpu_we_world = cpu_ram_we && (cpu_ram_addr >= 32);

    logic [7:0] uart_buffer = 0;

    always_ff @(posedge clk) begin
        // Captures UART data or allows CPU to clear the buffer (mapped to 0x0F)
        if (uart_rx_valid) begin
            uart_buffer <= uart_rx_data;
        end else if (cpu_we_bram && cpu_ram_addr[3:0] == 4'd15) begin
            uart_buffer <= cpu_ram_data_out;
        end

        // Scratchpad RAM inference
        if (cpu_we_bram) begin
            real_bram[cpu_ram_addr[3:0]] <= cpu_ram_data_out;
        end
        real_bram_out <= real_bram[cpu_ram_addr[3:0]];

        // Handle MMIO writes for player position and camera angles
        if (cpu_we_mmio) begin
            case (cpu_ram_addr)
                8'h13: mmio_player_x  <= cpu_ram_data_out;
                8'h14: mmio_player_y  <= cpu_ram_data_out;
                8'h15: mmio_player_z  <= cpu_ram_data_out;
                8'h16: mmio_angle_h   <= cpu_ram_data_out;
                8'h17: mmio_angle_v   <= cpu_ram_data_out;
            endcase
        end
    end

    // Frame Pacer
    localparam CYCLES_PER_FRAME = CLK_FREQ / TARGET_FPS;
    logic [23:0] fps_timer = 0;

    always_ff @(posedge clk) begin
        if (fps_timer == CYCLES_PER_FRAME - 1) begin
            fps_timer <= 0;
            if (!gpu_is_running) begin
                v_swap <= 1;
                gpu_start <= 1;
                gpu_is_running <= 1;
            end
        end else begin
            fps_timer <= fps_timer + 1;
            gpu_start <= 0;
            v_swap <= 0;
        end
        if (gpu_done) gpu_is_running <= 0;
    end

    // CPU Read Mux
    always_comb begin
        if (cpu_ram_addr >= 32)         cpu_ram_data_in = world_ram_out;
        else if (cpu_ram_addr == 8'h12) cpu_ram_data_in = {7'b0, gpu_is_running};
        else if (cpu_ram_addr == 8'h0F) cpu_ram_data_in = uart_buffer;
        else                            cpu_ram_data_in = real_bram_out;
    end

    // Peripherals & Graphics Pipeline
    spi_lcd my_lcd (
        .clk(clk), .vram_x(vl_x), .vram_y(vl_y), .vram_data(vl_d),
        .spi_sck(spi_sck), .spi_sda(spi_sda), .spi_cs(spi_cs),
        .spi_dc(spi_dc), .spi_res(spi_res), .vsync(w_vsync)
    );

    vram my_vram (
        .clk(clk), .gpu_we(v_we), .gpu_x(vg_x), .gpu_y(vg_y), .gpu_data(vg_d),
        .cpu_swap(v_swap), .lcd_x(vl_x), .lcd_y(vl_y), .lcd_data(vl_d)
    );

    trig_rom my_trig_h ( .clk(clk), .angle(gpu_angle_h), .sin_out(trig_s_h), .cos_out(trig_c_h) );
    trig_rom my_trig_v ( .clk(clk), .angle(gpu_angle_v), .sin_out(trig_s_v), .cos_out(trig_c_v) );
    
    world_ram my_world (
        .clk(clk), .gpu_active(gpu_is_running),
        .addr_a(gpu_world_addr), .data_a(gpu_world_data),
        .addr_b(cpu_ram_addr - 32), .data_b(cpu_ram_data_out),
        .we_b(cpu_we_world), .q_b(world_ram_out)
    );

    tex_rom my_textures (
        .clk(clk), .block_id(tex_id), .face(tex_face),
        .u(tex_u), .v(tex_v), .color_out(tex_color)
    );

    gpu_dda my_gpu (
        .clk(clk), .start(gpu_start), .done(gpu_done),
        .vram_x(vg_x), .vram_y(vg_y), .vram_data(vg_d), .vram_we(v_we),
        .trig_angle_h(gpu_angle_h), .trig_angle_v(gpu_angle_v),
        .trig_sin_h(trig_s_h), .trig_cos_h(trig_c_h),
        .trig_sin_v(trig_s_v), .trig_cos_v(trig_c_v),
        .world_addr(gpu_world_addr), .world_data(gpu_world_data),
        .tex_block_id(tex_id), .tex_face(tex_face),
        .tex_u(tex_u), .tex_v(tex_v), .tex_color(tex_color),
        
        .player_x(mmio_player_x),
        .player_y(mmio_player_y),
        .player_z(mmio_player_z),
        .angle_h({mmio_angle_h, 1'b0}),
        .angle_v({mmio_angle_v, 1'b0})
    );

    // Internal power-on reset generator
    logic [3:0] reset_counter = 0;
    logic reset = 1;
    always_ff @(posedge clk) begin
        if (reset_counter < 15) begin
            reset_counter <= reset_counter + 1;
            reset <= 1;
        end else begin
            reset <= 0;
        end
    end

endmodule