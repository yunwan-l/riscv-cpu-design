`timescale 1ns/1ps
module tb_ab;
    logic clk,rst_n; logic[31:0] pc,instr,illegal;
    logic[31:0] da,dbus_w,dbus_r,pc5,pi,ps,pf,pb,ih,im;
    logic dr,dw,du; import rvp_pkg::*; mem_size_e ds;
    rvp_core_pipeline cpu(.clk_i(clk),.rst_ni(rst_n),.pc_o(pc),.instr_o(instr),.illegal_o(illegal),
        .dbus_addr_o(da),.dbus_read_o(dr),.dbus_write_o(dw),.dbus_size_o(ds),.dbus_unsigned_o(du),
        .dbus_wdata_o(dbus_w),.dbus_rdata_i(dbus_r),.perf_cycle_o(pc5),.perf_inst_o(pi),
        .perf_stall_o(ps),.perf_flush_o(pf),.perf_branch_o(pb),.icache_hit_o(ih),.icache_miss_o(im));
    assign dbus_r=0;
    initial begin clk=0; forever #5 clk=~clk; end
    string hp;
    initial begin #1; hp="D:/Course resources for the second semester of sophomore year/riscv-cpu-design/sw/tests/conflict3.hex";
        $readmemh(hp, cpu.icache.bm.mem); end
    integer cyc=0; always@(posedge clk) if(rst_n) cyc<=cyc+1;
    logic[31:0] lpc; integer sc;
    always@(posedge clk) if(rst_n) begin if(pc==lpc) sc<=sc+1; else begin sc<=0; lpc<=pc; end end
    initial begin rst_n=0; #50 rst_n=1; end
    always@(posedge clk) if(sc>200||cyc>80000) begin
        $display("%s: hits=%0d miss=%0d rate=%.2f%%",
            "APGR", ih, im, 100.0*ih/(ih+im+1)); $finish; end
endmodule
