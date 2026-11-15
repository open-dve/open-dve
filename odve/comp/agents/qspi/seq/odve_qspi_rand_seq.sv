// n random flash operations in the current bus mode: reads with every read
// instruction the mode offers (quad ones only when `qe` says QE is set),
// page programs, now and then a sector erase or a status / ID read.
// Programs and erases wait for BUSY to clear.
class odve_qspi_rand_seq extends odve_qspi_base_seq;
    `uvm_object_utils(odve_qspi_rand_seq)

    int unsigned n         = 20;
    int unsigned max_bytes = 24;
    bit          qe        = 0;     // the flash has QE set: quad instructions allowed
    int unsigned erase_pct = 5;

    function new(string name = "odve_qspi_rand_seq");
        super.new(name);
    endfunction

    virtual task body();
        bit [7:0] spi_rd[$] = '{QSPI_READ, QSPI_FREAD, QSPI_DOR, QSPI_DIOR};
        bit [7:0] qpi_rd[$] = '{QSPI_FREAD, QSPI_QIOR};
        int unsigned w[];
        init_rng();
        w = new[5];
        w[0] = 50; w[1] = 30; w[2] = erase_pct; w[3] = 10; w[4] = 5;
        if (qe) begin spi_rd.push_back(QSPI_QOR); spi_rd.push_back(QSPI_QIOR); end
        repeat (n) begin
            odve_qspi_item it = odve_qspi_item::type_id::create("it");
            bit [7:0] d[$];
            bit       qpi = p_sequencer.cfg.bus.qpi;
            it.rng       = rng.spawn("it");
            it.mem_bytes = 8192;
            it.max_bytes = max_bytes;
            `odve_rand(it)
            case (rng.weighted(w))
                0: read(qpi ? qpi_rd[rng.index(qpi_rd.size())] : spi_rd[rng.index(spi_rd.size())], it.addr, it.nrd, d);
                1: page_program((qpi || !qe || rng.chance(50)) ? QSPI_PP : QSPI_QPP, it.addr, it.wdata);
                2: erase(it.addr);
                3: rd_reg(rng.chance(50) ? QSPI_RDSR1 : QSPI_RDSR2, rng.urand(1, 3), d);
                default: rd_reg(QSPI_RDID, rng.urand(3, 6), d);
            endcase
        end
    endtask
endclass
