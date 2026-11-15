// Runs one prepared item on the controller (tests build items, this carries
// them); the results are in `it` afterwards.
class odve_i3c_xfer_seq extends odve_i3c_base_seq;
    `uvm_object_utils(odve_i3c_xfer_seq)

    odve_i3c_item it;

    function new(string name = "odve_i3c_xfer_seq");
        super.new(name);
    endfunction

    virtual task body();
        xfer(it);
    endtask
endclass
