`timescale 1ns / 1ps

module logarithm #(
    parameter WIDTH = 32
)(
    input                         clk,
    input                         reset,
    input                         start,  // one-cycle start pulse
    input  signed [WIDTH-1:0]     in,     // Input in Q16.16
    output reg signed [WIDTH-1:0] out,    // Output ln(x) in Q16.16
    output reg                    valid   // asserted for two cycles
);

    // Constant for ln2 in Q16.16 (~0.6931)
    localparam signed [WIDTH-1:0] ln2 = 32'h0000B172;

    // Coefficients for polynomial approximation
    localparam signed [WIDTH-1:0] coeff2 = 32'hFFFF8000;  // -0.5
    localparam signed [WIDTH-1:0] coeff3 = 32'h00005555;  // ~1/3

    // State encoding with pipeline stages
    localparam IDLE      = 3'b000,
               NORMALIZE = 3'b001,
               COMPUTE1  = 3'b010,
               COMPUTE2  = 3'b011,
               COMPUTE3  = 3'b100,
               HOLD      = 3'b101;

    reg [2:0]              state;
    reg signed [WIDTH-1:0] mantissa;
    reg signed [31:0]      exponent;
    integer                msb_index, shift_amount;

    // Pipeline registers
    reg signed [WIDTH-1:0] x_reg, x2_reg, x3_reg;
    reg signed [WIDTH-1:0] term2_reg, term3_reg;
    reg signed [WIDTH-1:0] poly_reg;
    reg signed [WIDTH-1:0] exponent_ln2_reg;

    function integer find_msb;
        input [WIDTH-1:0] value;
        integer j;
        begin
            find_msb = -1;
            for (j = WIDTH-1; j >= 0; j = j - 1)
                if (value[j]) find_msb = j;
        end
    endfunction

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state    <= IDLE;
            valid    <= 0;
            out      <= 0;
            {mantissa, exponent, x_reg, x2_reg, x3_reg, term2_reg, term3_reg, poly_reg} <= 0;
        end else begin
            case (state)
                IDLE: begin
                    valid <= 0;
                    if (start) begin
                        msb_index = find_msb(in);
                        exponent  <= msb_index - 16;
                        shift_amount = msb_index - 16;
                        mantissa <= (shift_amount > 0) ? 
                                  ((in + (1 << (shift_amount - 1))) >> shift_amount) : in;
                        state <= NORMALIZE;
                    end
                end

                NORMALIZE: begin
                    // Stage 1: Compute x, x^2, and exponent*ln2
                    x_reg <= mantissa - 32'h00010000;  // x = m - 1.0
                    x2_reg <= (x_reg * x_reg) >>> 16;  // x^2 in Q16.16
                    exponent_ln2_reg <= exponent * ln2; // Precompute exponent term
                    state <= COMPUTE1;
                end

                COMPUTE1: begin
                    // Stage 2: Compute x^3 and polynomial terms
                    x3_reg <= (x2_reg * x_reg) >>> 16;    // x^3
                    term2_reg <= (x2_reg * coeff2) >>> 16; // -0.5x^2
                    term3_reg <= (x3_reg * coeff3) >>> 16; // (1/3)x^3
                    state <= COMPUTE2;
                end

                COMPUTE2: begin
                    // Stage 3: Sum polynomial terms
                    poly_reg <= x_reg + term2_reg + term3_reg;
                    state <= COMPUTE3;
                end

                COMPUTE3: begin
                    // Final output calculation
                    out <= poly_reg + exponent_ln2_reg;
                    valid <= 1;
                    state <= HOLD;
                end

                HOLD: begin
                    valid <= 1;  // Hold valid for second cycle
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule