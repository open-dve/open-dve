// Turns the monitor's expected protocol-violation errors (by message ID)
// into UVM_INFO and counts them, so an error-injection test can check that
// the monitor detected exactly what was injected. Any other error passes.
class err_catcher extends uvm_report_catcher;
    string       ids[$];
    int unsigned n_caught[string];

    function new(string name = "err_catcher");
        super.new(name);
    endfunction

    function int unsigned count(string id);
        return n_caught.exists(id) ? n_caught[id] : 0;
    endfunction

    virtual function action_e catch();
        if (get_severity() == UVM_ERROR) begin
            foreach (ids[i]) begin
                if (get_id() == ids[i]) begin
                    n_caught[ids[i]] = count(ids[i]) + 1;
                    set_severity(UVM_INFO);
                    set_message({"expected: ", get_message()});
                    break;
                end
            end
        end
        return THROW;
    endfunction
endclass
