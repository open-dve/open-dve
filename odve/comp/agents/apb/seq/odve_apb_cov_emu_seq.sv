// Reads the functional-coverage counters back from an odve_cov_emu block on
// the bus (comp/common/cov/odve_cov_emu.sv) and writes them as the run's
// cov.dump - what host software does on an emulator, here as a sequence.
// In simulation it also compares every counter with the package store the
// block was fed from, so the backend is checked on each run. FCOV=1 only.
`ifdef ODVE_FCOV
class odve_apb_cov_emu_seq extends odve_apb_base_seq;
    `uvm_object_utils(odve_apb_cov_emu_seq)

    bit [31:0]   reg_base   = 32'h0000_FFF0;   // odve_cov_emu REG_BASE
    int unsigned n_mismatch = 0;
    int unsigned max_report = 10;

    function new(string name = "odve_apb_cov_emu_seq");
        super.new(name);
    endfunction

    task xfer(bit [31:0] addr, bit write, inout bit [31:0] data, output bit slverr);
        odve_apb_item item = odve_apb_item::type_id::create("item");
        item.addr  = addr;
        item.write = write;
        item.data  = data;
        start_item(item);
        finish_item(item);
        data   = item.data;
        slverr = item.slverr;
    endtask

    task rd(bit [31:0] addr, output bit [31:0] data);
        bit slverr;
        data = '0;
        xfer(addr, 0, data, slverr);
        if (slverr) `uvm_error(get_name(), $sformatf("pslverr reading 0x%08h - is +apb_slave=cov on?", addr))
    endtask

    task wr(bit [31:0] addr, bit [31:0] data);
        bit slverr;
        xfer(addr, 1, data, slverr);
        if (slverr) `uvm_error(get_name(), $sformatf("pslverr writing 0x%08h", addr))
    endtask

    virtual task body();
        typedef odve_cov_pkg::odve_cov_store store;
        bit [31:0]   n_hw, w_hw, samples, v;
        int unsigned counts[];

        // No more samples from anywhere (the monitor sees this sequence's
        // own transfers too). Then let the feed drain its queue - one
        // index per clock, and a sample hits several bins, so it lags
        // behind the traffic - by reading the ID registers until it is
        // empty; the last two reads cover the in-flight sample.
        store::frozen = 1;
        while (store::smp_q.size() > 0) rd(reg_base + 4, n_hw);
        rd(reg_base + 4, n_hw);
        rd(reg_base + 8, w_hw);
        if (n_hw != odve_cov_pkg::N || w_hw != odve_cov_pkg::W) begin
            `uvm_error(get_name(), $sformatf("odve_cov_emu reports N=%0d W=%0d, the store has N=%0d W=%0d - not the same model", n_hw, w_hw, odve_cov_pkg::N, odve_cov_pkg::W))
            return;
        end
        wr(reg_base + 12, 32'h1);               // freeze in hardware, as host software would
        rd(reg_base + 0, samples);

        counts = new[n_hw];
        for (int i = 0; i < n_hw; i++) begin
            rd(4 * i, v);
            counts[i] = v;
            if (v != 32'(store::cnt[i])) begin
                n_mismatch++;
                if (n_mismatch <= max_report)
                    `uvm_error(get_name(), $sformatf("bin %0d: emu count %0d, store count %0d", i, v, store::cnt[i]))
            end
        end
        if (samples != 32'(store::nsamples))
            `uvm_error(get_name(), $sformatf("NSAMPLES: emu %0d, store %0d", samples, store::nsamples))
        `uvm_info(get_name(), $sformatf("odve_cov_emu readback: %0d bins, %0d samples, %0d mismatch(es)", n_hw, samples, n_mismatch), UVM_LOW)

        if (store::dump != "") begin
            store::write_ext(store::dump, "final", counts, samples, "emu");
            store::ext_dumped = 1;
        end
    endtask
endclass
`endif
