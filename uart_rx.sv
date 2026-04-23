module uart_rx #(
    parameter CLK_FREQ  = 12000000,
    parameter BAUD_RATE = 9600
)(
    input  logic       clk,
    input  logic       reset,
    input  logic       rx,
    output logic       valid,
    output logic [7:0] data
);
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    
    // Anti-metastability synchronizer
    logic rx_sync_0 = 1, rx_sync = 1;
    always_ff @(posedge clk) begin
        rx_sync_0 <= rx;
        rx_sync   <= rx_sync_0;
    end
    
    typedef enum logic [1:0] {IDLE, START, DATA, STOP} state_t;
    state_t state = IDLE;
    
    logic [15:0] clk_count = 0;
    logic [2:0]  bit_index = 0;
    logic [7:0]  rx_data_reg = 0;
    
    always_ff @(posedge clk) begin
        valid <= 0;
        
        if (reset) begin
            state <= IDLE;
        end else begin
            case (state)
                IDLE: begin
                    clk_count <= 0;
                    bit_index <= 0;
                    if (rx_sync == 0) state <= START;
                end
                
                START: begin
                    if (clk_count == CLKS_PER_BIT / 2) begin
                        if (rx_sync == 0) begin
                            clk_count <= 0;
                            state <= DATA;
                        end else state <= IDLE;
                    end else clk_count <= clk_count + 1;
                end
                
                DATA: begin
                    if (clk_count == CLKS_PER_BIT - 1) begin
                        clk_count <= 0;
                        rx_data_reg[bit_index] <= rx_sync;
                        
                        if (bit_index == 7) state <= STOP;
                        else bit_index <= bit_index + 1;
                    end else clk_count <= clk_count + 1;
                end
                
                STOP: begin
                    // Sample at half the stop bit to resync quickly on burst transmissions
                    if (clk_count == CLKS_PER_BIT / 2) begin
                        data <= rx_data_reg;
                        valid <= 1;
                        state <= IDLE;
                    end else clk_count <= clk_count + 1;
                end
            endcase
        end
    end
endmodule