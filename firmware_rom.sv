import mini_minecraft_pkg::*;

module firmware_rom (
    input  logic clk,
    input  logic [$clog2(NUM_INST)-1:0] addr,
    output logic [15:0] data
);

    logic [15:0] rom_memory [0:NUM_INST-1];

    initial begin
        $readmemh("hex/firmware.hex", rom_memory);
    end

    // 1-cycle latency synchronous read
    always_ff @(posedge clk) begin
        data <= rom_memory[addr];
    end

endmodule