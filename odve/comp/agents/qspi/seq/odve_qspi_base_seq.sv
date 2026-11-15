typedef class odve_qspi_one_seq;

// Base of the agent's master sequences: flash operations as tasks. Every
// helper sends its frames as one-item sequences on p_sequencer, so it works
// from body() and from a test that only set_sequencer()'d the sequence.
// Values from the sequence's odve_rand stream (`rng`), each item drawing
// from a spawn() of it (comp/common/rand/README rule 3).
class odve_qspi_base_seq extends uvm_sequence #(odve_qspi_item);
    `uvm_object_utils(odve_qspi_base_seq)
    `uvm_declare_p_sequencer(odve_qspi_sqr)

    odve_rand    rng;
    int unsigned max_polls = 2000;

    function new(string name = "odve_qspi_base_seq");
        super.new(name);
    endfunction

    function void init_rng();
        if (rng == null) rng = new(get_full_name());
    endfunction

    function odve_qspi_item new_item(bit [7:0] cmd);
        odve_qspi_item it = odve_qspi_item::type_id::create("it");
        it.cmd = cmd;
        return it;
    endfunction

    task send(odve_qspi_item item);
        odve_qspi_one_seq one = odve_qspi_one_seq::type_id::create("one");
        one.item = item;
        one.start(p_sequencer);
    endtask

    // instruction only: WREN, WRDI, ...
    task op(bit [7:0] cmd);
        send(new_item(cmd));
    endtask

    // instruction + n bytes read, no address (status, JEDEC ID)
    task rd_reg(bit [7:0] cmd, int unsigned n, output bit [7:0] d[$]);
        odve_qspi_item it = new_item(cmd);
        it.nrd = n;
        send(it);
        d = it.rdata;
    endtask

    // read n bytes at addr with any read instruction (03h, 0Bh, 3Bh, BBh, 6Bh, EBh, 5Ah)
    task read(bit [7:0] cmd, bit [23:0] addr, int unsigned n, output bit [7:0] d[$]);
        odve_qspi_item it = new_item(cmd);
        it.addr = addr;
        it.nrd  = n;
        send(it);
        d = it.rdata;
    endtask

    // poll status register 1 until BUSY clears; returns the last status
    task wait_ready(output bit [7:0] sr);
        bit [7:0] d[$];
        for (int i = 0; i < max_polls; i++) begin
            rd_reg(QSPI_RDSR1, 1, d);
            sr = d[0];
            if (!sr[0]) return;
        end
        `uvm_error(get_name(), $sformatf("flash still busy after %0d status polls", max_polls))
    endtask

    // WREN, PP/QPP, wait until done ("program" is a keyword)
    task page_program(bit [7:0] cmd, bit [23:0] addr, bit [7:0] data[$], bit wren = 1);
        odve_qspi_item it = new_item(cmd);
        bit [7:0] sr;
        if (wren) op(QSPI_WREN);
        it.addr  = addr;
        it.wdata = data;
        send(it);
        wait_ready(sr);
    endtask

    // WREN, SE, wait until done
    task erase(bit [23:0] addr, bit wren = 1);
        odve_qspi_item it = new_item(QSPI_SE);
        bit [7:0] sr;
        if (wren) op(QSPI_WREN);
        it.addr = addr;
        send(it);
        wait_ready(sr);
    endtask

    // WREN, write status register 2 (bit 1 = QE), wait until done
    task write_sr2(bit [7:0] v);
        odve_qspi_item it = new_item(QSPI_WRSR2);
        bit [7:0] sr;
        op(QSPI_WREN);
        it.wdata.push_back(v);
        send(it);
        wait_ready(sr);
    endtask

    // 38h / FFh, and tell every agent on the bus (cfg.bus.qpi) - only call
    // enter_qpi() with QE set, or the flash stays in SPI mode
    task enter_qpi();
        op(QSPI_QPIEN);
        p_sequencer.cfg.bus.qpi = 1;
    endtask
    task exit_qpi();
        op(QSPI_QPIEX);
        p_sequencer.cfg.bus.qpi = 0;
    endtask

    // random write data
    function void rand_bytes(int unsigned n, output bit [7:0] d[$]);
        d.delete();
        repeat (n) begin
            bit [7:0] b = rng.urange(255);
            d.push_back(b);
        end
    endfunction

    virtual task body();
        init_rng();
    endtask
endclass

// carrier of base_seq::send()
class odve_qspi_one_seq extends uvm_sequence #(odve_qspi_item);
    `uvm_object_utils(odve_qspi_one_seq)
    odve_qspi_item item;
    function new(string name = "odve_qspi_one_seq");
        super.new(name);
    endfunction
    virtual task body();
        start_item(item);
        finish_item(item);
    endtask
endclass
