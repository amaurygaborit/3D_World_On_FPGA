package mini_minecraft_pkg;

    // Timing
    localparam TARGET_FPS = 30;
    localparam CLK_FREQ   = 12000000;

    // Voxel World
    localparam WORLD_L    = 8;          // 8x8 footprint (X and Z)
    localparam NUM_BLOCKS = 3;          // Supported block types
    localparam TEX_SIZE   = 8;          // 8x8 pixel textures (16 colors)
    localparam WORLD_SIZE = WORLD_L * WORLD_L * 7; // Total map blocks
    
    // Camera & Raycaster
    localparam FOV_H = 60;
    localparam FOV_V = 60;
    localparam PLAYER_HEIGHT = 2;       // Eye level offset
    localparam MAX_TRANSPARENCY_DEPTH = 0;

    // CPU Architecture
    localparam NUM_INST = 256;
    localparam RAM_SIZE = 256;

    // Physical Display Hardware
    localparam PHYS_W   = 80;
    localparam PHYS_H   = 160;
    localparam HW_OFF_X = 26;           // Panel-specific internal offsets
    localparam HW_OFF_Y = 1;

    // Render Target & Scaling
    localparam GAME_W   = 32;           // Internal render width
    localparam GAME_H   = 32;           // Internal render height
    localparam ZOOM     = 2;            // Integer scaling factor
    localparam GAME_X   = 0;
    localparam GAME_Y   = 0;

    // Fixed-Point Trigonometry (Q2.6 format)
    localparam ANGLE_STEPS   = 512;     // Steps for a full 360-degree circle
    localparam STEP_COUNT    = 182;     // Max ray marching steps

    localparam TRIG_INT_BITS   = 2;
    localparam TRIG_FRC_BITS   = 6;
    localparam TRIG_TOTAL_BITS = TRIG_INT_BITS + TRIG_FRC_BITS;

endpackage