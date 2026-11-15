typedef class odve_spi_one_seq;

// Base of the agent's master sequences: n frames of random words to random
// chip selects (generic SPI traffic; the word stream means nothing to the
// slave). Values from the sequence's odve_rand stream, each item drawing
// from a spawn() of it (comp/common/rand/README rule 3).
class odve_spi_base_seq extends uvm_sequence #(odve_spi_item);
    `uvm_object_utils(odve_spi_base_seq)
    `uvm_declare_p_sequencer(odve_spi_sqr)

    int unsigned n         = 8;
    int unsigned max_words = 8;
    int unsigned gap_pct   = 0;
    int          cs        = -1;     // >= 0: only this chip select
    odve_rand    rng;

    function new(string name = "odve_spi_base_seq");
        super.new(name);
    endfunction

    function void init_rng();
        if (rng == null) rng = new(get_full_name());
    endfunction

    // a random item on the agent's slaves, words masked to the slave's width
    function odve_spi_item rand_item();
        odve_spi_item item = odve_spi_item::type_id::create("item");
        item.rng       = rng.spawn("item");
        item.ncs       = p_sequencer.cfg.ncs;
        item.max_words = max_words;
        item.gap_pct   = gap_pct;
        `odve_rand(item)
        if (cs >= 0) item.cs = cs;
        item.word_bits = p_sequencer.cfg.dev[item.cs].word_bits;
        foreach (item.mosi[i]) item.mosi[i] &= item.mask();
        return item;
    endfunction

    // one frame, as a one-item sequence on p_sequencer: works from body()
    // and from a test that only set_sequencer()'d this sequence
    task send(odve_spi_item item);
        odve_spi_one_seq one = odve_spi_one_seq::type_id::create("one");
        one.item = item;
        one.start(p_sequencer);
    endtask

    virtual task body();
        init_rng();
        repeat (n) begin
            odve_spi_item item = rand_item();
            start_item(item);
            finish_item(item);
        end
    endtask
endclass

// carrier of base_seq::send()
class odve_spi_one_seq extends uvm_sequence #(odve_spi_item);
    `uvm_object_utils(odve_spi_one_seq)
    odve_spi_item item;
    function new(string name = "odve_spi_one_seq");
        super.new(name);
    endfunction
    virtual task body();
        start_item(item);
        finish_item(item);
    endtask
endclass
