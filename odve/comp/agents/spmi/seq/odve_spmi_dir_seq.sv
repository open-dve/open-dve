// Directed traffic: sends the items queued in `items` as they are (built by
// the test with add() / addw()). After the sequence the read items carry the
// data and NRF mask the master sampled, the others the ACK/NACK bit.
class odve_spmi_dir_seq extends uvm_sequence #(odve_spmi_item);
    `uvm_object_utils(odve_spmi_dir_seq)

    odve_spmi_item items[$];

    function new(string name = "odve_spmi_dir_seq");
        super.new(name);
    endfunction

    // queue a read (or a sequence whose data does not matter)
    function odve_spmi_item add(odve_spmi_kind_e kind, bit [3:0] sid, bit [15:0] addr, int unsigned nbytes);
        odve_spmi_item it = odve_spmi_item::type_id::create($sformatf("it%0d", items.size()));
        it.kind   = kind;
        it.sid   = sid;
        it.addr   = addr;
        it.nbytes = nbytes;
        it.data   = new[nbytes];
        items.push_back(it);
        return it;
    endfunction

    // queue a write of data (nbytes = data.size()); inj_par_frame as in the item
    function odve_spmi_item addw(odve_spmi_kind_e kind, bit [3:0] sid, bit [15:0] addr, bit [7:0] data[], int inj_par_frame = -1);
        odve_spmi_item it = add(kind, sid, addr, data.size());
        it.data          = data;
        it.inj_par_frame = inj_par_frame;
        return it;
    endfunction

    virtual task body();
        foreach (items[i]) begin
            start_item(items[i]);
            finish_item(items[i]);
        end
    endtask
endclass
