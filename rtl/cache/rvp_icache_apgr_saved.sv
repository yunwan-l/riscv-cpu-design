// rvp_icache_apgr2.sv - 2-way I-Cache + tournament replacement + prefetch
module rvp_icache_apgr2 #(parameter NUM_SETS=32, INDEX_W=5) (
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

    logic[3:0] sw; logic bp;
    always_ff@(posedge clk_i or negedge rst_ni) begin
        if(!rst_ni){sw,bp}<=0; else begin
            sw<={sw[2:0],!ch};
            if(sw[0]+sw[1]+sw[2]+sw[3]>=12) bp<=1; else if(sw[0]+sw[1]+sw[2]+sw[3]<=4) bp<=0;
        end
    end

    logic eh[0:31];
    logic[29:0] pt; logic[31:0] pd; logic pv; logic[1:0] pl;
    logic ph; assign ph=pv&&(addr_i[31:2]==pt);
    assign instr_o=ph?pd:(ha?da[idx]:(hb?db[idx]:bram_instr));

    logic kb;
    always_comb begin
        if(!va[idx]) kb=0; else if(!vb[idx]) kb=1;
        else begin
            if((ra[idx]==0)!=(rb[idx]==0)) kb=(ra[idx]!=0);
            else if(ba[idx]!=bb[idx]) kb=ba[idx];
            else if(la[idx]!=lb[idx]) kb=la[idx];
            else kb=(rb[idx]<ra[idx]);
        end
    end

    always_ff@(posedge clk_i or negedge rst_ni) begin
        if(!rst_ni) for(int i=0;i<32;i++) begin
            va[i]<=0;vb[i]<=0;ra[i]<=0;rb[i]<=0;la[i]<=0;lb[i]<=0;ba[i]<=0;bb[i]<=0;eh[i]<=0;
        end else begin
            if(ha) case(pm) 1:begin ra[idx]<=(ra[idx]>4)?7:ra[idx]+3; la[idx]<=1; end
                            0:ra[idx]<=(ra[idx]==7)?7:ra[idx]+1;
                            2:begin ra[idx]<=(ra[idx]>4)?7:ra[idx]+2; ba[idx]<=1; end
                            3:begin ra[idx]<=3; ba[idx]<=1; end endcase
            if(hb) case(pm) 1:begin rb[idx]<=(rb[idx]>4)?7:rb[idx]+3; lb[idx]<=1; end
                            0:rb[idx]<=(rb[idx]==7)?7:rb[idx]+1;
                            2:begin rb[idx]<=(rb[idx]>4)?7:rb[idx]+2; bb[idx]<=1; end
                            3:begin rb[idx]<=3; bb[idx]<=1; end endcase
            if(!ch&&!bp) begin
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

    logic[7:0] ac; always_ff@(posedge clk_i or negedge rst_ni) if(!rst_ni) ac<=0; else ac<=ac+1;
    wire do_age=(ac==255);
    always_ff@(posedge clk_i) if(do_age) for(int i=0;i<32;i++) begin
        ra[i]<={1'b0,ra[i][2:1]}; rb[i]<={1'b0,rb[i][2:1]}; la[i]<=0; lb[i]<=0;
    end

    wire[31:0] ij={{11{bram_instr[31]}},bram_instr[31],bram_instr[19:12],bram_instr[20],bram_instr[30:21],1'b0};
    logic df; logic[31:0] fa;
    always_comb begin df=1; case(bram_instr[6:0])
        7'b1101111: fa=addr_i+ij; 7'b1100011: fa=addr_i+4; 7'b1100111: df=0; default: fa=addr_i+4; endcase
    end
    always_ff@(posedge clk_i or negedge rst_ni) begin
        if(!rst_ni){pv,pl}<=0; else begin
            if(pv&&pl==0) pv<=0;
            if(!ch&&df) begin pt<=fa[31:2]; pd<=bram_instr; pv<=1; pl<=3; end
            if(ph){pv,pl}<=0; if(pv&&!ph) pl<=pl-1;
        end
    end

    always_ff@(posedge clk_i or negedge rst_ni) begin
        if(!rst_ni){hit_count_o,miss_count_o}<=0;
        else if(ch) hit_count_o<=hit_count_o+1; else miss_count_o<=miss_count_o+1;
    end
endmodule
