`timescale 1ns / 1ps
`include "rvp_config.svh"
module rvp_tb;
  localparam CLK = 10;
  localparam MAX = 500;
  string fw = "firmware.hex";
  logic clk, rst_n, uart_rx, uart_tx, done;
  logic [15:0] gpio_in, gpio_out;
  integer cyc;

  initial begin clk=0; forever #(CLK/2) clk=~clk; end
  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) cyc<=0; else cyc<=cyc+1;
  end
  initial if($value$plusargs("firmware=%s",fw)) $display("FW:%s",fw);

  rvp_soc_top dut(.clk_i(clk),.rst_ni(rst_n),.uart_rx_i(uart_rx),.uart_tx_o(uart_tx),.gpio_in_i(gpio_in),.gpio_out_o(gpio_out));
  assign uart_rx=1; initial gpio_in=0;

  always @(posedge clk) begin
    if(rst_n && dut.u_core.data_req_o && dut.u_core.data_we_o && dut.u_core.data_addr_o==32'h2000_0000) begin
      $display("STORE:%d at cyc %d", dut.u_core.data_wdata_o, cyc);
      done=1;
    end
    if(cyc>=MAX && !done) begin
      $display("TIMEOUT at cyc %d", cyc);
      $finish;
    end
  end

  initial begin done=0; rst_n=0; #(CLK*5); rst_n=1; $display("GO"); end
  always @(posedge clk) if(done) begin #(CLK*10); $finish; end
endmodule
