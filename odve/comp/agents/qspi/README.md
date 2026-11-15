# odve QSPI agent

UVM agent for quad-SPI serial NOR flash buses (CS_n, SCLK, IO[3:0]):
master (flash controller) and slave (behavioural flash) roles, SPI and QPI
modes, formats 1-1-1, 1-1-2, 1-2-2, 1-1-4, 1-4-4 and 4-4-4, with a standalone
testbench against a small RTL QSPI NOR flash. Command reference: Winbond
W25Q32FV. Protocol summary: [`doc/spec.md`](doc/spec.md); requirements and
traceability: [`doc/req.md`](doc/req.md).

## Layout

| Path | What |
| --- | --- |
| `intf/odve_qspi_if.sv` | `cs_n`, `sclk`, value/enable pairs per driver (`m_io/_oe` master, `s_io/_oe` slave agent, `d_io/_oe` RTL), resolved `io[3:0]` and `io_ndrv[]` |
| `src/item/odve_qspi_item_pkg.sv` | opcodes, `odve_qspi_fmt()` (the shape of every instruction in SPI and QPI mode), the item |
| `src/item/odve_qspi_item.sv` | one frame: `cmd`, `addr`, `mode_byte`, `wdata[$]`/`rdata[$]`, `nrd`, injection knobs, monitor results (`nclk`, `truncated`, `partial_bits`, `unknown`, `proto_err`) |
| `src/agent/odve_qspi_cfg.sv` | `odve_qspi_bus_cfg` (shared: `cpol`, `qpi`, `qpi_dummy`) and `odve_qspi_cfg` |
| `src/agent/odve_qspi_decoder.sv` | rebuilds a frame from its rising edges (monitor and slave driver) |
| `src/agent/odve_qspi_flash_model.sv` | the behavioural flash (MEM and SEQ mode) |
| `src/agent/{mon,mst,slv}/` | monitor (checks, coverage `odve_qspi_cg`), master driver, slave driver |
| `seq/` | `odve_qspi_base_seq` (operations: `read`, `page_program`, `erase`, `rd_reg`, `write_sr2`, `enter_qpi`/`exit_qpi`, `wait_ready`, `send`), `odve_qspi_rand_seq`, `odve_qspi_slv_rsp_seq` |
| `vrf/dut/dut.sv` | RTL flash: 8 KiB, the instruction set of `doc/spec.md` |
| `vrf/tb/` | `top.sv`, `env/` (env, `cc`, scoreboard + `qspi_flash_cg`), `tests/` |

## Configuration (`odve_qspi_cfg`)

| Field | Default | Meaning |
| --- | --- | --- |
| `role` | `ODVE_QSPI_MASTER` | or `ODVE_QSPI_SLAVE` |
| `slv_mode` | `ODVE_QSPI_SLV_MEM` | slave: flash model in the driver, or `ODVE_QSPI_SLV_SEQ` (requests in `slv_sqr.req_fifo`, answered by `odve_qspi_slv_rsp_seq`) |
| `has_mon` | 1 | one monitor per bus |
| `bus.cpol` | 0 | SPI mode 0 or 3 (shared object, give every cfg on the bus the same) |
| `bus.qpi` | 0 | the flash is in QPI mode; `enter_qpi()`/`exit_qpi()` set it |
| `bus.qpi_dummy` | 2 | QPI dummy clocks of 0Bh/EBh |
| `half_period`, `lead`, `trail`, `idle` | 4 | master timing, system clock cycles |
| `min_lead`, `min_trail`, `min_idle` | 0 (= `half_period`) | monitor limits |
| `chk_undriven` | 1 | report undriven lanes (`QSPI_IO_Z`); clear it around reads the flash is expected to ignore |
| `mem_bytes`, `tpp`, `tse`, `tw` | 8192, 1500, 5000, 200 | slave: array size and busy times (cycles) |
| `mfr_id`, `type_spi`, `type_qpi`, `cap_id` | EFh, 40h, 60h, 0Dh | slave: JEDEC ID |

Item knobs for the master: `lead`/`trail`/`idle` overrides, `abort_after_clks`,
`extra_clks`, `cpol_err`. Components are cycle based on the interface `clk`
(sclk half period >= 2 cycles; the RTL flash needs >= 4).

## Plusargs (TB)

`+qspi_slave=dut|mem|seq` (RTL flash, default, or the slave agent in MEM /
SEQ mode), `+qspi_mode=0|3`.

## Running

```bash
cd odve/comp/agents/qspi/vrf/work/run
source sourceme
make aclean all run TESTNAME=read_test                   # ModelSim/Questa
make aclean all run TESTNAME=read_test VERILATOR=1       # Verilator
./regress.py submit -j 2 -exer                           # 14 runs
./regress.py submit -j 2 -exer -ropts="VERILATOR=1"
./regress.py submit -j 2 -cov -ropts="VERILATOR=1"
```

## Tests

| Test | Variants in submit | Requirements |
| --- | --- | --- |
| `id_test` - JEDEC ID, SFDP, status 1/2, WEL, QE, QPI enter/exit | dut, mem | 011-016, 030 |
| `read_test` - every read instruction, page crossing, array wrap, high address bits, SPI and QPI | dut, dut mode 3, mem, seq mode 3 | 001, 003-010, 016, 030, 031 |
| `prog_test` - PP / QPP / QPI PP, over-programming, page wrap, > 256 bytes, no WEL, sector erase | dut, mem, seq | 011, 016-020, 022, 030, 031 |
| `busy_test` - status during program/erase/status write, ignored commands, BUSY falling in a status stream | dut, seq | 012, 020-022, 031 |
| `rand_test` - random operations, SPI without/with QE, QPI | dut, mem mode 3 | 001, 003-009, 017-020, 030 |
| `err_test` - QE = 0, truncated program/address, extra clocks, timing, CPOL, contention, unknown opcode | dut | 002, 007, 008, 016, 018, 023-029 |

## Known limitations

- `bus.qpi` is bus-level knowledge: the sequence that sends 38h/FFh updates
  it; if the flash ignores 38h (QE clear) do not call `enter_qpi()`.
- Not modelled: continuous read mode, C0h, wrap/burst reads, E7h/E3h,
  90h/92h/94h/ABh, block/chip erase, suspend/resume, power-down, reset,
  protection bits, /WP and /HOLD functions, DTR, 4-byte addresses.
- The JEDEC SFDP standard itself was not available; the SFDP table is a
  plausible header + density only.
