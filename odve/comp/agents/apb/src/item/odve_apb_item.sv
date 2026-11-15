// One APB transfer. No `rand`/constraints (ModelSim SE has no solver, see
// comp/agents/README.md): values come from user_randomize(), reached through
// `odve_rand(item).
//
// Where the values come from is a compile-time choice:
//   default              an odve_rand stream (comp/common/rand): the same
//                        values for the same +SEED on every simulator, so a
//                        failing seed reproduces on Verilator and Questa alike
//   +define+ODVE_USE_URANDOM  (make URANDOM=1) the simulator's own $urandom:
//                        follows -sv_seed / +verilator+seed+, and differs
//                        between simulators for the same seed
class odve_apb_item extends uvm_sequence_item;
    `uvm_object_utils(odve_apb_item)

    bit [31:0] addr;      // byte address
    bit [31:0] data;      // pwdata for a write, prdata after a read
    bit        write;
    bit        slverr;    // filled in by the driver / seen by the monitor
    int unsigned wait_states = 0;   // slave response only: cycles of pready low before the transfer completes

    // Knobs for user_randomize(): word index range of the slave's registers,
    // and whether out-of-range addresses (which the slave answers with
    // pslverr) may be generated.
    int unsigned nregs = 16;
    bit          allow_oor = 0;
    odve_rand    rng;           // set by the sequence (a spawned stream); own stream if null. Unused with ODVE_USE_URANDOM

    function new(string name = "odve_apb_item");
        super.new(name);
    endfunction

    function void user_randomize();
        int unsigned idx;
`ifdef ODVE_USE_URANDOM
        write = $urandom_range(0, 1);                                                          // odve_rand: ok - ODVE_USE_URANDOM build only
        data  = $urandom();                                                                    // odve_rand: ok - ODVE_USE_URANDOM build only
        if (allow_oor && $urandom_range(0, 7) == 0) idx = $urandom_range(nregs, 2 * nregs - 1); // odve_rand: ok - ODVE_USE_URANDOM build only
        else                                          idx = $urandom_range(0, nregs - 1);       // odve_rand: ok - ODVE_USE_URANDOM build only
`else
        if (rng == null) rng = new("odve_apb_item");
        write = rng.urand(0, 1);
        data  = rng.u32();
        if (allow_oor && rng.urand(0, 7) == 0) idx = rng.urand(nregs, 2 * nregs - 1);
        else                                     idx = rng.urand(0, nregs - 1);
`endif
        addr = idx * 4;
        slverr = 0;
    endfunction

    function string convert2string();
        return $sformatf("%s addr=0x%08h data=0x%08h%s", write ? "WR" : "RD", addr, data, slverr ? " SLVERR" : "");
    endfunction
endclass
