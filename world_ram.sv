import mini_minecraft_pkg::*;

module world_ram (
    input  logic clk,
    input  logic gpu_active,

    // GPU Interface (Read only)
    input  logic [$clog2(WORLD_SIZE) - 1:0] addr_a,
    output logic [3:0] data_a,
    
    // CPU Interface (Read/Write)
    input  logic [7:0] addr_b,
    input  logic [7:0] data_b,
    input  logic       we_b,
    output logic [7:0] q_b
);

    logic [7:0] ram [0:223];
    initial $readmemh("hex/world.hex", ram);

    always_ff @(posedge clk) begin
        if (we_b && addr_b < 224) begin
            ram[addr_b] <= data_b;
        end
    end

    // Multiplex read address based on active master
    logic [7:0] read_addr;
    assign read_addr = gpu_active ? addr_a[8:1] : addr_b;

    logic [7:0] read_data;
    always_ff @(posedge clk) begin
        read_data <= (read_addr < 224) ? ram[read_addr] : 8'h00;
    end

    // GPU expects 4-bit nibbles, but memory is 8-bit wide
    logic gpu_nibble_sel;
    always_ff @(posedge clk) begin
        gpu_nibble_sel <= addr_a[0];
    end
    
    assign data_a = gpu_nibble_sel ? read_data[7:4] : read_data[3:0];
    assign q_b    = read_data;

endmodule