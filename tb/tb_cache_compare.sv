// tb_cache_compare.sv - I-Cache benchmark comparison
`timescale 1ns/1ps
module tb_cache_compare;

    localparam MAX_CYC = 500000;
    string BENCH_NAME;

    logic clk, rst_n, uart_tx;
    logic [15:0] led, sw;
    logic [31:0] pc_dbg;
    logic [31:0] cache_hits, cache_misses;
    integer cyc, stall_c;
    logic [31:0] last_pc;

    rvp_soc dut (.clk_i(clk),.rst_ni(rst_n),.uart_tx_o(uart_tx),
                 .led_o(led),.sw_i(sw),.pc_dbg_o(pc_dbg));
    assign cache_hits   = dut.icache_hit_count;
    assign cache_misses = dut.icache_miss_count;

    initial begin clk=0; forever #5 clk=~clk; end

    initial begin
        sw = 0; #1;
        if (!$value$plusargs("BENCH=%s", BENCH_NAME))
            BENCH_NAME = "bench_nested_loop";
        $readmemh({"D:/Course resources for the second semester of sophomore year/riscv-cpu-design/sw/tests/",BENCH_NAME,".hex"}, dut.cpu.icache.backing_mem.mem);
    end

    always @(posedge clk) begin
        if(rst_n) begin
            cyc <= cyc + 1;
            if(pc_dbg==last_pc) stall_c<=stall_c+1;
            else begin stall_c<=0; last_pc<=pc_dbg; end
        end
    end

    initial begin
        rst_n=0; #50 rst_n=1;
        $display("=== Cache Benchmark: %s ===", BENCH_NAME);
    end

    always @(posedge clk) begin
        if(stall_c>300 || cyc>MAX_CYC) begin
            $display("RESULTS: hits=%0d miss=%0d rate=%.2f%% cyc=%0d",
                cache_hits, cache_misses,
                100.0*cache_hits/(cache_hits+cache_misses+1), cyc);
            #100; $finish;
        end
    end

endmodule
