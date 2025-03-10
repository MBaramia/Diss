`timescale 1ns / 1ps

module top #(
    parameter WIDTH = 32
)(
    input clk,
    input reset,
    input start,
    input signed [WIDTH-1:0] S0,    // Spot price (Q16.16)
    input signed [WIDTH-1:0] K,     // Strike price (Q16.16)
    input signed [WIDTH-1:0] T,     // Time to maturity (Q16.16)
    input signed [WIDTH-1:0] sigma, // Volatility (Q16.16)
    input signed [WIDTH-1:0] r,     // Risk-free rate (Q16.16)
    input otype,                    // Option type: 0=call, 1=put
    output reg signed [WIDTH-1:0] OptionPrice, // Result (Q16.16)
    output reg done                 // Done signal
);

    // Internal wires connecting the modules
    wire signed [WIDTH-1:0] d1, d2;
    wire signed [WIDTH-1:0] Nd1, Nd2;
    wire norm_done, norm_start;
    wire pipeline_done;
    wire exp_start, exp_done;
    wire signed [WIDTH-1:0] option_price_result; // Wire to connect to OptionPrice output
    
    // Pipeline stage registers for improved timing
    reg signed [WIDTH-1:0] r_reg, T_reg, S0_reg, K_reg;
    reg signed [WIDTH-1:0] Nd1_reg, Nd2_reg;
    reg otype_reg;
    
    // Top-level state machine
    reg [2:0] state;  // MODIFIED: Expanded to 3 bits to add an additional state
    
    // Register to track when option_price_result is valid
    reg option_price_valid;  // ADDED: Flag to track when result is valid
    reg option_price_ready;  // ADDED: Flag to wait additional cycles if needed
    
    // Input registration for improved timing
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            r_reg <= 0;
            T_reg <= 0;
            S0_reg <= 0;
            K_reg <= 0;
            otype_reg <= 0;
        end else if (start) begin
            r_reg <= r;
            T_reg <= T;
            S0_reg <= S0;
            K_reg <= K;
            otype_reg <= otype;
        end
    end
    
    // Norm output registration for improved timing
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            Nd1_reg <= 0;
            Nd2_reg <= 0;
        end else if (norm_done) begin
            Nd1_reg <= Nd1;
            Nd2_reg <= Nd2;
        end
    end
    
    // FIXED: Track when option_price_result becomes valid
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            option_price_valid <= 0;
            option_price_ready <= 0;
        end else if (option_price_result != 0) begin
            option_price_valid <= 1;
            option_price_ready <= option_price_valid; // Wait one more cycle
        end
    end
    
    // FIXED: Separate always block specifically for updating OptionPrice
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            OptionPrice <= 0;
        end else if (option_price_valid) begin
            // Only update when result is valid, not just when exp_done
            OptionPrice <= option_price_result;
        end
    end

    // Instantiate d1d2 module
    d1d2 #(.WIDTH(WIDTH)) d1d2_inst (
        .clk(clk),
        .reset(reset),
        .start(start),
        .S0(S0),
        .K(K),
        .T(T),
        .sigma(sigma),
        .r(r),
        .d1(d1),
        .d2(d2),
        .div_valid_out(),
        .sqrt_valid_out(),
        .log_valid_out(),
        .pipeline_done(pipeline_done),
        .norm_start(norm_start)
    );
    
    // Instantiate norm module
    norm #(.WIDTH(WIDTH)) norm_inst (
        .clk(clk),
        .reset(reset),
        .start(norm_start),
        .d1(d1),
        .d2(d2),
        .Nd1(Nd1),
        .Nd2(Nd2),
        .done(norm_done)
    );
    
    // Instantiate OptionPrice module with corrected connection
    OptionPrice #(.WIDTH(WIDTH)) option_price_inst (
        .clk(clk),
        .reset(reset),
        .rate(r_reg),
        .timetm(T_reg),
        .spot(S0_reg),
        .strike(K_reg),
        .Nd1(Nd1_reg),
        .Nd2(Nd2_reg),
        .otype(otype_reg),
        .norm_done(norm_done),
        .OptionPrice(option_price_result), // Connect to internal wire, not directly to output
        .exp_start(exp_start),
        .exp_done(exp_done)
    );
    
    // FIXED: Modified top-level state machine to track actual completion
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= 3'b000;
            done <= 0;
        end else begin
            case (state)
                3'b000: begin
                    // Waiting for start
                    done <= 0;
                    if (start) begin
                        state <= 3'b001;
                    end
                end
                
                3'b001: begin
                    // Waiting for norm_done
                    if (norm_done) begin
                        state <= 3'b010;
                    end
                end
                
                3'b010: begin
                    // Waiting for exp_start
                    if (exp_start) begin
                        state <= 3'b011;
                    end
                end
                
                3'b011: begin
                    // Waiting for exp_done
                    if (exp_done) begin
                        state <= 3'b100; // NEW STATE: Wait for result to be valid
                    end
                end
                
                3'b100: begin
                    // ADDED: Wait for result to be actually valid
                    if (option_price_valid && option_price_ready) begin
                        done <= 1;
                        state <= 3'b000;
                    end
                end
            endcase
        end
    end

endmodule