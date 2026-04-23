import mini_minecraft_pkg::*;

module vram (
    input  logic                        clk,
    input  logic                        gpu_we,
    input  logic [$clog2(GAME_W) - 1:0] gpu_x,
    input  logic [$clog2(GAME_H) - 1:0] gpu_y,
    input  logic [3:0]                  gpu_data,

    input  logic                        cpu_swap,

    input  logic [$clog2(GAME_W) - 1:0] lcd_x,
    input  logic [$clog2(GAME_H) - 1:0] lcd_y,
    output logic [3:0]                  lcd_data
);
    localparam MEM_SIZE = GAME_W * GAME_H;
    
    logic [3:0] ram [0:(2*MEM_SIZE) - 1];
    logic front_bank = 0;

    wire [$clog2(MEM_SIZE) - 1:0] g_offset = (gpu_y * GAME_W) + gpu_x;
    wire [$clog2(MEM_SIZE) - 1:0] l_offset = (lcd_y * GAME_W) + lcd_x;

    // Double buffering: swap base addresses based on active bank
    wire [$clog2(2*MEM_SIZE) - 1:0] g_addr = (front_bank ? MEM_SIZE : 0) + g_offset;
    wire [$clog2(2*MEM_SIZE) - 1:0] l_addr = (front_bank ? 0 : MEM_SIZE) + l_offset;

    always_ff @(posedge clk) begin
        if (cpu_swap) front_bank <= ~front_bank;
        if (gpu_we) ram[g_addr] <= gpu_data;
        lcd_data <= ram[l_addr];
    end
endmodule