import mini_minecraft_pkg::*;

module gpu_dda (
    input  logic clk,
    input  logic start,
    output logic done,

    output logic [$clog2(GAME_W)-1:0] vram_x,
    output logic [$clog2(GAME_H)-1:0] vram_y,
    output logic [3:0]                vram_data,
    output logic                      vram_we,

    output logic [$clog2(ANGLE_STEPS)-1:0]    trig_angle_h,
    output logic [$clog2(ANGLE_STEPS)-1:0]    trig_angle_v,
    input  logic signed [TRIG_TOTAL_BITS-1:0] trig_sin_h,
    input  logic signed [TRIG_TOTAL_BITS-1:0] trig_cos_h,
    input  logic signed [TRIG_TOTAL_BITS-1:0] trig_sin_v,
    input  logic signed [TRIG_TOTAL_BITS-1:0] trig_cos_v,

    output logic [$clog2(WORLD_SIZE)-1:0] world_addr,
    input  logic [$clog2(NUM_BLOCKS)-1:0] world_data,

    output logic [$clog2(NUM_BLOCKS)-1:0] tex_block_id,
    output logic                          tex_face,
    output logic [$clog2(TEX_SIZE)-1:0]   tex_u,
    output logic [$clog2(TEX_SIZE)-1:0]   tex_v,
    input  logic [3:0]                    tex_color,

    input  logic [7:0] player_x, 
    input  logic [7:0] player_y, 
    input  logic [7:0] player_z, 
    input  logic [$clog2(ANGLE_STEPS)-1:0] angle_h,
    input  logic [$clog2(ANGLE_STEPS)-1:0] angle_v
);
    // Fixed-point precision configuration for the raycaster
    // 10 fractional bits provide smooth sub-block resolution and prevent jitter
    localparam WL_BITS  = $clog2(WORLD_L);
    localparam TEX_BITS = $clog2(TEX_SIZE);
    localparam ANG_BITS = $clog2(ANGLE_STEPS);
    
    localparam RAY_FRC  = 10; 
    
    // Coordinate format: 1 sign bit + 3 integer bits (for 8x8 map) + 10 fractional bits
    localparam COORD_BITS = 1 + WL_BITS + RAY_FRC; 

    typedef enum logic [3:0] {
        IDLE, REQ_ANGLE, WAIT_ROM, SETUP_RAY,
        STEP_DDA_REQ, WAIT_WORLD, STEP_DDA_CHECK,
        REQ_TEXTURE, WAIT_TEXTURE, WRITE_PIXEL, NEXT_PIXEL
    } state_enum;
    state_enum state = IDLE;

    logic [$clog2(GAME_W)-1:0] curr_x = 0;
    logic [$clog2(GAME_H)-1:0] curr_y = 0;

    logic signed [COORD_BITS-1:0] ray_x, ray_y, ray_z;
    logic signed [COORD_BITS-1:0] step_x, step_y, step_z;

    // Precomputed perspective projection offsets
    logic signed [7:0] fov_lut_h [0:GAME_W-1];
    logic signed [7:0] fov_lut_v [0:GAME_H-1];
    initial begin
        $readmemh("hex/fov_h.hex", fov_lut_h);
        $readmemh("hex/fov_v.hex", fov_lut_v);
    end

    // Extract current block coordinates by discarding fractional bits
    wire [WL_BITS-1:0] map_x = ray_x[RAY_FRC + WL_BITS - 1 : RAY_FRC];
    wire [WL_BITS-1:0] map_y = ray_y[RAY_FRC + WL_BITS - 1 : RAY_FRC];
    wire [WL_BITS-1:0] map_z = ray_z[RAY_FRC + WL_BITS - 1 : RAY_FRC];
    
    assign world_addr = {map_y, map_z, map_x};

    // Edge crossing detection for UV mapping alignment
    logic [WL_BITS-1:0] last_map_x, last_map_y, last_map_z;
    wire crossed_x = (map_x != last_map_x);
    wire crossed_y = (map_y != last_map_y);
    wire crossed_z = (map_z != last_map_z);

    wire oob_x = ray_x[COORD_BITS-1]; 
    wire oob_z = ray_z[COORD_BITS-1];
    wire oob_y = ray_y[COORD_BITS-1] || (map_y == 3'b111);

    logic [$clog2(STEP_COUNT + 1)-1:0] step_count;

    wire signed [ANG_BITS-1:0] fov_h_ext = $signed(fov_lut_h[curr_x]);
    wire signed [ANG_BITS-1:0] fov_v_ext = $signed(fov_lut_v[curr_y]);

    always_ff @(posedge clk) begin
        case (state)
            IDLE: begin
                done <= 0;
                vram_we <= 0;
                if (start) begin
                    curr_x <= 0;
                    curr_y <= 0;
                    state <= REQ_ANGLE;
                end
            end

            REQ_ANGLE: begin
                trig_angle_h <= angle_h + fov_h_ext;
                trig_angle_v <= angle_v - fov_v_ext; // Invert Y-axis for correct pitch orientation
                state <= WAIT_ROM;
            end

            WAIT_ROM: begin
                state <= SETUP_RAY;
            end

            SETUP_RAY: begin
                // Sign-extend 8-bit trig values to 14 bits.
                // The lack of explicit shifting acts as a mathematical division, scaling down the step vector.
                step_x <= { {6{trig_cos_h[7]}}, trig_cos_h };
                step_z <= { {6{trig_sin_h[7]}}, trig_sin_h };
                step_y <= { {6{trig_sin_v[7]}}, trig_sin_v };

                // Align 5-bit fractional CPU position to the 10-bit fractional ray format
                ray_x <= {1'b0, player_x, 5'b0};
                ray_y <= {1'b0, player_y, 5'b0};
                ray_z <= {1'b0, player_z, 5'b0};

                last_map_x <= player_x[7:5];
                last_map_y <= player_y[7:5];
                last_map_z <= player_z[7:5];

                step_count <= 0;
                state <= STEP_DDA_REQ;
            end

            STEP_DDA_REQ: begin
                last_map_x <= map_x;
                last_map_y <= map_y;
                last_map_z <= map_z;

                ray_x <= ray_x + step_x;
                ray_y <= ray_y + step_y;
                ray_z <= ray_z + step_z;

                step_count <= step_count + 1;
                state <= WAIT_WORLD;
            end

            WAIT_WORLD: begin
                state <= STEP_DDA_CHECK;
            end

            STEP_DDA_CHECK: begin
                // Terminate ray if it hits a block, goes out of bounds, or reaches max depth
                if (world_data != 0 || oob_x || oob_z || oob_y || step_count == STEP_COUNT) begin

                    if (world_data != 0 && !oob_x && !oob_y && !oob_z) begin
                        tex_block_id <= world_data;
                    end else begin
                        tex_block_id <= 0; 
                    end

                    // Derive UV coordinates based on the axis that was just crossed
                    if (crossed_y) begin
                        tex_face <= 1; 
                        tex_u <= ray_x[RAY_FRC-1 : RAY_FRC - TEX_BITS];
                        tex_v <= ray_z[RAY_FRC-1 : RAY_FRC - TEX_BITS];
                    end
                    else if (crossed_x) begin
                        tex_face <= 0; 
                        tex_u <= ray_z[RAY_FRC-1 : RAY_FRC - TEX_BITS];
                        tex_v <= ~ray_y[RAY_FRC-1 : RAY_FRC - TEX_BITS];
                    end
                    else begin
                        tex_face <= 0; 
                        tex_u <= ray_x[RAY_FRC-1 : RAY_FRC - TEX_BITS];
                        tex_v <= ~ray_y[RAY_FRC-1 : RAY_FRC - TEX_BITS];
                    end

                    state <= REQ_TEXTURE;
                end
                else begin
                    state <= STEP_DDA_REQ;
                end
            end

            REQ_TEXTURE: begin
                state <= WAIT_TEXTURE;
            end

            WAIT_TEXTURE: begin
                vram_data <= tex_color;
                state <= WRITE_PIXEL;
            end

            WRITE_PIXEL: begin
                vram_x <= curr_x;
                vram_y <= curr_y;
                vram_we <= 1;
                state <= NEXT_PIXEL;
            end

            NEXT_PIXEL: begin
                vram_we <= 0;
                if (curr_x == GAME_W - 1) begin
                    curr_x <= 0;
                    if (curr_y == GAME_H - 1) begin
                        done <= 1;
                        state <= IDLE;
                    end else begin
                        curr_y <= curr_y + 1;
                        state <= REQ_ANGLE;
                    end
                end else begin
                    curr_x <= curr_x + 1;
                    state <= REQ_ANGLE;
                end
            end
        endcase
    end
endmodule