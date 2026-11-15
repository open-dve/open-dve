// Directed traffic: sends the items queued in `items` as they are (built by
// the test with add() / addw()). After the sequence the read items carry the data
// and NRF mask the master sampled.
class odve_rffe_dir_seq extends uvm_sequence #(odve_rffe_item);
    `uvm_object_utils(odve_rffe_dir_seq)

    odve_rffe_item items[$];

    function new(string name = "odve_rffe_dir_seq");
        super.new(name);
    endfunction

    // queue a read (or a sequence whose data does not matter)
    function odve_rffe_item add(odve_rffe_kind_e kind, bit [3:0] usid, bit [15:0] addr, int unsigned nbytes);
        odve_rffe_item it = odve_rffe_item::type_id::create($sformatf("it%0d", items.size()));
        it.kind   = kind;
        it.usid   = usid;
        it.addr   = addr;
        it.nbytes = nbytes;
        it.data   = new[nbytes];
        items.push_back(it);
        return it;
    endfunction

    // queue a write of data (nbytes = data.size()); inj_par_frame as in the item
    function odve_rffe_item addw(odve_rffe_kind_e kind, bit [3:0] usid, bit [15:0] addr, bit [7:0] data[], int inj_par_frame = -1);
        odve_rffe_item it = add(kind, usid, addr, data.size());
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
