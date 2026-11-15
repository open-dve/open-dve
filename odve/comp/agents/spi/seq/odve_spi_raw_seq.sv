// Sends the items queued in `items` as they are - frames built by hand
// (directed words, injected violations).
class odve_spi_raw_seq extends odve_spi_base_seq;
    `uvm_object_utils(odve_spi_raw_seq)

    odve_spi_item items[$];

    function new(string name = "odve_spi_raw_seq");
        super.new(name);
    endfunction

    virtual task body();
        foreach (items[i]) begin
            start_item(items[i]);
            finish_item(items[i]);
        end
    endtask
endclass
