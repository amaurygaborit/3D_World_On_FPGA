import mini_minecraft_pkg::*;

module top (
    input  logic clk,
    input  logic uart_rx, // Kept for .pcf pinout compatibility
    output logic spi_sck, spi_sda, spi_cs, spi_dc, spi_res,
    output logic led
);

    // GPU and VRAM signals
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

    // Fixed player state for testing purposes
    logic [7:0] player_x = 144;
    logic [7:0] player_y = 32 + 32 * PLAYER_HEIGHT;
    logic [7:0] player_z = 144;
    
    logic [7:0] angle_h = 0;
    logic [7:0] angle_v = -8;

    // Simple heartbeat LED to verify FPGA is running
    logic [23:0] led_timer = 0;
    always_ff @(posedge clk) begin
        led_timer <= led_timer + 1;
    end
    assign led = led_timer[23];

    // Frame pacer (30 FPS target) and auto-rotation engine
    localparam CYCLES_PER_FRAME = CLK_FREQ / TARGET_FPS;
    logic [23:0] fps_timer = 0;

    always_ff @(posedge clk) begin
        if (fps_timer == CYCLES_PER_FRAME - 1) begin
            fps_timer <= 0;
            if (!gpu_is_running) begin
                v_swap <= 1;
                gpu_start <= 1;
                gpu_is_running <= 1;
                
                // Continuous camera rotation for the demo
                angle_h <= angle_h + 1;
            end
        end else begin
            fps_timer <= fps_timer + 1;
            gpu_start <= 0;
            v_swap <= 0;
        end
        
        if (gpu_done) gpu_is_running <= 0;
    end

    // Hardware instantiations
    spi_lcd my_lcd (
        .clk(clk), .vram_x(vl_x), .vram_y(vl_y), .vram_data(vl_d),
        .spi_sck(spi_sck), .spi_sda(spi_sda), .spi_cs(spi_cs),
        .spi_dc(spi_dc), .spi_res(spi_res), .vsync(w_vsync)
    );
    
    vram my_vram (
        .clk(clk), .gpu_we(v_we), .gpu_x(vg_x), .gpu_y(vg_y),
        .gpu_data(vg_d), .cpu_swap(v_swap), .lcd_x(vl_x),
        .lcd_y(vl_y), .lcd_data(vl_d)
    );
    
    trig_rom my_trig_h ( .clk(clk), .angle(gpu_angle_h), .sin_out(trig_s_h), .cos_out(trig_c_h) );
    trig_rom my_trig_v ( .clk(clk), .angle(gpu_angle_v), .sin_out(trig_s_v), .cos_out(trig_c_v) );
    
    // Tie off unused CPU write port for the world RAM
    logic [7:0] unused_q_b;
    world_ram my_world (
        .clk(clk), .gpu_active(gpu_is_running),
        .addr_a(gpu_world_addr), .data_a(gpu_world_data),
        .addr_b(8'd0), .data_b(8'd0), .we_b(1'b0),
        .q_b(unused_q_b)
    );
    
    tex_rom my_textures ( .clk(clk), .block_id(tex_id), .face(tex_face), .u(tex_u), .v(tex_v), .color_out(tex_color) );
    
    gpu_dda my_gpu (
        .clk(clk), .start(gpu_start), .done(gpu_done),
        .vram_x(vg_x), .vram_y(vg_y), .vram_data(vg_d), .vram_we(v_we),
        .trig_angle_h(gpu_angle_h), .trig_angle_v(gpu_angle_v),
        .trig_sin_h(trig_s_h), .trig_cos_h(trig_c_h),
        .trig_sin_v(trig_s_v), .trig_cos_v(trig_c_v),
        .world_addr(gpu_world_addr), .world_data(gpu_world_data),
        .tex_block_id(tex_id), .tex_face(tex_face),
        .tex_u(tex_u), .tex_v(tex_v), .tex_color(tex_color),
        
        // Injecting demo registers instead of MMIO
        .player_x(player_x),
        .player_y(player_y),
        .player_z(player_z),
        .angle_h({angle_h, 1'b0}),
        .angle_v({angle_v, 1'b0})
    );

endmodule