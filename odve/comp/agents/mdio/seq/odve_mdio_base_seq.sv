// Directed frames: build a list with the push_* helpers (or push() any
// item), then start the sequence. The items are updated in place by the
// master driver, so after the sequence q[i].data / q[i].resp hold what each
// read returned. pre_len / idle apply to every frame pushed after they are set.
class odve_mdio_base_seq extends uvm_sequence #(odve_mdio_item);
    `uvm_object_utils(odve_mdio_base_seq)

    odve_mdio_item q[$];
    int unsigned   pre_len = 32;
    int unsigned   idle    = 1;

    function new(string name = "odve_mdio_base_seq");
        super.new(name);
    endfunction

    function odve_mdio_item push(odve_mdio_kind_e kind, bit [4:0] phyad, bit [4:0] regad, bit [15:0] data = '0);
        odve_mdio_item it = odve_mdio_item::type_id::create($sformatf("f%0d", q.size()));
        it.kind    = kind;
        it.phyad   = phyad;
        it.regad   = regad;
        it.data    = data;
        it.pre_len = pre_len;
        it.idle    = idle;
        q.push_back(it);
        return it;
    endfunction

    function void c22_wr(bit [4:0] pa, bit [4:0] ra, bit [15:0] d); void'(push(ODVE_MDIO_C22_WR, pa, ra, d)); endfunction
    function void c22_rd(bit [4:0] pa, bit [4:0] ra);               void'(push(ODVE_MDIO_C22_RD, pa, ra)); endfunction
    function void c45_addr(bit [4:0] pa, bit [4:0] dev, bit [15:0] a); void'(push(ODVE_MDIO_C45_ADDR, pa, dev, a)); endfunction
    function void c45_wr(bit [4:0] pa, bit [4:0] dev, bit [15:0] d);   void'(push(ODVE_MDIO_C45_WR, pa, dev, d)); endfunction
    function void c45_rd(bit [4:0] pa, bit [4:0] dev);                 void'(push(ODVE_MDIO_C45_RD, pa, dev)); endfunction
    function void c45_rinc(bit [4:0] pa, bit [4:0] dev);               void'(push(ODVE_MDIO_C45_RINC, pa, dev)); endfunction

    virtual task body();
        foreach (q[i]) begin
            start_item(q[i]);
            finish_item(q[i]);
        end
    endtask
endclass
