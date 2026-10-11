// Self-test of odve_rand_pkg: every API and the calling contexts where
// simulators have been seen to differ. It writes "<key> <value>" lines to
// rand_out.txt; odve_rand_ref.py computes the same lines from the Annex N
// algorithm, so each simulator is checked against one reference (and so
// against each other). Run by run_test.sh.
`timescale 1ns / 1ps

package odve_rand_tb_pkg;
    import odve_rand_pkg::*;

    int fd;

    function automatic int unsigned fold(int unsigned h, longint unsigned v);
        h = odve_rand_mix(h ^ 32'(v)) + 32'h9E37_79B9;
        return odve_rand_mix(h ^ 32'(v >> 32)) + 32'h9E37_79B9;
    endfunction

    function automatic void put(string key, longint unsigned v);
        $fdisplay(fd, "%s %0d", key, v);
    endfunction

    // a draw from a package function
    function automatic int unsigned pkg_draw(odve_rand r);
        return r.urange(1000);
    endfunction

    // A thread of its own: a stream per object, random delays and clock
    // edges between draws (values must not depend on the timing).
    class worker;
        int          id;
        odve_rand    r;
        int unsigned h;
        virtual odve_rand_clk_if vif;

        function new(int i, virtual odve_rand_clk_if v);
            id  = i;
            vif = v;
            r   = new($sformatf("worker%0d", i));
        endfunction

        task run_it();
            fork
                begin
                    for (int k = 0; k < 400; k++) begin
                        int unsigned v, c;
                        v = r.urange(99);
                        c = r.urange(4);
                        h = fold(h, v);
                        case (c)
                            0: #(r.urange(5, 1) * 10ns + 1ps);
                            1: @(posedge vif.clk);
                            2: @(negedge vif.clk);
                            3: #0;
                            default: #(10ns + 1ps);
                        endcase
                    end
                end
                #1ms;
            join_any
            disable fork;
            put($sformatf("worker %0d", id), h);
        endtask
    endclass
endpackage

interface odve_rand_clk_if(input logic clk);
endinterface

// draws in an always block of a sub-module, one per clock for 100 clocks
module odve_rand_tb_sub(input logic clk, output int unsigned h, output int unsigned n);
    import odve_rand_pkg::*;
    odve_rand    r;
    int unsigned hh = 0, nn = 0;
    initial r = new("sub");
    always @(posedge clk) begin
        if (nn < 100) begin
            hh <= odve_rand_tb_pkg::fold(hh, r.u16());
            nn <= nn + 1;
        end
    end
    assign h = hh;
    assign n = nn;
endmodule

module odve_rand_tb;
    import odve_rand_pkg::*;
    import odve_rand_tb_pkg::*;

    logic clk = 0;
    always #5 clk = ~clk;
    odve_rand_clk_if cif(clk);
    int unsigned sub_h, sub_n;
    odve_rand_tb_sub u_sub(.clk(clk), .h(sub_h), .n(sub_n));

    // edge cases of below(), urand(), irand(), urange()
    task automatic t_ranges();
        odve_rand r = new("ranges");
        longint unsigned nb[] = '{0, 1, 2, 3, 7, 100, 65535, 65536, 65537, 1000000,
                                  64'hFFFF_FFFF, 64'h1_0000_0000, 64'h1_0000_0001,
                                  64'h8000_0000_0000_0000, 64'h8000_0000_0000_0001,
                                  64'hFFFF_FFFF_FFFF_FFFF};
        foreach (nb[j]) begin
            int unsigned h = 0;
            for (int k = 0; k < 50; k++) h = fold(h, r.below(nb[j]));
            put($sformatf("below %0d", nb[j]), h);
        end
        begin
            int unsigned h = 0;
            for (int k = 0; k < 50; k++) h = fold(h, r.urand(10, 100));
            for (int k = 0; k < 50; k++) h = fold(h, r.urand(100, 10));       // empty: 100
            for (int k = 0; k < 50; k++) h = fold(h, r.urand(5, 5));
            for (int k = 0; k < 50; k++) h = fold(h, r.urand(0, 32'hFFFF_FFFF));
            for (int k = 0; k < 50; k++) h = fold(h, r.urand(32'hFFFF_FFF0, 32'hFFFF_FFFF));
            put("urand", h);
            h = 0;
            for (int k = 0; k < 50; k++) h = fold(h, r.urand64(100, 10));     // empty: 100
            for (int k = 0; k < 50; k++) h = fold(h, r.urand64(0, 64'hFFFF_FFFF_FFFF_FFFF));
            for (int k = 0; k < 50; k++) h = fold(h, r.urand64(64'hFFFF_FFFF_FFFF_FFF0, 64'hFFFF_FFFF_FFFF_FFFF));
            for (int k = 0; k < 50; k++) h = fold(h, r.urand64(64'h1_0000_0000, 64'h2_0000_0000));
            put("urand64", h);
            h = 0;
            for (int k = 0; k < 50; k++) h = fold(h, r.urange(15));
            for (int k = 0; k < 50; k++) h = fold(h, r.urange(0));
            for (int k = 0; k < 50; k++) h = fold(h, r.urange(32'hFFFF_FFFF));
            for (int k = 0; k < 50; k++) h = fold(h, r.urange(3, 9));             // reversed
            put("urange", h);
            h = 0;
            for (int k = 0; k < 50; k++) h = fold(h, r.irand(-5, 5));
            for (int k = 0; k < 50; k++) h = fold(h, r.irand(-2147483648, 2147483647));
            for (int k = 0; k < 50; k++) h = fold(h, r.irand(2147483647, -2147483648)); // empty: INT_MAX
            for (int k = 0; k < 50; k++) h = fold(h, r.irand(-2147483648, -2147483640));
            put("irand", h);
            h = 0;
            for (int p = 0; p <= 101; p++)
                for (int k = 0; k < 20; k++) h = fold(h, r.chance(p));
            for (int k = 0; k < 20; k++) h = fold(h, r.chance(32'hFFFF_FFFF));
            put("chance", h);
            h = 0;
            for (int k = 0; k < 50; k++) h = fold(h, r.index(0));
            for (int k = 0; k < 50; k++) h = fold(h, r.index(1));
            for (int k = 0; k < 50; k++) h = fold(h, r.index(13));
            put("index", h);
            h = 0;
            for (int k = 0; k < 50; k++) h = fold(h, r.weighted('{70, 20, 10}));
            for (int k = 0; k < 50; k++) h = fold(h, r.weighted('{0, 0, 5}));
            for (int k = 0; k < 50; k++) h = fold(h, r.weighted('{0, 0}));
            for (int k = 0; k < 50; k++) h = fold(h, r.weighted('{1, 0, 32'hFFFF_FFFF, 3}));
            put("weighted", h);
        end
    endtask

    // many random ranges; every result must be inside its range
    task automatic t_sweep();
        odve_rand c = new("sweep.ctl"), r = new("sweep");
        int unsigned h = 0, bad = 0;
        for (int k = 0; k < 100000; k++) begin
            longint unsigned lo, hi, v;
            int unsigned kind = c.urange(3);
            case (kind)
                0: begin lo = c.urange(1000); hi = lo + c.urange(1000); end
                1: begin lo = c.u32(); hi = c.u32(); end
                2: begin lo = c.u64(); hi = lo + c.urange(255); end
                default: begin lo = 0; hi = (64'd1 << c.urange(63)) - 1; end
            endcase
            v = r.urand64(lo, hi);
            if (lo <= hi ? (v < lo || v > hi) : (v != lo)) bad++;
            h = fold(h, v);
        end
        put("sweep", h);
        put("sweep_out_of_range", bad);
    endtask

    // the raw words and a long stream
    task automatic t_words();
        odve_rand r = new("words");
        int unsigned h = 0;
        for (int k = 0; k < 20; k++) put($sformatf("u16 %0d", k), r.u16());
        for (int k = 0; k < 10; k++) put($sformatf("u32 %0d", k), r.u32());
        for (int k = 0; k < 10; k++) put($sformatf("u64 %0d", k), r.u64());
        for (int b = 0; b < 4; b++) begin
            for (int k = 0; k < 250000; k++) h = fold(h, r.u16());
            put($sformatf("long %0d", b), h);
        end
    endtask

    // seeds, names, spawn, replay
    task automatic t_seeds();
        string names[] = '{"", "a", "b", "odve_rand", "uvm_test_top.env.mst_agent.drv",
                           "a very long stream name with spaces and digits 0123456789"};
        odve_rand r = new("seeds"), k1, k2, k3;
        int unsigned s, h = 0;
        put("run_seed", odve_rand::run_seed());
        foreach (names[j]) put($sformatf("stream_seed %0d", j), odve_rand::stream_seed(names[j]));
        k1 = r.spawn("item");
        k2 = r.spawn("item");      // same name, another stream
        k3 = r.spawn();
        put("spawn 1", k1.u32());
        put("spawn 2", k2.u32());
        put("spawn 3", k3.u32());
        put("spawn name", k1.get_name() == "item");
        s = r.get_seed();
        for (int k = 0; k < 100; k++) h = fold(h, r.u32());
        r.set_seed(s);
        for (int k = 0; k < 100; k++) h = fold(h, r.u32());
        put("replay", h);
        r.set_seed(0);             // seed 0 is a seed like any other
        put("seed0", r.u32());
    endtask

    // contexts: a case selector, ?:, inside, a package function
    task automatic t_exprs();
        odve_rand r = new("exprs");
        int unsigned h = 0;
        for (int k = 0; k < 2000; k++) begin
            int unsigned v;
            case (r.urange(3))
                0: v = 10;
                1: v = 11;
                2: v = 12;
                default: v = 13;
            endcase
            h = fold(h, v);
            v = r.chance(50) ? r.urange(9) : r.urange(99, 50);
            h = fold(h, v);
            if (r.urange(9) inside {[2:4], 7}) h = fold(h, 1);
            else h = fold(h, 2);
            h = fold(h, pkg_draw(r));
            h = fold(h, r.urange(9) % 4);
        end
        put("exprs", h);
    endtask

    initial begin
        worker w[$];
        fd = $fopen("rand_out.txt", "w");
        t_seeds();
        t_words();
        t_ranges();
        t_sweep();
        t_exprs();
        for (int i = 0; i < 50; i++) begin
            automatic worker x = new(i, cif);
            w.push_back(x);
            fork x.run_it(); join_none
        end
        wait fork;
        wait (sub_n == 100);
        put("sub", sub_h);
        $fclose(fd);
        $display("odve_rand_tb: done");
        $finish;
    end
endmodule
