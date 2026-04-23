import mini_minecraft_pkg::*;

module mini_cpu (
    input  logic        clk,
    input  logic        reset,

    output logic [$clog2(NUM_INST) - 1:0] inst_addr,
    input  logic [15:0]                   inst_data,

    // Bus d'adresse forcé sur 8 bits pour adresser toute la RAM et les MMIO (0 à 255)
    output logic [7:0]                    ram_addr,
    input  logic [7:0]                    ram_data_in,
    output logic [7:0]                    ram_data_out,
    output logic                          ram_we
);

    typedef enum logic [3:0] {
        OP_NOP  = 4'h0, OP_ADD  = 4'h1, OP_SUB  = 4'h2, OP_AND  = 4'h3,
        OP_OR   = 4'h4, OP_XOR  = 4'h5, OP_SHT  = 4'h6, OP_SHI  = 4'h7,
        OP_LDI  = 4'h8, OP_LD   = 4'h9, OP_ST   = 4'hA, OP_BEQ  = 4'hB,
        OP_BNE  = 4'hC, OP_BLT  = 4'hD, OP_JMP  = 4'hE, OP_HLT  = 4'hF 
    } opcode_t;

    // --- DÉCORTICAGE DE L'INSTRUCTION ---
    logic [3:0] opcode = inst_data[3:0];
    logic [2:0] regD   = inst_data[6:4];
    logic [2:0] src1   = inst_data[9:7];
    logic [2:0] src2   = inst_data[12:10];

    logic addCarry     = inst_data[14];
    logic invRes       = inst_data[15];
    logic signedShift  = inst_data[14];

    logic        [7:0] bigImm   = inst_data[14:7];
    logic signed [5:0] smallImm = inst_data[15:10];
    
    // Extension de signe sur 8 bits purs
    wire  [7:0] ext_smallImm = { {2{smallImm[5]}}, smallImm };

    // --- REGISTRES ET PC ---
    // HACK RISC : R0 n'est plus instancié physiquement ! (Économie de FFs et MUX)
    logic [7:0] regs [1:7];         
    logic [7:0] pc = 0;             
    
    // Si reg=0, on renvoie 0 (masse matérielle), sinon on lit le vrai registre
    logic [7:0] val_D, val_A, val_B;
    assign val_D = (regD == 3'b000) ? 8'h00 : regs[regD];
    assign val_A = (src1 == 3'b000) ? 8'h00 : regs[src1];
    assign val_B = (src2 == 3'b000) ? 8'h00 : regs[src2];

    logic [7:0] alu_result;

    // ==========================================
    // ALU (Ultra-Slim 8 bits)
    // ==========================================
    always_comb begin
        logic take_branch;
        alu_result  = 8'b0; 
        take_branch = 1'b0;

        // 1. Évaluation conditionnelle mutualisée (Fusion des comparateurs)
        case (opcode)
            OP_BEQ: take_branch = (val_D == val_A);
            OP_BNE: take_branch = (val_D != val_A);
            OP_BLT: take_branch = ($signed(val_D) < $signed(val_A));
            default: take_branch = 1'b0;
        endcase

        // 2. Calcul du résultat ALU
        case (opcode)
            // L'addition / soustraction pure (fini le + flag_c et temp_sum !)
            OP_ADD: alu_result = val_A + val_B;
            OP_SUB: alu_result = val_A - val_B;
            
            OP_AND: alu_result = val_A & val_B;
            OP_OR:  alu_result = val_A | val_B;
            OP_XOR: alu_result = val_A ^ val_B;            
            
            // OP_SHT désactivé pour économiser des dizaines de LCs (inutilisé par le firmware)
            OP_SHT: alu_result = 8'b0; 
            
            OP_SHI: alu_result = signedShift ? (val_A >> src2) : (val_A << src2);
            
            OP_LDI: alu_result = bigImm;
            
            // LD / ST : Calcul d'adresse mutualisé
            OP_LD, OP_ST: alu_result = val_A + ext_smallImm; 

            // Sauts conditionnels : Mutualisation sur un SEUL additionneur 8-bits !
            OP_BEQ, OP_BNE, OP_BLT: alu_result = pc + (take_branch ? ext_smallImm : 8'd1);

            // Si l'empreinte est exactement 0x87 (JMR R7), on saute au registre, sinon on saute à l'adresse absolue
            OP_JMP: alu_result = (bigImm == 8'h87) ? val_A : bigImm;

            OP_HLT: alu_result = pc; 
            
            default: alu_result = 8'b0;
        endcase
        
        // On n'inverse le résultat que pour les opérations arithmétiques pures
        if (invRes && (opcode < 4'h6)) alu_result = ~alu_result;
    end

    // ==========================================
    // MACHINE À ÉTATS DU CPU
    // ==========================================
    typedef enum logic [2:0] {
        FETCH, WAIT_ROM, DECODE_EXECUTE, WAIT_LD, WAIT_LD_2, WAIT_ST         
    } state_t;
    
    state_t state = FETCH;

    always_ff @(posedge clk) begin
        if (reset) begin
            pc <= 0;
            state <= FETCH;
            ram_we <= 0;
            for (int i=1; i<8; i++) regs[i] <= 0; // On ne reset que R1 à R7
        end else begin
            case (state)
                FETCH: begin
                    inst_addr <= pc;
                    ram_we <= 0;
                    state <= WAIT_ROM;
                end
                
                WAIT_ROM: begin
                    state <= DECODE_EXECUTE;
                end
                
                DECODE_EXECUTE: begin
                    case (opcode)
                        OP_ADD, OP_SUB, OP_AND, OP_OR, OP_XOR, OP_SHT, OP_SHI, OP_LDI: begin
                            // HACK RISC : On n'écrit le résultat que si la destination n'est pas R0
                            if (regD != 3'b000) regs[regD] <= alu_result;
                            pc <= pc + 1;
                            state <= FETCH;
                        end
                        
                        OP_BEQ, OP_BNE, OP_BLT, OP_JMP, OP_HLT: begin
                            pc <= alu_result;
                            state <= FETCH;
                        end
                        
                        OP_LD: begin
                            ram_addr <= alu_result; 
                            ram_we   <= 0;
                            state    <= WAIT_LD; 
                        end
                        
                        OP_ST: begin
                            ram_addr     <= alu_result;
                            ram_data_out <= val_D; // ST écrit val_D (le premier opérande)
                            ram_we       <= 1;     
                            state        <= WAIT_ST; 
                        end
                        
                        default: begin
                            pc <= pc + 1;
                            state <= FETCH;
                        end
                    endcase
                end
                
                WAIT_LD: begin
                    state <= WAIT_LD_2; 
                end
                
                WAIT_LD_2: begin
                    // HACK RISC : On protège l'écriture dans R0 ici aussi
                    if (regD != 3'b000) regs[regD] <= ram_data_in; 
                    pc <= pc + 1;              
                    state <= FETCH;
                end
                
                WAIT_ST: begin
                    ram_we <= 0;  
                    pc <= pc + 1; 
                    state <= FETCH;
                end
            endcase
        end
    end
endmodule