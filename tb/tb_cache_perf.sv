// tb_cache_perf.sv — I-Cache性能测试
`timescale 1ns/1ps
module tb_cache_perf;
  logic clk, rst_n, uart_tx;
  logic [15:0] led, sw;
  logic [31:0] pc_dbg;

  rvp_soc dut (.clk_i(clk),.rst_ni(rst_n),.uart_tx_o(uart_tx),.led_o(led),.sw_i(sw),.pc_dbg_o(pc_dbg));

  initial begin clk=0; forever #5 clk=~clk; end
  initial begin sw=0; #1;
    $readmemh("D:/Course resources for the second semester of sophomore year/riscv-cpu-design/sw/tests/cache_big.hex", dut.cpu.icache.backing_mem.mem);
  end

  integer cyc=0;
  always @(posedge clk) if(rst_n) cyc<=cyc+1;

  logic [31:0] last_pc; integer stall_c;
  always @(posedge clk) begin
    if(rst_n) begin
      if(pc_dbg==last_pc) stall_c<=stall_c+1; else begin stall_c<=0; last_pc<=pc_dbg; end
    end
  end

  initial begin
    rst_n=0; #50 rst_n=1;
    $display("=== Cache Perf: cache_big (452B > 256B cache) ===");
  end

  always @(posedge clk) begin
    if(stall_c>200||cyc>50000) begin
      $display("Done: %0d cyc  hits=%0d miss=%0d rate=%.1f%%",
               cyc, dut.icache_hit_count, dut.icache_miss_count,
               100.0*dut.icache_hit_count/(dut.icache_hit_count+dut.icache_miss_count+1));
      #100; $finish;
    end
  end
endmodule
