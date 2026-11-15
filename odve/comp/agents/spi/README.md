# odve SPI agent

UVM agent for the Serial Peripheral Interface (Motorola SPI block guide
conventions: SCK/MOSI/MISO/SS, CPOL/CPHA/LSBFE), master and slave roles, with
a standalone testbench against an RTL SPI slave. Protocol summary:
[`doc/spec.md`](doc/spec.md); requirements and traceability:
[`doc/req.md`](doc/req.md).

## Layout

| Path | What |
| --- | --- |
| `intf/odve_spi_if.sv` | `sclk`, `mosi`, `cs_n[ODVE_SPI_MAX_CS-1:0]` (default 4), MISO as explicit value/enable pairs per driver (`s_miso/_oe` slave agents, `d_miso/_oe` RTL), resolved bus `miso` and `miso_ndrv` |
| `src/item/odve_spi_item.sv` | one frame: `cs`, `mosi[$]`/`miso[$]` words, format copy, master timing/injection knobs, monitor results (`partial_bits`, `had_gap`, `proto_err`) |
| `src/agent/odve_spi_cfg.sv` | `odve_spi_dev_cfg` (per chip select: `cpol`, `cpha`, `lsb_first`, `word_bits`) and `odve_spi_cfg` |
| `src/agent/odve_spi_slv_model.sv` | the slave register-file model (MEM and SEQ mode) |
| `src/agent/mon/` | cycle-based monitor: frames, protocol checks, coverage `odve_spi_cg` |
| `src/agent/mst/` | master driver: generates SCK, `cs_n`, MOSI, samples MISO |
| `src/agent/slv/` | slave driver: answers one chip select from the model or a sequence |
| `seq/` | `odve_spi_base_seq` (random frames), `odve_spi_reg_seq` (register protocol: random + `write`/`read`/`xfer`), `odve_spi_raw_seq` (hand-built items), `odve_spi_slv_rsp_seq` (reactive slave) |
| `vrf/dut/dut.sv` | RTL slave: 64-byte register file, format by strap pins |
| `vrf/tb/` | `top.sv`, `spi_strap_if.sv`, `env/` (env, `cc`, scoreboard + `spi_reg_cg`), `tests/` |

## Configuration (`odve_spi_cfg`)

| Field | Default | Meaning |
| --- | --- | --- |
| `role` | `ODVE_SPI_MASTER` | or `ODVE_SPI_SLAVE` |
| `slv_mode` | `ODVE_SPI_SLV_MEM` | slave: model in the driver, or `ODVE_SPI_SLV_SEQ` (requests to `slv_sqr.req_fifo`, answered by `odve_spi_slv_rsp_seq`) |
| `has_mon` | 1 | one monitor per bus |
| `ncs` | 1 | chip selects in use |
| `dev[i]` | mode 0, MSB, 8-bit | format of chip select `i`; share the same objects between all cfgs on a bus |
| `half_period`, `lead`, `trail`, `idle` | 4 | master timing in system clock cycles (SCK half period, tL, tT, tI) |
| `min_lead`, `min_trail`, `min_idle` | 0 (= `half_period`) | monitor limits |
| `slv_cs`, `slv_id`, `slv_nbytes` | 0, `0xA5`, 64 | slave: chip select answered, ID byte, register file size |

Item knobs for the master: `word_gap` (idle cycles between words), `lead` /
`trail` / `idle` overrides, `abort_after_bits` (raise `cs_n` mid-frame),
`cpol_err` (leave SCK off idle at `cs_n` rise). All agent components are
cycle based on the interface's `clk` (SCK half period >= 2 cycles; the RTL
slave needs >= 4).

## Plusargs (TB)

`+spi_slave=dut|mem|seq` - the two RTL slaves (default), or two slave agents
(one per chip select) in MEM or SEQ mode. Every agent and the RTL straps
share one format per chip select; `env.set_format()` changes it between
frames.

## Running

```bash
cd odve/comp/agents/spi/vrf/work/run
source sourceme
make aclean all run TESTNAME=mode_test                   # ModelSim/Questa
make aclean all run TESTNAME=mode_test VERILATOR=1       # Verilator
./regress.py submit -j 2 -exer                           # 13 runs
./regress.py submit -j 2 -exer -ropts="VERILATOR=1"
./regress.py submit -j 2 -cov -ropts="VERILATOR=1"       # + functional coverage
```

## Tests

| Test | Slaves (submit) | Requirements (doc/req.md) |
| --- | --- | --- |
| `rw_test` - random reads/writes, two slaves of different formats | dut, mem, seq | 001, 006, 008, 016-018, 021, 022 |
| `mode_test` - 4 modes x MSB/LSB x 8/16/32 on both chip selects | dut, mem, seq | 001-005, 016-018, 021, 022 |
| `burst_test` - whole-file frames, wrap, over-length, command-only, inter-word gaps | dut, seq | 005-007, 016, 017, 019, 020, 022 |
| `b2b_test` - minimum tL/tT/tI, SCK half periods 4/5/9, alternating slaves | dut, mem | 008, 010-012, 021, 023, 024 |
| `abort_test` - `cs_n` raised mid-word, read back | dut, mem | 015, 021 |
| `err_test` - injected tL/tT/tI, CPOL, double select, contention, undriven MISO; each must be reported | dut | 001, 009-014 |

## Known limitations

- Multi-word frames are allowed in CPHA=0, where the block guide's own slave
  needs SS high between bytes (see `doc/spec.md`).
- No mode fault / multi-master, no bidirectional (MOMI/SISO) mode, no
  dual/quad data lines (see the `qspi` agent).
- The monitor and drivers sample on the system clock, so they need SCK
  edges aligned to it (true for this master; an external asynchronous
  master would need SCK half periods of several clock cycles).
- The slave model and the RTL slave share one ad-hoc register protocol; a
  different slave protocol needs its own model/sequence.
