// Register-file traffic in the command protocol of the RTL slave and of the
// slave agent's model (src/agent/odve_spi_slv_model.sv): word 0 = read bit
// (MSB of the word) + byte address [5:0], then data words.
// body(): n random reads/writes of 0..max_words data words; write()/read()
// are the directed helpers tests use - from a test, without start(): call
// set_sequencer(<master sqr>) once, every helper frame then runs as a
// one-item sequence of its own.
class odve_spi_reg_seq extends odve_spi_base_seq;
    `uvm_object_utils(odve_spi_reg_seq)

    int unsigned rd_pct = 50;
    int unsigned nbytes = 64;      // address space of the slave

    function new(string name = "odve_spi_reg_seq");
        super.new(name);
    endfunction

    function bit [31:0] cmd_word(int unsigned c, bit rd, int unsigned addr);
        int unsigned bits = p_sequencer.cfg.dev[c].word_bits;
        return (32'(rd) << (bits - 1)) | (addr & 6'h3F);
    endfunction

    // One frame: command + the given data words (read: as many dummy words).
    task xfer(int unsigned c, bit rd, int unsigned addr, bit [31:0] data[$], output odve_spi_item item,
              input int unsigned word_gap = 0, input int abort_after_bits = -1);
        item = odve_spi_item::type_id::create("item");
        item.cs = c;
        item.word_bits = p_sequencer.cfg.dev[c].word_bits;
        item.mosi.push_back(cmd_word(c, rd, addr));
        foreach (data[i]) item.mosi.push_back(rd ? 32'h0 : (data[i] & item.mask()));
        item.word_gap = word_gap;
        item.abort_after_bits = abort_after_bits;
        send(item);
    endtask

    task write(int unsigned c, int unsigned addr, bit [31:0] data[$], int unsigned word_gap = 0);
        odve_spi_item item;
        xfer(c, 0, addr, data, item, word_gap);
    endtask

    task read(int unsigned c, int unsigned addr, int unsigned nwords, output bit [31:0] data[$], input int unsigned word_gap = 0);
        odve_spi_item item;
        bit [31:0] dummy[$];
        repeat (nwords) dummy.push_back(0);
        xfer(c, 1, addr, dummy, item, word_gap);
        data = item.miso;
        if (data.size() > 0) data.pop_front();    // word 0 is the slave's ID
    endtask

    virtual task body();
        init_rng();
        repeat (n) begin
            odve_spi_item item = rand_item();      // cs, data words (count 1..max_words), gap
            bit           rd   = rng.chance(rd_pct);
            int unsigned  addr = rng.below(nbytes);
            bit [31:0]    data[$];
            odve_spi_item done;
            // word 0 of the random item becomes the command: 0..max_words-1 data words
            for (int i = 1; i < item.mosi.size(); i++) data.push_back(item.mosi[i]);
            xfer(item.cs, rd, addr, data, done, item.word_gap);
        end
    endtask
endclass
