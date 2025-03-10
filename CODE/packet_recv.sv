`timescale 1ns / 1ps

module packet_recv
  #(
    // Example parameters
    parameter [47:0] FPGA_MAC = 48'h021A4B000002,
    parameter [47:0] HOST_MAC = 48'hF8E43B04106E,
    parameter [31:0] FPGA_IP  = {8'd172, 8'd25, 8'd55, 8'd222},
    parameter [31:0] HOST_IP  = {8'd172, 8'd25, 8'd55, 8'd221},
    parameter [15:0] FPGA_PORT= 16'd17767,
    parameter [15:0] HOST_PORT= 16'd17767,
    parameter CHECK_DESTINATION= 1
  )
  (
    // Clk/Reset
    input  wire       clk,
    input  wire       rst,

    // RMII nibble input
    input  wire [1:0] RXD,
    input  wire       RXDV,

    // AXIS output
    output reg        M_AXIS_TVALID,
    output reg [7:0]  M_AXIS_TDATA,
    output reg        M_AXIS_TLAST,

    // Debug
    output wire [63:0] preamble_sfd_out
  );

  //-------------------------------------------------------------------------
  // States
  typedef enum logic [1:0] {
    IDLE         = 2'b00,
    PREAMBLE_SFD = 2'b01,
    HEADER       = 2'b10,
    DATA         = 2'b11
  } state_type;

  state_type current_state, next_state;

  //-------------------------------------------------------------------------
  // Internal signals
  reg [31:0] state_counter;
  reg [63:0] preamble_sfd_buffer;
  reg [7:0]  data_buffer;

  // Track how many nibbles we have captured
  reg [4:0]  nibble_count; // up to 16 for preamble_sfd

  // Single-stage pipeline for RMII
  reg [1:0] rxd_reg;
  reg       rxdv_reg;

  // Standard Ethernet preamble: 7×0x55 + SFD=0xD5
  // => 0x55555555555555D5 in hex
  localparam [63:0] EXPECTED_PREAMBLE_SFD = 64'h55555555555555D5;

  assign preamble_sfd_out = preamble_sfd_buffer;

  //-------------------------------------------------------------------------
  // 1) Capture RMII in a 1-stage pipeline
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      rxd_reg  <= 2'b00;
      rxdv_reg <= 1'b0;
    end
    else begin
      rxd_reg  <= RXD;
      rxdv_reg <= RXDV;
    end
  end

  //-------------------------------------------------------------------------
  // 2) Main State Machine
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      current_state       <= IDLE;
      next_state          <= IDLE;
      state_counter       <= 0;
      nibble_count        <= 0;
      preamble_sfd_buffer <= 64'b0;

      data_buffer         <= 8'b0;
      M_AXIS_TVALID       <= 0;
      M_AXIS_TDATA        <= 8'b0;
      M_AXIS_TLAST        <= 0;

      $display("Time %0t: Reset asserted. Module init.", $time);
    end
    else begin
      current_state <= next_state;

      case (current_state)

        //=====================================================================
        IDLE: begin
          // Clear signals
          state_counter       <= 0;
          nibble_count        <= 0;
          preamble_sfd_buffer <= 64'b0;
          data_buffer         <= 8'b0;
          M_AXIS_TVALID       <= 0;
          M_AXIS_TLAST        <= 0;

          if (RXDV) begin
            // If we see data, go capture preamble
            next_state <= PREAMBLE_SFD;
            $display("Time %0t: IDLE->PREAMBLE_SFD", $time);
          end
          else begin
            next_state <= IDLE;
          end
        end

        //=====================================================================
        PREAMBLE_SFD: begin
          // SHIFT each nibble from rxd_reg if rxdv_reg is still high
          if (!rxdv_reg) begin
            // If the signal dropped too soon, go back IDLE
            next_state <= IDLE;
          end
          else begin
            // Insert the new nibble into the LOW bits of the shift
            // or the high bits, depending on your nibble ordering.
            // We'll do a left shift: Old data moves up, new nibble goes to bottom.
            preamble_sfd_buffer <= {preamble_sfd_buffer[61:0], rxd_reg};

            nibble_count <= nibble_count + 1;
            // Once we've captured 16 nibbles => we have 8 bytes
            if (nibble_count == 15) begin
              // We just inserted nibble #16 => check buffer
              if ( {preamble_sfd_buffer[61:0], rxd_reg} == EXPECTED_PREAMBLE_SFD ) begin
                $display("Time %0t: Found correct preamble SFD => HEADER", $time);
                next_state    <= HEADER;
                state_counter <= 0;
              end
              else begin
                $display("Time %0t: Wrong preamble => IDLE", $time);
                next_state <= IDLE;
              end
            end
          end
        end

        //=====================================================================
        HEADER: begin
          // Example: read 14 bytes or 12 cycles, etc.
          // Let's say we read 12 cycles for a minimal test
          state_counter <= state_counter + 1;
          $display("Time %0t: HEADER, state_counter=%d", $time, state_counter);

          if (state_counter == 12) begin
            next_state    <= DATA;
            state_counter <= 0;
            nibble_count  <= 0;
            data_buffer   <= 8'h00;
            $display("Time %0t: -> DATA", $time);
          end
        end

        //=====================================================================
        DATA: begin
          // If rxdv_reg dropped => end of frame
          if (!rxdv_reg) begin
            M_AXIS_TLAST <= 1;
            next_state    <= IDLE;
            $display("Time %0t: End of frame => IDLE", $time);
          end
          else begin
            // Gather nibble by nibble
            case (nibble_count)
              2'b00: data_buffer[1:0] <= rxd_reg;
              2'b01: data_buffer[3:2] <= rxd_reg;
              2'b10: data_buffer[5:4] <= rxd_reg;
              2'b11: begin
                data_buffer[7:6] <= rxd_reg;
                // Now we have a complete byte
                M_AXIS_TDATA  <= data_buffer;
                M_AXIS_TVALID <= 1;

                $display("Time %0t: Byte=0x%02h", $time, data_buffer);

                // Clear for next
                data_buffer <= 8'h00;
              end
            endcase

            // Bump nibble count
            if (nibble_count == 2'b11)
              nibble_count <= 0;
            else
              nibble_count <= nibble_count + 1;
          end
        end

      endcase
    end
  end

endmodule
