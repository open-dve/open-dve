// One APB transfer. No `rand`/constraints (ModelSim SE has no solver, see
// comp/agents/README.md): values come from user_randomize(), reached through
// `odve_rand(item), with plain $urandom.
class odve_apb_item extends uvm_sequence_item;
    `uvm_object_utils(odve_apb_item)

    bit [31:0] addr;      // byte address
    bit [31:0] data;      // pwdata for a write, prdata after a read
    bit        write;
    bit        slverr;    // filled in by the driver / seen by the monitor

    // Knobs for user_randomize(): word index range of the slave's registers,
    // and whether out-of-range addresses (which the slave answers with
    // pslverr) may be generated.
    int unsigned nregs = 16;
    bit          allow_oor = 0;

    function new(string name = "odve_apb_item");
        super.new(name);
    endfunction

    function void user_randomize();
        int unsigned idx;
        write = $urandom_range(0, 1);
        data  = $urandom();
        if (allow_oor && $urandom_range(0, 7) == 0) idx = $urandom_range(nregs, 2 * nregs - 1);
        else                                          idx = $urandom_range(0, nregs - 1);
        addr = idx * 4;
        slverr = 0;
    endfunction

    function string convert2string();
        return $sformatf("%s addr=0x%08h data=0x%08h%s", write ? "WR" : "RD", addr, data, slverr ? " SLVERR" : "");
    endfunction
endclass
