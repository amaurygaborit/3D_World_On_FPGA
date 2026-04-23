import mini_minecraft_pkg::*;

module trig_rom (
    input  logic clk,
    input  logic [$clog2(ANGLE_STEPS) - 1:0] angle,
    
    output logic signed [TRIG_TOTAL_BITS - 1:0] sin_out,
    output logic signed [TRIG_TOTAL_BITS - 1:0] cos_out
);
    logic [(2*TRIG_TOTAL_BITS) - 1:0] rom [0:ANGLE_STEPS - 1];

    initial begin
        $readmemh("hex/trig.hex", rom);
    end

    // 1-cycle latency for memory fetch
    always_ff @(posedge clk) begin
        sin_out <= rom[angle][TRIG_TOTAL_BITS - 1:0];
        cos_out <= rom[angle][(2*TRIG_TOTAL_BITS) - 1:TRIG_TOTAL_BITS];
    end

endmodule