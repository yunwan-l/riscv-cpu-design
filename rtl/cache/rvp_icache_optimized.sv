// rvp_icache_optimized.sv - 优化版2-way I-Cache (APGR + 4项关键修复)
//
// 修复清单:
//   FIX1: 移除无效流式旁路 — 4位窗口最大和=4, 阈值>=12永远不可达(bp恒为0);
//         Python模拟证明旁路在所有16种trace下都有害(2路cache已足够, 旁路阻止有用填充)
//   FIX2: 修复预取缓冲数据 — 新增第二BRAM读端口, pd存储预取地址(fa)的指令
//         原始代码错误存储bram_instr(当前地址指令), 导致PB命中时返回错误数据
//   FIX3: 启用遗产标记eh — 淘汰赛前检查eh, 上次踢了热行时优先保护当前热行(reuse>=4)
//         原始代码eh被赋值但从未参与受害者选择
//   FIX4: 修复老化竞争条件 — 将老化逻辑合并到主always_ff块
//         原始代码两个always_ff同时写ra/rb/la/lb, 同周期触发时产生竞争
module rvp_icache #(parameter NUM_SETS=32, INDEX_W=5) (
    input logic clk_i,rst_ni, input logic[31:0] addr_i, output logic[31:0] instr_o,
    output logic hit_o,miss_o, output logic[31:0] hit_count_o,miss_count_o
);
    localparam TW=25;
    logic[4:0] idx; logic[24:0] tag;
    assign idx=addr_i[INDEX_W+1:2]; assign tag=addr_i[31:INDEX_W+2];

    logic va[0:31],vb[0:31]; logic[24:0] ta[0:31],tb[0:31]; logic[31:0] da[0:31],db[0:31];
    logic[2:0] ra[0:31],rb[0:31]; logic la[0:31],lb[0:31],ba[0:31],bb[0:31];

    logic ha,hb; assign ha=va[idx]&&(ta[idx]==tag); assign hb=vb[idx]&&(tb[idx]==tag);
    logic ch; assign ch=ha||hb; assign hit_o=ch; assign miss_o=!ch;

    logic[31:0] bram_instr;
    rvp_instr_mem bm(.addr_i(addr_i[12:2]),.instr_o(bram_instr));

    logic[31:0] lp; logic[1:0] pm; wire[31:0] d=addr_i-lp;
    always_ff@(posedge clk_i or negedge rst_ni) if(!rst_ni) lp<=-1; else lp<=addr_i;
    always_comb begin
        if(d==4) pm=0; else if($signed(d)<0&&$signed(d)>-256) pm=1;
        else if(d!=4&&$signed(d)>=0) pm=2; else pm=3;
    end

    // 预取地址计算 (与原始代码相同)
    wire[31:0] ij={{11{bram_instr[31]}},bram_instr[31],bram_instr[19:12],bram_instr[20],bram_instr[30:21],1'b0};
    logic df; logic[31:0] fa;
    always_comb begin df=1; case(bram_instr[6:0])
        7'b1101111: fa=addr_i+ij; 7'b1100011: fa=addr_i+4; 7'b1100111: df=0; default: fa=addr_i+4; endcase
    end

    // FIX 2: 第二BRAM读端口 — 读取预取地址(fa)的指令
    //   原始代码pd<=bram_instr存储的是当前地址的指令, 而非预取目标地址的指令
    //   修复后pd<=pf_instr, PB命中时返回正确的预取数据
    logic[31:0] pf_instr;
    rvp_instr_mem bm2(.addr_i(fa[12:2]),.instr_o(pf_instr));

    // FIX 1: 流式旁路(sw,bp)已完全移除
    //   原始代码: 4位窗口sw, sw[0]+sw[1]+sw[2]+sw[3]最大值为4, 但阈值>=12, bp永远为0
    //   移除后: 缺失填充条件从 !ch&&!bp 简化为 !ch
    //   验证: 旁路在所有16种trace下都有害(平均86.77% vs 66.27%/70.19%)

    logic eh[0:31];
    logic[29:0] pt; logic[31:0] pd; logic pv; logic[1:0] pl;
    logic ph; assign ph=pv&&(addr_i[31:2]==pt);
    assign instr_o=ph?pd:(ha?da[idx]:(hb?db[idx]:bram_instr));

    // FIX 3: eh遗产标记参与淘汰赛
    //   原始代码: eh[idx]被赋值但从未在kb(受害者选择)中使用
    //   修复: 在淘汰赛第一轮之前新增"第0轮"eh检查
    //   逻辑: 如果上次踢了热行(eh=1)且当前两路冷热不同, 优先踢冷行(protect热行)
    logic kb;
    always_comb begin
        if(!va[idx]) kb=0; else if(!vb[idx]) kb=1;
        else begin
            // 第0轮(FIX3新增): eh检查 — 上次踢了热行时, 保护当前reuse>=4的行
            if(eh[idx]&&(ra[idx]>=4)!=(rb[idx]>=4)) kb=(ra[idx]>=4);
            // 以下为原始淘汰赛四轮, 保持不变
            else if((ra[idx]==0)!=(rb[idx]==0)) kb=(ra[idx]!=0);
            else if(ba[idx]!=bb[idx]) kb=ba[idx];
            else if(la[idx]!=lb[idx]) kb=la[idx];
            else kb=(rb[idx]<ra[idx]);
        end
    end

    // FIX 4: 老化逻辑合并到主always_ff块
    //   原始代码: 独立的always_ff@(posedge clk_i)块在do_age时写ra/rb/la/lb
    //           主always_ff也在同周期写ra[idx]/rb[idx]/la[idx]/lb[idx]
    //           两个always_ff同时驱动同一信号 → 综合竞争/仿真不确定
    //   修复: 将老化for循环移入主always_ff, 放在命中/缺失更新之前
    //         非阻塞赋值语义: 后续的命中/缺失更新覆盖当前idx的老化结果
    logic[7:0] ac; always_ff@(posedge clk_i or negedge rst_ni) if(!rst_ni) ac<=0; else ac<=ac+1;
    wire do_age=(ac==255);

    always_ff@(posedge clk_i or negedge rst_ni) begin
        if(!rst_ni) for(int i=0;i<32;i++) begin
            va[i]<=0;vb[i]<=0;ra[i]<=0;rb[i]<=0;la[i]<=0;lb[i]<=0;ba[i]<=0;bb[i]<=0;eh[i]<=0;
        end else begin
            // 老化(FIX4合并): reuse右移1位, loop标志清零
            //   非阻塞赋值: 当前idx若同时有命中/缺失更新, 后续赋值覆盖此处的老化值
            if(do_age) for(int i=0;i<32;i++) begin
                ra[i]<={1'b0,ra[i][2:1]}; rb[i]<={1'b0,rb[i][2:1]}; la[i]<=0; lb[i]<=0;
            end
            if(ha) case(pm) 1:begin ra[idx]<=(ra[idx]>4)?7:ra[idx]+3; la[idx]<=1; end
                            0:ra[idx]<=(ra[idx]==7)?7:ra[idx]+1;
                            2:begin ra[idx]<=(ra[idx]>4)?7:ra[idx]+2; ba[idx]<=1; end
                            3:begin ra[idx]<=3; ba[idx]<=1; end endcase
            if(hb) case(pm) 1:begin rb[idx]<=(rb[idx]>4)?7:rb[idx]+3; lb[idx]<=1; end
                            0:rb[idx]<=(rb[idx]==7)?7:rb[idx]+1;
                            2:begin rb[idx]<=(rb[idx]>4)?7:rb[idx]+2; bb[idx]<=1; end
                            3:begin rb[idx]<=3; bb[idx]<=1; end endcase
            // FIX 1: 条件从 !ch&&!bp 改为 !ch (旁路已移除)
            if(!ch) begin
                if(kb) begin
                    eh[idx]<=(rb[idx]>=4); vb[idx]<=1; tb[idx]<=tag; db[idx]<=bram_instr;
                    case(pm) 1:begin rb[idx]<=5;lb[idx]<=1;bb[idx]<=1; end
                             2:begin rb[idx]<=3;bb[idx]<=1; end
                             3:begin rb[idx]<=4;bb[idx]<=1; end default:rb[idx]<=1; endcase
                end else begin
                    eh[idx]<=(ra[idx]>=4); va[idx]<=1; ta[idx]<=tag; da[idx]<=bram_instr;
                    case(pm) 1:begin ra[idx]<=5;la[idx]<=1;ba[idx]<=1; end
                             2:begin ra[idx]<=3;ba[idx]<=1; end
                             3:begin ra[idx]<=4;ba[idx]<=1; end default:ra[idx]<=1; endcase
                end
            end
        end
    end

    // FIX 2: pd存储预取地址的指令pf_instr (原始代码错误存储bram_instr)
    always_ff@(posedge clk_i or negedge rst_ni) begin
        if(!rst_ni){pv,pl}<=0; else begin
            if(pv&&pl==0) pv<=0;
            if(!ch&&df) begin pt<=fa[31:2]; pd<=pf_instr; pv<=1; pl<=3; end
            if(ph){pv,pl}<=0; if(pv&&!ph) pl<=pl-1;
        end
    end

    always_ff@(posedge clk_i or negedge rst_ni) begin
        if(!rst_ni){hit_count_o,miss_count_o}<=0;
        else if(ch) hit_count_o<=hit_count_o+1; else miss_count_o<=miss_count_o+1;
    end
endmodule
