`timescale 1ns / 1ps

module packet_gen
  #(
    parameter [31:0] FPGA_IP  = 32'hC0A80164,
    parameter [31:0] HOST_IP  = 32'hC0A80165,
    parameter [15:0] FPGA_PORT= 16'h4567,
    parameter [15:0] HOST_PORT= 16'h4567,
    parameter [47:0] FPGA_MAC = 48'he86a64e7e830,
    parameter [47:0] HOST_MAC = 48'he86a64e7e829,
    parameter [15:0] HEADER_CHECKSUM=16'h65ba,
    parameter        MII_WIDTH=2
    // For 8-bit data we no longer need WORD_BYTES in this example
  )
  (
    input  wire             CLK,
    input  wire             RST,

    // AXIS input
    input  wire [7:0]       S_AXIS_TDATA,
    input  wire             S_AXIS_TVALID,
    input  wire             S_AXIS_TLAST,
    input  wire [11:0]      S_AXIS_TUSER, // packet length in bytes?
    output wire             S_AXIS_TREADY,

    // RMII-like output
    output reg              TX_EN,
    output reg [MII_WIDTH-1:0] TXD
  );

  // Packet constants
  localparam HEADER_BYTES   = 34; 
  localparam PREAMBLE_BYTES = 7;
  localparam SFD_BYTES      = 1;
  localparam FCS_BYTES      = 4;

  localparam PREAMBLE_LENGTH = PREAMBLE_BYTES * 8 / MII_WIDTH;
  localparam SFD_LENGTH      = SFD_BYTES      * 8 / MII_WIDTH;
  localparam HEADER_LENGTH   = HEADER_BYTES   * 8 / MII_WIDTH;
  localparam FCS_LENGTH      = FCS_BYTES      * 8 / MII_WIDTH;

  // States
  typedef enum logic [2:0] {
    IDLE,
    PREAMBLE,
    SFD,
    HEADER,
    DATA,
    FCS,
    WAIT
  } state_type;

  state_type current_state, next_state;

  // Some registers
  reg [31:0] state_counter;
  reg [56:0] preamble_buffer;
  reg [7:0]  sfd_buffer;
  reg [(HEADER_BYTES*8)-1:0] header_buffer;
  reg [31:0] crc_reg;

  //===============================
  // ADDED for real FIFO:
  //===============================
  wire [7:0] fifo_dout;
  wire       fifo_full;
  wire       fifo_empty;
  wire [11:0] fifo_data_count; // you said "Data Count Outputs" => 12 bits

  // Write enable: when the master is valid & we are ready
  wire wr_en = S_AXIS_TVALID && (S_AXIS_TREADY);

  // We'll say S_AXIS_TREADY = !fifo_full (or you can do advanced logic).
  // This means "we can accept data if FIFO not full."
  assign S_AXIS_TREADY = ~fifo_full;

  // Read enable will be asserted by the state machine in the DATA state
  reg rd_en;

  // The actual data_fifo IP instance
  data_fifo data_fifo_i (
    .clk   (CLK),
    .srst  (RST),
    .din   (S_AXIS_TDATA),
    .wr_en (wr_en),
    .rd_en (rd_en),
    .dout  (fifo_dout),
    .full  (fifo_full),
    .empty (fifo_empty),
    .data_count (fifo_data_count)
  );

  //===============================
  // CRC generator
  //===============================
  wire [31:0] crc_wire;
  crc_gen crc_gen_inst (
    .clk    (CLK),
    .rst    (RST),
    .data_in(TXD),  // nibble or bits
    .crc_en ((current_state==DATA)||(current_state==HEADER)),
    .crc_out(crc_wire)
  );

  //===============================
  // Header generator
  //===============================
  wire [(HEADER_BYTES*8)-1:0] header_output;
  eth_header_gen #(
    .FPGA_MAC(FPGA_MAC),
    .HOST_MAC(HOST_MAC),
    .FPGA_IP (FPGA_IP),
    .HOST_IP (HOST_IP),
    .FPGA_PORT(FPGA_PORT),
    .HOST_PORT(HOST_PORT),
    .HEADER_CHECKSUM(HEADER_CHECKSUM)
  ) header_gen_inst (
    .payload_bytes(S_AXIS_TUSER),  // e.g. number of bytes
    .output_header(header_output)
  );

  //===============================
  // State Machine
  //===============================
  always @(posedge CLK or posedge RST) begin
    if (RST) begin
      current_state   <= IDLE;
      next_state      <= IDLE;
      state_counter   <= 0;
      TX_EN           <= 0;
      TXD             <= 0;
      crc_reg         <= 0;
      preamble_buffer <= 56'h5555_5555_5555_55;
      sfd_buffer      <= 8'hD5;
      header_buffer   <= 0;
      rd_en           <= 0;
    end
    else begin
      current_state <= next_state;

      case (current_state)

        //====================================================
        IDLE: begin
          TX_EN         <= 0;
          rd_en         <= 0;
          state_counter <= 0;
          // Wait until the FIFO has enough data to cover the entire packet:
          // If you want partial packets, you can remove this check or do
          // if (!fifo_empty) ...
          if (fifo_data_count >= S_AXIS_TUSER) begin
            header_buffer   <= header_output;
            preamble_buffer <= 56'h5555_5555_5555_55;
            sfd_buffer      <= 8'hD5;
            next_state      <= PREAMBLE;
          end
        end

        //====================================================
        PREAMBLE: begin
          TX_EN <= 1;
          TXD   <= preamble_buffer[MII_WIDTH-1 : 0];
          preamble_buffer <= preamble_buffer >> MII_WIDTH;

          if (state_counter == (PREAMBLE_LENGTH - 1)) begin
            state_counter <= 0;
            next_state    <= SFD;
          end else begin
            state_counter <= state_counter + 1;
          end
        end

        //====================================================
        SFD: begin
          TX_EN <= 1;
          TXD   <= sfd_buffer[MII_WIDTH-1:0];
          sfd_buffer <= sfd_buffer >> MII_WIDTH;

          if (state_counter == (SFD_LENGTH - 1)) begin
            state_counter <= 0;
            next_state    <= HEADER;
          end else begin
            state_counter <= state_counter + 1;
          end
        end

        //====================================================
        HEADER: begin
          TX_EN <= 1;
          TXD   <= header_buffer[MII_WIDTH-1:0];
          header_buffer <= header_buffer >> MII_WIDTH;

          if (state_counter == (HEADER_LENGTH - 1)) begin
            state_counter <= 0;
            crc_reg       <= crc_wire; 
            next_state    <= DATA;
          end else begin
            state_counter <= state_counter + 1;
          end
        end

        //====================================================
        DATA: begin
          TX_EN <= 1;
          // If FIFO is not empty, read next nibble
          // We'll do a nibble-based approach. Typically you handle a full byte per 4 nibbles if MII_WIDTH=2
          // We'll read a new byte from the FIFO whenever we've used up the old one.
          // For simplicity: read the next byte at the *start* of each new byte cycle:

          // On the first nibble of a new byte:
          if (state_counter[1:0] == 2'b00) begin
            // If empty, we won't have data. But let's assume we have enough
            rd_en <= 1;
          end else begin
            rd_en <= 0;
          end

          // Actually drive TXD with the "current byte's nibble"
          TXD <= fifo_dout[MII_WIDTH-1:0];

          // If we've shifted out all nibbles of TUSER bytes, go to FCS
          // TUSER * 8 bits => TUSER * (8 / MII_WIDTH) nibbles
          if (state_counter == ((S_AXIS_TUSER * (8/MII_WIDTH)) - 1)) begin
            state_counter <= 0;
            crc_reg       <= crc_wire;
            next_state    <= FCS;
          end else begin
            // shift the fifo_dout bits? Typically you'd do a register
            state_counter <= state_counter + 1;
          end
        end

        //====================================================
        FCS: begin
          TX_EN <= 1;
          // shift out the CRC nibble by nibble
          TXD   <= crc_reg[MII_WIDTH-1:0];
          crc_reg <= crc_reg >> MII_WIDTH;

          if (state_counter == (FCS_LENGTH - 1)) begin
            state_counter <= 0;
            next_state    <= WAIT;
          end else begin
            state_counter <= state_counter + 1;
          end
        end

        //====================================================
        WAIT: begin
          // Possibly wait inter-frame gap
          // then go IDLE
          next_state <= IDLE;
        end

      endcase
    end
  end // always @(posedge CLK)

endmodule
