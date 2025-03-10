`timescale 1ns / 1ps
module norm_single #(
    parameter WIDTH = 32
)(
    input clk,
    input reset,
    input start,
    input signed [WIDTH-1:0] d,
    output reg signed [WIDTH-1:0] N,
    output reg done
);
    // Fixed-point constants (Q16.16 format)
    localparam signed [WIDTH-1:0] ONE      = 32'h00010000; // 1.0
    localparam signed [WIDTH-1:0] HALF     = 32'h00008000; // 0.5
    localparam signed [WIDTH-1:0] POINT_ONE = 32'h00001999; // 0.1 in Q16.16
    
    // Thresholds for approximation
    localparam signed [WIDTH-1:0] THRESH_HIGH = 32'h00030000; // 3.0
    
    // State machine
    localparam IDLE          = 0;
    localparam COMPUTE       = 1;
    localparam DONE          = 2;
    
    reg [3:0] state;
    
    // Internal registers
    reg signed [WIDTH-1:0] x_abs;
    reg is_negative;
    reg signed [63:0] temp;
    
    // Variables for lookup table interpolation
    reg [4:0] lut_idx;
    reg signed [WIDTH-1:0] lut_val1, lut_val2;
    reg signed [WIDTH-1:0] fraction;
    reg signed [WIDTH-1:0] delta;

    // Lookup table for CDF values at 0.1 increments (Q16.16)
    // Index: x = 0.0, 0.1, 0.2, ..., 2.9, 3.0
    // Values correspond to N(x)
    reg signed [WIDTH-1:0] lut [0:30];
    
    // Initialize the lookup table with provided values
    initial begin
        lut[0]  = 32'h00008000; // 0.0 -> 0.5000
        lut[1]  = 32'h00008A14; // 0.1 -> 0.539827837
        lut[2]  = 32'h00009434; // 0.2 -> 0.579259709
        lut[3]  = 32'h00009E6A; // 0.3 -> 0.617911422
        lut[4]  = 32'h0000A7F0; // 0.4 -> 0.655421742
        lut[5]  = 32'h0000B0F4; // 0.5 -> 0.691462461
        lut[6]  = 32'h0000B9E3; // 0.6 -> 0.725746882
        lut[7]  = 32'h0000C223; // 0.7 -> 0.758036348
        lut[8]  = 32'h0000C9BB; // 0.8 -> 0.788144601
        lut[9]  = 32'h0000D106; // 0.9 -> 0.815939875
        lut[10] = 32'h0000D7B0; // 1.0 -> 0.841344746
        lut[11] = 32'h0000DD4E; // 1.1 -> 0.864333939
        lut[12] = 32'h0000E267; // 1.2 -> 0.88493033
        lut[13] = 32'h0000E71D; // 1.3 -> 0.903199515
        lut[14] = 32'h0000EB5E; // 1.4 -> 0.919243341
        lut[15] = 32'h0000EF24; // 1.5 -> 0.933192799
        lut[16] = 32'h0000F1F3; // 1.6 -> 0.945200708
        lut[17] = 32'h0000F44E; // 1.7 -> 0.955434537
        lut[18] = 32'h0000F68F; // 1.8 -> 0.964069681
        lut[19] = 32'h0000F89D; // 1.9 -> 0.97128344
        lut[20] = 32'h0000FA40; // 2.0 -> 0.977249868
        lut[21] = 32'h0000FB76; // 2.1 -> 0.982135579
        lut[22] = 32'h0000FC75; // 2.2 -> 0.986096552
        lut[23] = 32'h0000FD43; // 2.3 -> 0.98927589
        lut[24] = 32'h0000FDEA; // 2.4 -> 0.991802464
        lut[25] = 32'h0000FE71; // 2.5 -> 0.993790335
        lut[26] = 32'h0000FEED; // 2.6 -> 0.995338812
        lut[27] = 32'h0000FF4A; // 2.7 -> 0.996533026
        lut[28] = 32'h0000FF92; // 2.8 -> 0.99744487
        lut[29] = 32'h0000FFCB; // 2.9 -> 0.998134187
        lut[30] = 32'h0000FFF5; // 3.0 -> 0.998650102
    end
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            done <= 0;
            N <= 0;
            lut_idx <= 0;
            lut_val1 <= 0;
            lut_val2 <= 0;
            fraction <= 0;
            delta <= 0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 0;
                    if (start) begin
                        // Capture input sign and absolute value
                        is_negative <= d[WIDTH-1];
                        x_abs <= d[WIDTH-1] ? -d : d;
                        state <= COMPUTE;
                    end
                end
                
                COMPUTE: begin
                    // Handle special cases first
                    if (x_abs == 0) begin
                        // N(0) = 0.5 exactly
                        N <= HALF;
                    end 
                    else if (x_abs >= THRESH_HIGH) begin
                        // For values >= 3.0: N(x) ? 1.0 for positive x, N(x) ? 0.0 for negative x
                        N <= is_negative ? 32'h00000000 : ONE;
                    end
                    else begin
                        // Find the index for lookup table interpolation
                        // Each 0.1 unit represents one step in the table
                        // lut_idx = floor(x_abs / 0.1)
                        
                        // Divide by 0.1 (multiply by 10)
                        temp = x_abs * 'd10;
                        lut_idx = temp[47:16] > 30 ? 30 : temp[47:16];
                        
                        // Get values from lookup table
                        lut_val1 = lut[lut_idx];
                        lut_val2 = (lut_idx < 30) ? lut[lut_idx+1] : lut[30]; // Prevent out-of-bounds
                        
                        // Calculate the fractional part
                        // fraction = (x_abs - lut_idx*0.1) / 0.1
                        fraction = x_abs - (lut_idx * POINT_ONE); // Subtract base value
                        temp = fraction * 'd10; // Divide by 0.1 (multiply by 10)
                        fraction = temp[47:16];
                        
                        // Linear interpolation: val1 + fraction * (val2 - val1)
                        delta = lut_val2 - lut_val1;
                        temp = delta * fraction;
                        delta = temp[47:16];
                        
                        // Apply symmetry for negative inputs: N(-x) = 1 - N(x)
                        if (is_negative) begin
                            N <= ONE - (lut_val1 + delta);
                        end else begin
                            N <= lut_val1 + delta;
                        end
                        
                       
                    end
                    state <= DONE;
                end
                
                DONE: begin
                    done <= 1;
                    state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end
endmodule