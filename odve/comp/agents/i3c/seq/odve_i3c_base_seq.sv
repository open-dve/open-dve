// Base of the controller's sequences: helpers that build one item, run it on
// the controller and hand back the results (ack, read data, ENTDAA rounds).
// Every random value comes from `rng` (an odve_rand stream: set it, or one
// named after the sequence is made).
class odve_i3c_base_seq extends uvm_sequence #(odve_i3c_item);
    `uvm_object_utils(odve_i3c_base_seq)

    odve_rand rng;

    function new(string name = "odve_i3c_base_seq");
        super.new(name);
    endfunction

    function void rng_init();
        if (rng == null) rng = new(get_full_name());
    endfunction

    task xfer(odve_i3c_item it);
        start_item(it);
        finish_item(it);
    endtask

    task priv_wr(bit [6:0] addr, bit [7:0] bytes[$], output bit ack, input int perr_idx = -1, input bit use_7e = 1);
        odve_i3c_item it = odve_i3c_item::type_id::create("it");
        it.kind = I3C_PRIV_WR; it.addr = addr; it.data = bytes; it.perr_idx = perr_idx; it.use_7e = use_7e;
        xfer(it);
        ack = it.ack;
    endtask

    task priv_rd(bit [6:0] addr, int unsigned len, output bit [7:0] bytes[$], output bit ack, output bit t_end,
                 input bit use_7e = 1);
        odve_i3c_item it = odve_i3c_item::type_id::create("it");
        it.kind = I3C_PRIV_RD; it.addr = addr; it.len = len; it.use_7e = use_7e;
        xfer(it);
        bytes = it.data; ack = it.ack; t_end = it.t_end;
    endtask

    task ccc_bc(bit [7:0] ccc, bit [7:0] bytes[$]);
        odve_i3c_item it = odve_i3c_item::type_id::create("it");
        it.kind = I3C_CCC_BC; it.ccc = ccc; it.data = bytes;
        xfer(it);
    endtask

    task ccc_dw(bit [7:0] ccc, bit [6:0] addr, bit [7:0] bytes[$], output bit ack);
        odve_i3c_item it = odve_i3c_item::type_id::create("it");
        it.kind = I3C_CCC_DW; it.ccc = ccc; it.addr = addr; it.data = bytes;
        xfer(it);
        ack = it.ack;
    endtask

    task ccc_dr(bit [7:0] ccc, bit [6:0] addr, output bit [7:0] bytes[$], output bit ack);
        odve_i3c_item it = odve_i3c_item::type_id::create("it");
        it.kind = I3C_CCC_DR; it.ccc = ccc; it.addr = addr; it.len = i3c_get_len(ccc);
        xfer(it);
        bytes = it.data; ack = it.ack;
    endtask

    // ENTDAA: offers pool[r] in round r; returns the item with every round
    task entdaa(bit [6:0] pool[$], output odve_i3c_item it, input int perr_round = -1);
        it = odve_i3c_item::type_id::create("it");
        it.kind = I3C_ENTDAA; it.ccc = I3C_CCC_ENTDAA; it.da_pool = pool; it.perr_idx = perr_round;
        xfer(it);
    endtask

    virtual task body();
    endtask
endclass
