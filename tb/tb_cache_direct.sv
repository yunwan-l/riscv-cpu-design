// tb_cache_direct.sv - 直接测缓存, 用toggle_sim程序
`timescale 1ns/1ps
module tb_cache_direct;

    logic clk, rst_n;
    logic [31:0] pc, instr, illegal;
    logic [31:0] dbus_addr, dbus_wdata, dbus_rdata, perf_cycle, perf_inst, perf_stall, perf_flush, perf_branch;
    logic dbus_read, dbus_write, dbus_unsigned;
    logic [31:0] icache_hit, icache_miss;
    import rvp_pkg::*;
    mem_size_e dbus_size;

    rvp_core_pipeline cpu (.clk_i(clk),.rst_ni(rst_n),.pc_o(pc),.instr_o(instr),.illegal_o(illegal),
        .dbus_addr_o(dbus_addr),.dbus_read_o(dbus_read),.dbus_write_o(dbus_write),
        .dbus_size_o(dbus_size),.dbus_unsigned_o(dbus_unsigned),
        .dbus_wdata_o(dbus_wdata),.dbus_rdata_i(dbus_rdata),
        .perf_cycle_o(perf_cycle),.perf_inst_o(perf_inst),
        .perf_stall_o(perf_stall),.perf_flush_o(perf_flush),.perf_branch_o(perf_branch),
        .icache_hit_o(icache_hit),.icache_miss_o(icache_miss));
    assign dbus_rdata = 0;

    initial begin clk=0; forever #5 clk=~clk; end

    initial begin #1;
        $readmemh("D:/Course resources for the second semester of sophomore year/riscv-cpu-design/sw/tests/toggle_sim.hex", cpu.icache.backing_mem.mem);
    end

    integer cyc=0;
    always @(posedge clk) if(rst_n) cyc<=cyc+1;

    initial begin
        rst_n=0; #50 rst_n=1; $display("=== toggle_sim cache test ===");
    end

    logic [31:0] lpc; integer sc;
    always @(posedge clk) begin
        if(rst_n) begin
            if(pc==lpc) sc<=sc+1; else begin sc<=0; lpc<=pc; end
        end
    end

    // 收集缓存统计 (icache在pipeline内部)
    always @(posedge clk) begin
        if(sc>100 || cyc>100000) begin
            $display("DONE: cyc=%0d PC=%h", cyc, pc);
            $display("I-Cache: hits=%0d miss=%0d rate=%.1f%%",
                icache_hit, icache_miss,
                100.0*icache_hit/(icache_hit+icache_miss+1));
            #100; $finish;
        end
    end

endmodule
