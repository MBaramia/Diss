`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// sqrt_int Module
// Computes the square root of a Q16.16 fixed-point number using an iterative algorithm.
// A rising edge on start loads the radicand and iterates for ITER cycles. When done,
// the output "root" and "rem" are valid for one clock cycle (valid asserted).
//////////////////////////////////////////////////////////////////////////////////
module sqrt #(
    parameter WIDTH = 32,  // width of radicand (Q16.16)
    parameter FBITS = 16  // fractional bits
)(
    input         clk,
    input         reset,
    input         start,             // one-cycle start pulse (rising edge triggers computation)
    output reg    busy,              // computation in progress
    output reg    valid,             // asserted for one cycle when output is valid
    input  [WIDTH-1:0] rad,          // radicand in Q16.16
    output reg [WIDTH-1:0] root,       // computed square root in Q16.16
    output reg [WIDTH-1:0] rem         // remainder (unused, but computed) in Q16.16
);

    reg [WIDTH-1:0] x, x_next;    // working copy of radicand portion
    reg [WIDTH-1:0] q, q_next;    // working quotient (the square root estimate)
    reg [WIDTH+1:0] ac, ac_next;  // accumulator (2 bits wider)
    reg [WIDTH+1:0] test_res;     // difference for the iterative test

    localparam ITER = (WIDTH+FBITS) >> 1;  // number of iterations
    reg [5:0] i;  // iteration counter

    // Start edge detector:
    reg start_d;
    wire start_edge = start & ~start_d;
    always @(posedge clk or posedge reset) begin
      if(reset) start_d <= 0;
      else start_d <= start;
    end

    // Combinational block: next iteration.
    always @(*) begin
        test_res = ac - {q, 2'b01};
        if (test_res[WIDTH+1] == 0) begin  // test_res >= 0
            {ac_next, x_next} = {test_res[WIDTH-1:0], x, 2'b0};
            q_next = {q[WIDTH-2:0], 1'b1};
        end else begin
            {ac_next, x_next} = {ac[WIDTH-1:0], x, 2'b0};
            q_next = q << 1;
        end
    end

    // Iterative state machine.
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            busy  <= 0;
            valid <= 0;
            i     <= 0;
            q     <= 0;
            ac    <= 0;
            x     <= 0;
            root  <= 0;
            rem   <= 0;
        end else begin
            if(start_edge) begin
                busy <= 1;
                valid <= 0;
                i <= ITER;
                q <= 0;
                {ac, x} <= { {WIDTH{1'b0}}, rad, 2'b0 };
            end else if(busy) begin
                if(i == 1) begin
                    busy <= 0;
                    valid <= 1;
                    root <= q_next;
                    rem <= ac_next[WIDTH+1:2]; // undo final shift
                end else begin
                    i <= i - 1;
                    x <= x_next;
                    ac <= ac_next;
                    q <= q_next;
                end
            end else begin
                valid <= 0;
            end
        end
    end

endmodule