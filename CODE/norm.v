`timescale 1ns / 1ps
module norm #(
    parameter WIDTH = 32
)(
    input clk,
    input reset,
    input start,
    input signed [WIDTH-1:0] d1,
    input signed [WIDTH-1:0] d2,
    output reg signed [WIDTH-1:0] Nd1,
    output reg signed [WIDTH-1:0] Nd2,
    output reg done
);
    // Internal signals
    wire done1, done2;
    reg start1, start2;
    
    // State machine
    localparam IDLE = 0;
    localparam PROC_D1 = 1;
    localparam PROC_D2 = 2;
    localparam COMPLETE = 3;
    
    reg [1:0] state;
    
    // Results from individual modules
    wire signed [WIDTH-1:0] cdf1, cdf2;
    
    // Instantiate norm_single modules
    norm_single #(WIDTH) norm1 (
        .clk(clk),
        .reset(reset),
        .start(start1),
        .d(d1),
        .N(cdf1),
        .done(done1)
    );
    
    norm_single #(WIDTH) norm2 (
        .clk(clk),
        .reset(reset),
        .start(start2),
        .d(d2),
        .N(cdf2),
        .done(done2)
    );
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            start1 <= 0;
            start2 <= 0;
            Nd1 <= 0;
            Nd2 <= 0;
            done <= 0;
        end else begin
            // Default state for one-cycle pulses
            start1 <= 0;
            start2 <= 0;
            
            case (state)
                IDLE: begin
                    done <= 0;
                    if (start) begin
                        start1 <= 1;
                        state <= PROC_D1;
                    end
                end
                
                PROC_D1: begin
                    if (done1) begin
                        Nd1 <= cdf1;
                        start2 <= 1;
                        state <= PROC_D2;
                    end
                end
                
                PROC_D2: begin
                    if (done2) begin
                        Nd2 <= cdf2;
                        done <= 1;
                        state <= COMPLETE;
                    end
                end
                
                COMPLETE: begin
                    if (!start) begin
                        state <= IDLE;
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end
    
endmodule