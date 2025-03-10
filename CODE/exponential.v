`timescale 1ns / 1ps

module exponential #(
    parameter WIDTH = 32
)(
    input clk,
    input reset,
    input start,                            // Pulse high to begin computation
    input signed [WIDTH-1:0] x,             // Input x (Q16.16)
    output reg signed [WIDTH-1:0] y,        // Output e^(-x) (Q16.16)
    output reg done                         // Asserted for two cycles when result is valid
);

    // Constants in Q16.16
    localparam signed [WIDTH-1:0] one                  = 32'h00010000; // 1.0
    localparam signed [WIDTH-1:0] two_inv              = 32'h00008000; // 1/2
    localparam signed [WIDTH-1:0] six_inv              = 32'h00002AAA; // ~1/6
    localparam signed [WIDTH-1:0] twenty_four_inv      = 32'h00000AAA; // ~1/24
    localparam signed [WIDTH-1:0] one_twenty_inv       = 32'h00000222; // ~1/120
    localparam signed [WIDTH-1:0] one_seventy_inv      = 32'h0000005B; // ~1/720
    localparam signed [WIDTH-1:0] one_fifty_inv        = 32'h0000000D; // ~1/5040

    // Pipeline registers for intermediate results
    reg signed [WIDTH-1:0] x_reg;           // Latched input

    // Multiplication pipeline registers
    reg signed [WIDTH-1:0] mult1_a, mult1_b;
    reg signed [2*WIDTH-1:0] mult1_result;
    reg signed [WIDTH-1:0] mult1_out;
    
    reg signed [WIDTH-1:0] mult2_a, mult2_b;
    reg signed [2*WIDTH-1:0] mult2_result;
    reg signed [WIDTH-1:0] mult2_out;
    
    // Power calculation registers
    reg signed [WIDTH-1:0] x_squared, x_cubed, x_fourth;
    reg signed [WIDTH-1:0] x_fifth, x_sixth, x_seventh;
    
    // Term calculation registers
    reg signed [WIDTH-1:0] term1, term2, term3, term4;
    reg signed [WIDTH-1:0] term5, term6, term7, term8;
    
    // Sum pipeline registers
    reg signed [WIDTH-1:0] sum1, sum2, sum3, sum4;
    
    // State machine with more pipeline stages
    reg [5:0] state;
    
    // Pipeline valid flags
    reg [15:0] stage_valid;
    
    // Register to detect a rising edge on start
    reg prev_start;
    
    always @(posedge clk) begin
        if (reset)
            prev_start <= 1'b0;
        else
            prev_start <= start;
    end

    // Pipelined multiplier 1
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            mult1_result <= 0;
            mult1_out <= 0;
        end else begin
            mult1_result <= $signed(mult1_a) * $signed(mult1_b);
            mult1_out <= mult1_result[47:16];
        end
    end
    
    // Pipelined multiplier 2
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            mult2_result <= 0;
            mult2_out <= 0;
        end else begin
            mult2_result <= $signed(mult2_a) * $signed(mult2_b);
            mult2_out <= mult2_result[47:16];
        end
    end

    // Main state machine
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= 6'd0;
            x_reg <= 0;
            x_squared <= 0;
            x_cubed <= 0;
            x_fourth <= 0;
            x_fifth <= 0;
            x_sixth <= 0;
            x_seventh <= 0;
            term1 <= 0;
            term2 <= 0;
            term3 <= 0;
            term4 <= 0;
            term5 <= 0;
            term6 <= 0;
            term7 <= 0;
            term8 <= 0;
            sum1 <= 0;
            sum2 <= 0;
            sum3 <= 0;
            sum4 <= 0;
            y <= 0;
            done <= 0;
            stage_valid <= 16'd0;
            mult1_a <= 0;
            mult1_b <= 0;
            mult2_a <= 0;
            mult2_b <= 0;
        end else begin
            // Default state for done signal
            done <= 0;
            
            // Pipeline valid flags shift register
            stage_valid <= {stage_valid[14:0], 1'b0};
            
            case (state)
                6'd0: begin
                    if (start && !prev_start) begin
                        x_reg <= x;
                        state <= 6'd1;
                        stage_valid[0] <= 1'b1;
                    end
                end
                
                6'd1: begin
                    // Start x^2 calculation
                    mult1_a <= x_reg;
                    mult1_b <= x_reg;
                    state <= 6'd2;
                end
                
                6'd2: begin
                    // Wait for x^2
                    state <= 6'd3;
                end
                
                6'd3: begin
                    // Store x^2 and start x^3
                    x_squared <= mult1_out;
                    mult1_a <= mult1_out;
                    mult1_b <= x_reg;
                    
                    // Start calculating term2 = -x
                    term2 <= -x_reg;
                    
                    state <= 6'd4;
                end
                
                6'd4: begin
                    // Wait for x^3
                    state <= 6'd5;
                end
                
                6'd5: begin
                    // Store x^3 and start x^4 and term3
                    x_cubed <= mult1_out;
                    mult1_a <= mult1_out;
                    mult1_b <= x_reg;
                    
                    // Start term3 calculation = x^2 * (1/2)
                    mult2_a <= x_squared;
                    mult2_b <= two_inv;
                    
                    state <= 6'd6;
                end
                
                6'd6: begin
                    // Wait for multiplications
                    state <= 6'd7;
                end
                
                6'd7: begin
                    // Store x^4 and start x^5
                    x_fourth <= mult1_out;
                    mult1_a <= mult1_out;
                    mult1_b <= x_reg;
                    
                    // Store term3 and start term4
                    term3 <= mult2_out;
                    mult2_a <= x_cubed;
                    mult2_b <= six_inv;
                    
                    state <= 6'd8;
                end
                
                6'd8: begin
                    // Wait for multiplications
                    state <= 6'd9;
                end
                
                6'd9: begin
                    // Store x^5 and start x^6
                    x_fifth <= mult1_out;
                    mult1_a <= mult1_out;
                    mult1_b <= x_reg;
                    
                    // Store term4 and start term5
                    term4 <= -mult2_out;  // Note the negative sign
                    mult2_a <= x_fourth;
                    mult2_b <= twenty_four_inv;
                    
                    state <= 6'd10;
                end
                
                6'd10: begin
                    // Wait for multiplications
                    state <= 6'd11;
                end
                
                6'd11: begin
                    // Store x^6 and start x^7
                    x_sixth <= mult1_out;
                    mult1_a <= mult1_out;
                    mult1_b <= x_reg;
                    
                    // Store term5 and start term6
                    term5 <= mult2_out;
                    mult2_a <= x_fifth;
                    mult2_b <= one_twenty_inv;
                    
                    state <= 6'd12;
                end
                
                6'd12: begin
                    // Wait for multiplications
                    state <= 6'd13;
                end
                
                6'd13: begin
                    // Store x^7
                    x_seventh <= mult1_out;
                    
                    // Store term6 and start term7
                    term6 <= -mult2_out;  // Note the negative sign
                    mult2_a <= x_sixth;
                    mult2_b <= one_seventy_inv;
                    
                    // Set term1
                    term1 <= one;
                    
                    state <= 6'd14;
                end
                
                6'd14: begin
                    // Wait for term7 calculation
                    state <= 6'd15;
                end
                
                6'd15: begin
                    // Store term7 and start term8
                    term7 <= mult2_out;
                    mult2_a <= x_seventh;
                    mult2_b <= one_fifty_inv;
                    
                    // Begin first level of summation
                    sum1 <= term1 + term2;
                    
                    state <= 6'd16;
                end
                
                6'd16: begin
                    // Wait for term8 calculation
                    // Continue summation pipeline
                    sum2 <= term3 + term4;
                    state <= 6'd17;
                end
                
                6'd17: begin
                    // Store term8
                    term8 <= -mult2_out;  // Note the negative sign
                    
                    // Continue summation pipeline
                    sum3 <= term5 + term6;
                    sum1 <= sum1 + sum2;
                    
                    state <= 6'd18;
                end
                
                6'd18: begin
                    // Continue summation pipeline
                    sum4 <= term7 + term8;
                    sum2 <= sum1 + sum3;
                    
                    state <= 6'd19;
                end
                
                6'd19: begin
                    // Final summation
                    y <= sum2 + sum4;
                    
                    state <= 6'd20;
                end
                
                6'd20: begin
                    // Signal completion
                    done <= 1;
                    state <= 6'd0;
                end
                
                default: state <= 6'd0;
            endcase
        end
    end
endmodule