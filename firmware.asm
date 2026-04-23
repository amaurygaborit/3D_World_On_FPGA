// Mini-Colossus Micro-Minecraft Firmware
// Target: 8x8x7 Voxel World, Custom 8-bit CPU Architecture

// --- Memory Map Constants ---
CONST PLAYER_BASE  0x00
CONST IO_BASE      0x10
CONST WORLD_BASE   0x20

// --- Player Struct Offsets ---
CONST OFF_X        0   
CONST OFF_Y        1   
CONST OFF_Z        2   
CONST OFF_ANG_H    3
CONST OFF_ANG_V    4    
CONST OFF_INPUT    5
CONST OFF_NEWX     6
CONST OFF_NEWZ     7
CONST OFF_DIR_X    8   
CONST OFF_DIR_Z    9   

// --- MMIO GPU/Hardware Offsets ---
CONST OFF_IN_INPUT  0
CONST OFF_IN_GTRIG  1
CONST OFF_IN_GSTAT  2
CONST OFF_IN_GPX    3
CONST OFF_IN_GPY    4
CONST OFF_IN_GPZ    5
CONST OFF_IN_GANG_H 6
CONST OFF_IN_GANG_V 7  
CONST OFF_IN_ACTION 8   

// --- Game Engine Constants ---
CONST MOVE_SPEED 4    
CONST ROT_SPEED  4
CONST PLACE_BLOCK_TYPE 1 

    JMP main

// ------------------------------------------------------------------
// Subroutine: get_block
// Input: R1=X, R2=Y, R3=Z (Block coordinates)
// Output: R4=Block ID
// Desc: Maps 3D coords to linear memory. 2 blocks are packed per byte.
// ------------------------------------------------------------------
get_block:
    SHI  R4, R2, 5, 0      // R4 = Y * 32 (Since 8x8 layer = 64 blocks, packed in 32 bytes)
    SHI  R5, R3, 2, 0      // R5 = Z * 4 (Row offset)
    ADD  R4, R4, R5, 0     
    SHI  R5, R1, 1, 1      // R5 = X / 2 (Byte offset in row)
    ADD  R4, R4, R5, 0     
    LDI  R5, WORLD_BASE
    ADD  R5, R4, R5, 0     // R5 = Absolute memory address
    LDI  R6, 1
    AND  R6, R1, R6        // Check if X is odd or even (determines nibble)
    LD   R4, R5, 0         // Fetch the raw byte containing two blocks
    BEQ  R6, R0, get_block_low 
    SHI  R4, R4, 4, 1      // Shift right if we need the upper nibble
get_block_low:
    LDI  R6, 0x0F
    AND  R4, R4, R6        // Mask out the other block
    JMR  R7                // Return

// ------------------------------------------------------------------
// Subroutine: set_block
// Input: R1=X, R2=Y, R3=Z, R4=New Block ID
// Desc: Updates a specific 4-bit nibble in the world RAM without 
//       destroying the neighboring block in the same byte.
// ------------------------------------------------------------------
set_block:
    SHI  R6, R2, 5, 0      
    SHI  R5, R3, 2, 0      
    ADD  R6, R6, R5, 0     
    SHI  R5, R1, 1, 1      
    ADD  R6, R6, R5, 0     
    LDI  R5, WORLD_BASE
    ADD  R6, R6, R5, 0     // R6 = Absolute memory address
    LD   R5, R6, 0         // Load the existing byte
    LDI  R2, 1
    AND  R2, R1, R2        
    BEQ  R2, R0, set_low
    LDI  R2, 0x0F
    AND  R5, R5, R2        // Clear upper nibble
    SHI  R4, R4, 4, 0      // Shift new block ID to upper nibble
    OR   R5, R5, R4        // Combine
    JMP  set_done
set_low:
    LDI  R2, 240           // Mask 0xF0
    AND  R5, R5, R2        // Clear lower nibble
    LDI  R2, 0x0F
    AND  R4, R4, R2        
    OR   R5, R5, R4        // Combine
set_done:
    ST   R5, R6, 0         // Save back to RAM
    JMR  R7

// ------------------------------------------------------------------
// Entry Point
// ------------------------------------------------------------------
main:
    LDI  R5, PLAYER_BASE
    LDI  R1, 144 
    ST   R1, R5, OFF_X     // Start at center X
    ST   R1, R5, OFF_Z     // Start at center Z
    LDI  R1, 32  
    ST   R1, R5, OFF_Y     // Start at elevation 1 block (32 units)
    LDI  R1, 0
    ST   R1, R5, OFF_ANG_H
    ST   R1, R5, OFF_ANG_V

game_loop:
    // Read UART Input directly from hardware mapped RAM (Addr 15)
    LDI  R5, PLAYER_BASE
    LD   R6, R5, 15        // R6 = ASCII Keycode
    ST   R0, R5, 15        // Clear register to prevent infinite input repeating
    ST   R6, R5, OFF_INPUT

    // Camera Rotation Processing (Q, E, R, F)
    LDI  R3, ROT_SPEED 
    
    LDI  R4, 113           // 'q' (Yaw Left)
    BNE  R6, R4, skip_rot_left
    LD   R4, R5, OFF_ANG_H
    SUB  R4, R4, R3, 0     
    ST   R4, R5, OFF_ANG_H
skip_rot_left:
    
    LDI  R4, 101           // 'e' (Yaw Right)
    BNE  R6, R4, skip_rot_right
    LD   R4, R5, OFF_ANG_H
    ADD  R4, R4, R3, 0     
    ST   R4, R5, OFF_ANG_H
skip_rot_right:
    
    LDI  R4, 114           // 'r' (Pitch Up)
    BNE  R6, R4, skip_rot_up
    LD   R4, R5, OFF_ANG_V
    ADD  R4, R4, R3, 0     
    ST   R4, R5, OFF_ANG_V
skip_rot_up:
    
    LDI  R4, 102           // 'f' (Pitch Down)
    BNE  R6, R4, skip_rot_down
    LD   R4, R5, OFF_ANG_V
    SUB  R4, R4, R3, 0     
    ST   R4, R5, OFF_ANG_V
skip_rot_down:

    // Determine orthogonal movement vector based on current yaw angle
    // Resolves 360 degrees into 4 cardinal directions
    LD   R6, R5, OFF_ANG_H
    LDI  R4, 32
    ADD  R6, R6, R4, 0     
    SHI  R6, R6, 6, 1      // Divide angle by 64 to get quadrant (0 to 3)
    LDI  R1, MOVE_SPEED    
    LDI  R2, 0
    BEQ  R6, R0, store_dir
    LDI  R1, 0             
    LDI  R2, MOVE_SPEED
    LDI  R3, 1
    BEQ  R6, R3, store_dir
    LDI  R1, 256 - MOVE_SPEED  // Two's complement for negative speed
    LDI  R2, 0
    LDI  R3, 2
    BEQ  R6, R3, store_dir
    LDI  R1, 0             
    LDI  R2, 256 - MOVE_SPEED
store_dir:
    ST   R1, R5, OFF_DIR_X
    ST   R2, R5, OFF_DIR_Z

    // Block Placement Logic (Spacebar)
    LDI  R4, 32            // 'Space'
    BNE  R6, R4, skip_place

do_place:
    LDI  R5, PLAYER_BASE
    LD   R1, R5, OFF_X
    SHI  R1, R1, 5, 1      // Convert world coord to block coord (divide by 32)
    LD   R3, R5, OFF_DIR_X
    LDI  R4, 128
    AND  R4, R3, R4        // Extract sign bit
    BNE  R4, R0, dirx_neg
    BEQ  R3, R0, apply_dirx
    LDI  R3, 1             // Place +1 in X
    JMP  apply_dirx
dirx_neg: 
    LDI  R3, 255           // Place -1 in X
apply_dirx: 
    ADD  R1, R1, R3, 0

    LD   R3, R5, OFF_Z
    SHI  R3, R3, 5, 1
    LD   R2, R5, OFF_DIR_Z
    LDI  R4, 128
    AND  R4, R2, R4
    BNE  R4, R0, dirz_neg
    BEQ  R2, R0, apply_dirz
    LDI  R2, 1             // Place +1 in Z
    JMP  apply_dirz
dirz_neg: 
    LDI  R2, 255           // Place -1 in Z
apply_dirz: 
    ADD  R3, R3, R2, 0

    LD   R2, R5, OFF_Y            
    SHI  R2, R2, 5, 1 
    
    // Bounds checking before placing
    LDI  R4, 7
    BLT  R1, R0, skip_place
    BLT  R4, R1, skip_place
    BLT  R3, R0, skip_place
    BLT  R4, R3, skip_place

    LDI  R4, PLACE_BLOCK_TYPE
    LDI  R7, ret_place
    JMP  set_block
ret_place:
    LDI  R5, PLAYER_BASE
skip_place:

    // Movement Processing (W, A, S, D)
    LDI  R5, PLAYER_BASE
    LD   R6, R5, OFF_INPUT
    LD   R1, R5, OFF_X     
    LD   R2, R5, OFF_Z     
    LD   R3, R5, OFF_DIR_X
    LD   R4, R5, OFF_DIR_Z

    LDI  R7, 119           // 'w' (Forward)
    BNE  R6, R7, skip_w
    ADD  R1, R1, R3, 0
    ADD  R2, R2, R4, 0
skip_w:
    LDI  R7, 115           // 's' (Backward)
    BNE  R6, R7, skip_s
    SUB  R1, R1, R3, 0
    SUB  R2, R2, R4, 0
skip_s:
    LDI  R7, 97            // 'a' (Strafe Left)
    BNE  R6, R7, skip_a
    ADD  R1, R1, R4, 0
    SUB  R2, R2, R3, 0
skip_a:
    LDI  R7, 100           // 'd' (Strafe Right)
    BNE  R6, R7, skip_d
    SUB  R1, R1, R4, 0
    ADD  R2, R2, R3, 0
skip_d:

    // Map Boundary Clamping (Prevents wraparound integer overflow)
    LDI  R4, 252           // Mask for edge detection
    AND  R6, R1, R4
    BEQ  R6, R0, clamp_x_min
    BEQ  R6, R4, clamp_x_max
    JMP  clamp_x_ok
clamp_x_min:
    LDI  R1, 4             // Min bound
    JMP  clamp_x_ok
clamp_x_max:
    LDI  R1, 251           // Max bound
clamp_x_ok:
    ST   R1, R5, OFF_NEWX

    AND  R6, R2, R4
    BEQ  R6, R0, clamp_z_min
    BEQ  R6, R4, clamp_z_max
    JMP  clamp_z_ok
clamp_z_min:
    LDI  R2, 4
    JMP  clamp_z_ok
clamp_z_max:
    LDI  R2, 251
clamp_z_ok:
    ST   R2, R5, OFF_NEWZ
    
    // Collision Detection
    // Step 1: Check block at foot level in the proposed new position
    LD   R1, R5, OFF_NEWX  
    SHI  R1, R1, 5, 1
    LD   R2, R5, OFF_Y     
    SHI  R2, R2, 5, 1
    LD   R3, R5, OFF_NEWZ  
    SHI  R3, R3, 5, 1
    LDI  R7, ret_collision_foot
    JMP  get_block
ret_collision_foot:
    LDI  R5, PLAYER_BASE     
    BEQ  R4, R0, apply_move  // If empty space, move is valid

    // Step 2: Auto-step up logic (Check if block above is empty and height limit allows)
    LD   R2, R5, OFF_Y     
    LDI  R3, 32
    ADD  R2, R2, R3, 0     
    SHI  R3, R2, 5, 1       
    LDI  R4, 6             
    BLT  R4, R3, deny_move   // Reject if stepping up exceeds world height

    LD   R1, R5, OFF_NEWX
    SHI  R1, R1, 5, 1
    LD   R3, R5, OFF_NEWZ
    SHI  R3, R3, 5, 1
    SHI  R2, R2, 5, 1
    LDI  R7, ret_step_up
    JMP  get_block
ret_step_up:
    LDI  R5, PLAYER_BASE     
    BNE  R4, R0, deny_move   // Reject if block above is also solid

    // Execute step up
    LD   R6, R5, OFF_Y
    LDI  R1, 32
    ADD  R6, R6, R1, 0     
    ST   R6, R5, OFF_Y

apply_move:
    LD   R1, R5, OFF_NEWX
    LD   R3, R5, OFF_NEWZ
    ST   R1, R5, OFF_X
    ST   R3, R5, OFF_Z
    JMP  move_done
deny_move:
move_done:

    // Gravity Application
    // Continuously checks block directly beneath player, falling 1 block at a time
gravity_loop:
    LD   R1, R5, OFF_X
    SHI  R1, R1, 5, 1
    LD   R2, R5, OFF_Y
    SHI  R2, R2, 5, 1
    LD   R3, R5, OFF_Z
    SHI  R3, R3, 5, 1

    BEQ  R2, R0, gravity_done // Stop if at bedrock (Y=0)
    LDI  R6, 1
    SUB  R2, R2, R6, 0     
    LDI  R7, ret_gravity_check
    JMP  get_block
ret_gravity_check:
    LDI  R5, PLAYER_BASE     
    BNE  R4, R0, gravity_done // Stop falling if solid block detected

    LD   R2, R5, OFF_Y
    LDI  R6, 32
    SUB  R2, R2, R6, 0
    ST   R2, R5, OFF_Y
    JMP  gravity_loop

gravity_done:
    // Update GPU via Memory Mapped IO
    LDI  R3, IO_BASE
    LD   R1, R5, OFF_X
    ST   R1, R3, OFF_IN_GPX
    LD   R1, R5, OFF_Y
    ST   R1, R3, OFF_IN_GPY
    LD   R1, R5, OFF_Z
    ST   R1, R3, OFF_IN_GPZ
    LD   R1, R5, OFF_ANG_H
    ST   R1, R3, OFF_IN_GANG_H
    LD   R1, R5, OFF_ANG_V      
    ST   R1, R3, OFF_IN_GANG_V  

    // Frame Pacer (VSync Simulation)
    // Ensures physics and rendering stay locked to hardware frame rate
wait_gpu_start:
    LD   R1, R3, OFF_IN_GSTAT
    BEQ  R1, R0, wait_gpu_start  // Wait for GPU to assert drawing phase

wait_gpu_done:
    LD   R1, R3, OFF_IN_GSTAT
    BNE  R1, R0, wait_gpu_done   // Wait for GPU to finish drawing

    JMP  game_loop