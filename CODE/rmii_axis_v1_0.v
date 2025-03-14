`timescale 1 ns / 1 ps

module rmii_axis_v1_0 #
  (
   parameter [7:0] FPGA_IP_1 = 172,
   parameter [7:0] FPGA_IP_2 = 25,
   parameter [7:0] FPGA_IP_3 = 55,
   parameter [7:0] FPGA_IP_4 = 222,
   parameter [7:0] HOST_IP_1 = 172,
   parameter [7:0] HOST_IP_2 = 25,
   parameter [7:0] HOST_IP_3 = 55,
   parameter [7:0] HOST_IP_4 = 221,
   parameter [15:0] FPGA_PORT = 17767,
   parameter [15:0] HOST_PORT = 17767,
   parameter [15:0] HEADER_CHECKSUM = 16'h65b3,
   parameter [47:0] FPGA_MAC = 48'h021A4B000002,
   parameter [47:0] HOST_MAC = 48'hF8E43B04106E,
   parameter CHECK_DESTINATION = 1
  )
   (
    output		ETH_MDC,
    inout		ETH_MDIO,
    input		ETH_CRSDV,
    input [1:0]		ETH_RXD,
    output		ETH_TXEN,
    input		ETH_RXERR,
    output [1:0]	ETH_TXD,
   
    input wire		m00_axis_aclk,
    input wire		m00_axis_aresetn,
    output wire		m00_axis_tvalid,
    output wire [7:0]	m00_axis_tdata,
    output wire		m00_axis_tlast,
    input wire		m00_axis_tready,
     // Ports of Axi Slave Bus Interface S00_AXIS
    input wire		s00_axis_aclk,
    input wire		s00_axis_aresetn,
    
    output wire		s00_axis_tready,
    input wire [7 : 0]	s00_axis_tdata,
    input wire		s00_axis_tlast,
    input wire [11:0]	s00_axis_tuser,
    input wire		s00_axis_tvalid,
    output wire [63:0] ila_preamble_sfd // Added for ILA monitoring
   );
    parameter WORD_BYTES = 1;
   wire [63:0] preamble_sfd_wire;
    packet_gen
     #(
       .WORD_BYTES(WORD_BYTES),
       .FPGA_MAC(FPGA_MAC),   
       .HOST_MAC(HOST_MAC),
       .FPGA_IP({FPGA_IP_1, FPGA_IP_2, FPGA_IP_3, FPGA_IP_4}),
       .HOST_IP({HOST_IP_1, HOST_IP_2, HOST_IP_3, HOST_IP_4}),
       .FPGA_PORT(FPGA_PORT),
       .HOST_PORT(HOST_PORT),
       .HEADER_CHECKSUM(HEADER_CHECKSUM)
       )
   packet_gen_i
     (
      .CLK(s00_axis_aclk),
      .RST(~s00_axis_aresetn),
      .S_AXIS_TDATA(s00_axis_tdata),
      .S_AXIS_TVALID(s00_axis_tvalid),
      .S_AXIS_TLAST(s00_axis_tlast),
      .S_AXIS_TREADY(s00_axis_tready),
      .S_AXIS_TUSER(s00_axis_tuser),
      .TX_EN(ETH_TXEN),
      .TXD(ETH_TXD)
      );
   packet_recv
     #(
       .FPGA_MAC(FPGA_MAC),   
       .HOST_MAC(HOST_MAC),
       .FPGA_IP({FPGA_IP_1, FPGA_IP_2, FPGA_IP_3, FPGA_IP_4}),
       .HOST_IP({HOST_IP_1, HOST_IP_2, HOST_IP_3, HOST_IP_4}),
       .FPGA_PORT(FPGA_PORT),
       .HOST_PORT(HOST_PORT),
       .CHECK_DESTINATION(CHECK_DESTINATION)
       )
   packet_recv_i
     (
      .clk(m00_axis_aclk),
      .rst(~m00_axis_aresetn),
      .M_AXIS_TDATA(m00_axis_tdata),
      .M_AXIS_TVALID(m00_axis_tvalid),
      .M_AXIS_TLAST(m00_axis_tlast),
      .RXDV(ETH_CRSDV),
      .RXD(ETH_RXD),
      .preamble_sfd_out(preamble_sfd_wire)
      );

   assign ila_preamble_sfd = preamble_sfd_wire;
   

endmodule
