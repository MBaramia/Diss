`timescale 1ns / 1ps
module divider #(
    parameter WIDTH = 32,  // width of Q16.16 numbers
    parameter FBITS = 16   // fractional bits
)(
    input clk,
    input rst,
    input start,                     // one-cycle start pulse for a new division
    output reg busy,                 // high while division is in progress
    output reg done,                 // one-cycle pulse when done
    output reg valid,                // asserted when output is valid
    output reg dbz,                  // divide-by-zero flag
    output reg ovf,                  // overflow flag
    input  signed [WIDTH-1:0] a,     // dividend (Q16.16)
    input  signed [WIDTH-1:0] b,     // divisor (Q16.16)
    output reg signed [WIDTH-1:0] val // quotient result (Q16.16)
);

    localparam WIDTHU = WIDTH - 1;
    localparam FBITSW = (FBITS == 0) ? 1 : FBITS;
    localparam SMALLEST = {1'b1, {WIDTHU{1'b0}}};
    localparam ITER = WIDTHU + FBITS;
    localparam ITER_BITS = 6;
    
    // Counter for iterations
    reg [ITER_BITS-1:0] i;
    reg a_sig, b_sig, sig_diff;
    reg [WIDTHU-1:0] au, bu;
    reg [WIDTHU-1:0] quo, quo_next;
    reg [WIDTHU:0] acc, acc_next;
    
    // Timeout safety counter - important for simulation
    reg [7:0] timeout_counter;
    
    // State machine states
    localparam IDLE  = 0,
               INIT  = 1,
               CALC  = 2,
               ROUND = 3,
               SIGN  = 4;
    reg [2:0] state;

    // Divider logic
    always @(*) begin
        if (acc >= {1'b0, bu}) begin
            acc_next = acc - bu;
            {acc_next, quo_next} = {acc_next[WIDTHU-1:0], quo, 1'b1};
        end else begin
            {acc_next, quo_next} = {acc, quo} << 1;
        end
    end

    // Main state machine
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            busy <= 0;
            done <= 0;
            valid <= 0;
            dbz <= 0;
            ovf <= 0;
            val <= 0;
            i <= 0;
            timeout_counter <= 0;
        end else begin
            // Default state for one-cycle signals
            done <= 0;
            
            case (state)
                IDLE: begin
                    busy <= 0;
                    valid <= 0;
                    dbz <= 0;
                    ovf <= 0;
                    timeout_counter <= 0;
                    
                    if (start) begin
                        if (b == 0) begin
                            // Divide by zero handling
                            state <= IDLE;
                            done <= 1;
                            dbz <= 1;
                            valid <= 0;
                            // Default value for divide by zero (maximum positive value)
                            val <= 32'h7FFFFFFF;
                        end else if (a == SMALLEST || b == SMALLEST) begin
                            // Overflow handling
                            state <= IDLE;
                            done <= 1;
                            ovf <= 1;
                            valid <= 0;
                            // Default value for overflow
                            val <= 32'h7FFFFFFF;
                        end else begin
                            state <= INIT;
                            if (a[WIDTH-1]) 
                                au <= -a[WIDTHU-1:0];
                            else
                                au <= a[WIDTHU-1:0];
                            if (b[WIDTH-1])
                                bu <= -b[WIDTHU-1:0];
                            else
                                bu <= b[WIDTHU-1:0];
                            sig_diff <= a[WIDTH-1] ^ b[WIDTH-1];
                            busy <= 1;
                        end
                    end
                end
                
                INIT: begin
                    state <= CALC;
                    ovf <= 0;
                    i <= 0;
                    {acc, quo} <= { {WIDTHU{1'b0}}, au, 1'b0 };
                end
                
                CALC: begin
                    // Timeout safety
                    timeout_counter <= timeout_counter + 1;
                    if (timeout_counter >= 100) begin
                        // Force completion after too many cycles
                        state <= SIGN;
                    end
                    // Overflow check
                    else if (i == WIDTHU-1 && quo_next[WIDTHU-1:WIDTHU-FBITSW] != 0) begin
                        state <= IDLE;
                        busy <= 0;
                        done <= 1;
                        ovf <= 1;
                        valid <= 0;
                    end 
                    // Normal operation
                    else begin
                        if (i == ITER-1)
                            state <= ROUND;
                        i <= i + 1;
                        acc <= acc_next;
                        quo <= quo_next;
                    end
                end
                
                ROUND: begin
                    state <= SIGN;
                    if (quo_next[0] == 1'b1) begin
                        if (quo[0] == 1'b1 || acc_next[WIDTHU:1] != 0)
                            quo <= quo + 1;
                    end
                end
                
                SIGN: begin
                    state <= IDLE;
                    if (quo != 0)
                        val <= (sig_diff) ? {1'b1, -quo} : {1'b0, quo};
                    else
                        val <= 0;
                    busy <= 0;
                    done <= 1;
                    valid <= 1;
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule