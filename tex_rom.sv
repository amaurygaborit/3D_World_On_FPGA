import mini_minecraft_pkg::*;

module tex_rom (
    input  logic                            clk,
    
    input  logic [$clog2(NUM_BLOCKS) - 1:0] block_id,
    input  logic                            face,     // 0 = Côté, 1 = Haut/Bas
    input  logic [$clog2(TEX_SIZE) - 1:0]   u,        // Coordonnée X sur la texture
    input  logic [$clog2(TEX_SIZE) - 1:0]   v,        // Coordonnée Y sur la texture
    
    output logic [3:0]  color_out                     // L'index de la couleur
);
    localparam ROM_SIZE = NUM_BLOCKS * TEX_SIZE * TEX_SIZE * 2;     // 2 faces (côté et haut/bas)
    logic [3:0] rom [0:ROM_SIZE - 1];

    // Chargement du fichier généré par Python
    initial begin
        $readmemh("hex/textures.hex", rom);
    end

    wire [$clog2(ROM_SIZE) - 1:0] addr = {block_id, face, v, u};

    // 1 cycle de latence
    always_ff @(posedge clk) begin
        color_out <= rom[addr];
    end

endmodule