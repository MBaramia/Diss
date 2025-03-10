module OptionPrice #(
    parameter WIDTH = 32
)(
    input clk,
    input reset,
    input signed [WIDTH-1:0] rate,      // Risk-free rate (Q16.16)
    input signed [WIDTH-1:0] timetm,    // Time to maturity (Q16.16)
    input signed [WIDTH-1:0] spot,      // Spot price (Q16.16)
    input signed [WIDTH-1:0] strike,    // Strike (Q16.16)
    input signed [WIDTH-1:0] Nd1,       // CND of d1 (Q16.16)
    input signed [WIDTH-1:0] Nd2,       // CND of d2 (Q16.16)
    input otype,                        // 0 for call, 1 for put
    input norm_done,                    // Done signal from the norm module
    output reg signed [WIDTH-1:0] OptionPrice, // Option price (Q16.16)
    output reg exp_start,               // Start signal for the exponential module
    input exp_done                      // Done signal from the exponential module
);
    // Internal signals (all Q16.16 signed)
    reg signed [WIDTH-1:0] exp_input;   // Input to exponential module
    wire signed [WIDTH-1:0] exp_output; // Output from exponential module
    reg signed [WIDTH-1:0] Ke_rt;
    reg signed [WIDTH-1:0] spot_Nd1;
    reg signed [WIDTH-1:0] Ke_rt_Nd2;
    reg signed [WIDTH-1:0] COptionPrice;
    reg signed [WIDTH-1:0] POptionPrice;
    reg [2:0] state;                    // 3-bit state machine
    // 64-bit temporary for multiplications
    reg signed [63:0] temp64;

    // Instantiate the exponential module.
    exponential exp_module (
        .clk(clk),
        .reset(reset),
        .start(exp_start),
        .x(exp_input),
        .y(exp_output),
        .done(exp_done)  
    );

    // OptionPrice state machine with detailed debug prints.
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= 3'b000;
            OptionPrice <= 0;
            exp_input <= 0;
            Ke_rt <= 0;
            spot_Nd1 <= 0;
            Ke_rt_Nd2 <= 0;
            COptionPrice <= 0;
            POptionPrice <= 0;
            exp_start <= 0;
        end else begin
            case (state)
                3'b000: begin
                    // Wait for the norm module to complete (norm_done == 1).
                    if (norm_done) begin
                        // Compute exp_input = (rate * timetm) >>> 16.
                        exp_input <= ((rate * timetm) >>> 16);
                        state <= 3'b001;
                    end
                end
                3'b001: begin
                    // Start the exponential module.
                    exp_start <= 1;
                    state <= 3'b010;
                end
                3'b010: begin
                    // Wait for the exponential module to complete.
                    if (exp_done) begin
                        exp_start <= 0;
                        // Compute Ke_rt = (strike * exp_output)
                        temp64 = $signed(strike) * $signed(exp_output);
                        Ke_rt <= temp64[47:16];
                        state <= 3'b011;
                    end
                end
                3'b011: begin
                    // Compute spot_Nd1 = (spot * Nd1)
                    temp64 = $signed(spot) * $signed(Nd1);
                    spot_Nd1 <= temp64[47:16];
                    state <= 3'b100;
                end
                3'b100: begin
                    // Compute Ke_rt_Nd2 = (Ke_rt * Nd2)
                    temp64 = $signed(Ke_rt) * $signed(Nd2);
                    Ke_rt_Nd2 <= temp64[47:16];
                    state <= 3'b101;
                end
                3'b101: begin
                    // Compute Call Option Price: COptionPrice = spot_Nd1 - Ke_rt_Nd2.
                    COptionPrice <= $signed(spot_Nd1) - $signed(Ke_rt_Nd2);
                    state <= 3'b110;
                end
                3'b110: begin
                    // Compute Put Option Price: POptionPrice = Ke_rt - spot_Nd1.
                    POptionPrice <= $signed(Ke_rt) - $signed(spot_Nd1);
                    if (otype == 1'b0) begin
                        OptionPrice <= COptionPrice;
                    end else begin
                        OptionPrice <= POptionPrice;
                    end
                    state <= 3'b000;
                end
                default: state <= 3'b000;
            endcase
        end
    end
endmodule