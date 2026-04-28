import mini_minecraft_pkg::*;

module gpu_dda (
    input  logic clk,
    input  logic start,
    output logic done,

    // vram interface
    output logic [$clog2(GAME_W)-1:0] vram_x,
    output logic [$clog2(GAME_H)-1:0] vram_y,
    output logic [3:0]                vram_data,
    output logic                      vram_we,

    // trigonometry lut interface
    output logic [$clog2(ANGLE_STEPS)-1:0]    trig_angle_h,
    output logic [$clog2(ANGLE_STEPS)-1:0]    trig_angle_v,
    input  logic signed [TRIG_TOTAL_BITS-1:0] trig_sin_h,
    input  logic signed [TRIG_TOTAL_BITS-1:0] trig_cos_h,
    input  logic signed [TRIG_TOTAL_BITS-1:0] trig_sin_v,
    input  logic signed [TRIG_TOTAL_BITS-1:0] trig_cos_v,

    // world ram interface
    output logic [$clog2(WORLD_SIZE)-1:0] world_addr,
    input  logic [$clog2(NUM_BLOCKS)-1:0] world_data,

    // texture rom interface
    output logic [$clog2(NUM_BLOCKS)-1:0] tex_block_id,
    output logic                          tex_face,
    output logic [$clog2(TEX_SIZE)-1:0]   tex_u,
    output logic [$clog2(TEX_SIZE)-1:0]   tex_v,
    input  logic [3:0]                    tex_color,

    // camera and player state
    input  logic [7:0] player_x, 
    input  logic [7:0] player_y, 
    input  logic [7:0] player_z, 
    input  logic [$clog2(ANGLE_STEPS)-1:0] angle_h,
    input  logic [$clog2(ANGLE_STEPS)-1:0] angle_v
);

    // configuration and constants
    localparam WL_BITS  = $clog2(WORLD_L);
    localparam TEX_BITS = $clog2(TEX_SIZE);
    
    // fixed point precision configuration q3.10 format
    localparam RAY_FRC  = 10; 
    localparam COORD_BITS = 1 + WL_BITS + RAY_FRC; 
    
    // max steps
    localparam MAX_RAY_STEPS = 511; 

    typedef enum logic [4:0] {
        IDLE, WAIT_ROM_CAM, 
        CALC_VECTORS_1, CALC_VECTORS_1_WAIT, CALC_VECTORS_2, CALC_VECTORS_3, CALC_VECTORS_4, CALC_VECTORS_5,
        SETUP_RAY_0, SETUP_RAY_1, SETUP_RAY_2, SETUP_RAY_3, SETUP_RAY_4, SETUP_RAY_5, SETUP_RAY_FINALIZE, SETUP_RAY_APPLY,
        STEP_DDA_REQ, WAIT_WORLD, STEP_DDA_CHECK,
        REQ_TEXTURE, WAIT_TEXTURE, WRITE_PIXEL, NEXT_PIXEL
    } state_enum;
    
    state_enum state = IDLE;

    // precomputed planar projection scalars in q1.6 format
    logic signed [7:0] fov_lut_h [0:GAME_W-1];
    logic signed [7:0] fov_lut_v [0:GAME_H-1];
    initial begin
        $readmemh("hex/fov_h.hex", fov_lut_h);
        $readmemh("hex/fov_v.hex", fov_lut_v);
    end

    // dda tracking registers
    logic [$clog2(GAME_W)-1:0] curr_x = 0;
    logic [$clog2(GAME_H)-1:0] curr_y = 0;

    logic signed [COORD_BITS-1:0] ray_x, ray_y, ray_z;
    logic signed [COORD_BITS-1:0] step_x, step_y, step_z;

    // integer block coordinates extraction
    wire [WL_BITS-1:0] map_x = ray_x[RAY_FRC + WL_BITS - 1 : RAY_FRC];
    wire [WL_BITS-1:0] map_y = ray_y[RAY_FRC + WL_BITS - 1 : RAY_FRC];
    wire [WL_BITS-1:0] map_z = ray_z[RAY_FRC + WL_BITS - 1 : RAY_FRC];
    
    assign world_addr = {map_y, map_z, map_x};

    // edge crossing detection for uv mapping alignment
    logic [WL_BITS-1:0] last_map_x, last_map_y, last_map_z;
    wire crossed_x = (map_x != last_map_x);
    wire crossed_y = (map_y != last_map_y);
    wire crossed_z = (map_z != last_map_z);

    // out of bounds detection checking negative coords or upper y limit
    wire oob_x = ray_x[COORD_BITS-1]; 
    wire oob_z = ray_z[COORD_BITS-1];
    wire oob_y = ray_y[COORD_BITS-1] || (map_y == 3'b111);

    logic [8:0] step_count;

    // time multiplexed dsp slice
    // instantiates a single physical multiplier to preserve logic cells and dsp resources
    logic signed [7:0] mult_a, mult_b;
    wire signed [15:0] mult_out = mult_a * mult_b; 

    // camera basis vectors
    logic signed [15:0] dir_x_full, dir_z_full, up_x_full, up_z_full;
    logic signed [7:0]  dir_x, dir_y, dir_z;
    logic signed [7:0]  right_x, right_y, right_z;
    logic signed [7:0]  up_x, up_y, up_z;

    wire signed [7:0] px = $signed(fov_lut_h[curr_x]);
    wire signed [7:0] py = $signed(fov_lut_v[curr_y]);
    
    logic signed [15:0] rx_px, rz_px;
    logic signed [15:0] ux_py, uy_py, uz_py;

    // ray vector aggregation using 16 bit intermediate to prevent overflow
    // right shift by 6 performs q format normalization
    wire signed [15:0] ray_dx = 16'(signed'(dir_x)) + (rx_px >>> 6) + (ux_py >>> 6);
    wire signed [15:0] ray_dy = 16'(signed'(dir_y)) +                 (uy_py >>> 6);
    wire signed [15:0] ray_dz = 16'(signed'(dir_z)) + (rz_px >>> 6) + (uz_py >>> 6);

    // main fsm
    always_ff @(posedge clk) begin
        case (state)
            IDLE: begin
                done <= 0;
                vram_we <= 0;
                if (start) begin
                    trig_angle_h <= angle_h;
                    trig_angle_v <= angle_v;
                    state <= WAIT_ROM_CAM;
                end
            end

            WAIT_ROM_CAM: begin
                // trig rom read latency compensation
                mult_a <= trig_cos_h; mult_b <= trig_cos_v;
                state <= CALC_VECTORS_1;
            end

            // camera matrix multiplication pipeline
            // evaluated once per frame capturing mult_out one cycle after inputs
            CALC_VECTORS_1: begin
                dir_x_full <= mult_out; 
                mult_a <= trig_sin_h; mult_b <= trig_cos_v; 
                state <= CALC_VECTORS_2;
            end
            CALC_VECTORS_2: begin
                dir_z_full <= mult_out; 
                mult_a <= -trig_cos_h; mult_b <= trig_sin_v; 
                state <= CALC_VECTORS_3;
            end
            CALC_VECTORS_3: begin
                up_x_full <= mult_out;  
                mult_a <= -trig_sin_h; mult_b <= trig_sin_v; 
                state <= CALC_VECTORS_4;
            end
            CALC_VECTORS_4: begin
                up_z_full <= mult_out;  
                state <= CALC_VECTORS_5;
            end
            CALC_VECTORS_5: begin
                // normalize q2.14 back to q1.7
                dir_x <= 8'(dir_x_full >>> 6);
                dir_y <= trig_sin_v;
                dir_z <= 8'(dir_z_full >>> 6);

                right_x <= -trig_sin_h;
                right_y <= 0;
                right_z <= trig_cos_h;

                up_x <= 8'(up_x_full >>> 6);
                up_y <= trig_cos_v;
                up_z <= 8'(up_z_full >>> 6); 

                curr_x <= 0;
                curr_y <= 0;
                state <= SETUP_RAY_0;
            end

            // pixel ray multiplication pipeline
            // evaluated for every pixel in the viewport
            SETUP_RAY_0: begin
                // await stable px and py combinatorial reads from fov lut
                mult_a <= right_x; mult_b <= px; 
                state <= SETUP_RAY_1;
            end
            SETUP_RAY_1: begin
                rx_px <= mult_out;               
                mult_a <= right_z; mult_b <= px; 
                state <= SETUP_RAY_2;
            end
            SETUP_RAY_2: begin
                rz_px <= mult_out;               
                mult_a <= up_x; mult_b <= py;    
                state <= SETUP_RAY_3;
            end
            SETUP_RAY_3: begin
                ux_py <= mult_out;               
                mult_a <= up_y; mult_b <= py;    
                state <= SETUP_RAY_4;
            end
            SETUP_RAY_4: begin
                uy_py <= mult_out;               
                mult_a <= up_z; mult_b <= py;    
                state <= SETUP_RAY_5;
            end
            SETUP_RAY_5: begin
                uz_py <= mult_out;               
                state <= SETUP_RAY_FINALIZE;
            end
            SETUP_RAY_FINALIZE: begin
                // pipeline stall allowing one cycle for combinatorial ray aggregation
                state <= SETUP_RAY_APPLY;
            end
            SETUP_RAY_APPLY: begin
                // truncate safe 16 bit vectors to 14 bit core coordinate widths
                step_x <= COORD_BITS'(ray_dx);
                step_y <= COORD_BITS'(ray_dy);
                step_z <= COORD_BITS'(ray_dz);

                // initialize ray origin shifting q5.0 to q3.10 representation
                ray_x <= {1'b0, player_x, 5'b0};
                ray_y <= {1'b0, player_y, 5'b0};
                ray_z <= {1'b0, player_z, 5'b0};

                last_map_x <= player_x[7:5];
                last_map_y <= player_y[7:5];
                last_map_z <= player_z[7:5];

                step_count <= 0;
                state <= STEP_DDA_REQ;
            end

            // dda raymarching engine
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
                // one cycle stall to accommodate synchronous sram read latency
                state <= STEP_DDA_CHECK;
            end

            STEP_DDA_CHECK: begin
                if (world_data != 0 || oob_x || oob_z || oob_y || step_count == MAX_RAY_STEPS) begin

                    if (world_data != 0 && !oob_x && !oob_y && !oob_z) begin
                        tex_block_id <= world_data; 
                    end else begin
                        tex_block_id <= 0;          
                    end

                    // derive uv mapping and face orientation based on crossing flags
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

            // texture fetch and framebuffer write
            REQ_TEXTURE: begin
                state <= WAIT_TEXTURE;
            end

            WAIT_TEXTURE: begin
                // fallback default sky color if ray escapes the map
                if (tex_block_id == 0 && tex_color == 0) begin
                    vram_data <= 11; 
                end else begin
                    vram_data <= tex_color;
                end
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
                        state <= IDLE; // frame complete
                    end else begin
                        curr_y <= curr_y + 1;
                        state <= SETUP_RAY_0; // proceed to next scanline
                    end
                end else begin
                    curr_x <= curr_x + 1;
                    state <= SETUP_RAY_0; // proceed to next horizontal pixel
                end
            end
        endcase
    end
endmodule
