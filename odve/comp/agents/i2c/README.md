# odve I2C agent

UVM agent for the I2C bus (NXP UM10204 Rev. 7.0): controller (master) and
target (slave) roles, 7-bit and 10-bit addressing, write / read / combined
transfers, ACK/NACK, clock stretching, general call, a protocol-checking
monitor and a functional covergroup. It is also the bit layer of the
`smbus` and `pmbus` agents. Protocol summary: `doc/spec.md`; requirements and
their tests: `doc/req.md`.

## Layout

| Path | Contents |
| --- | --- |
| `intf/odve_i2c_if.sv` | SCL/SDA as open drain without tristates: per-party `*_o/*_oe` (`m_` master, `s_` slave agent, `d_` DUT, `x_` spare), wired-AND with pull-up |
| `src/item/` | `odve_i2c_item` (one transfer START..STOP), `odve_i2c_slv_item` (one target event), `odve_i2c_item_pkg` |
| `src/agent/` | `odve_i2c_cfg`, `odve_i2c_agent`, `odve_i2c_sqr`, `odve_i2c_slv_sqr`, `odve_i2c_slv_model` (+ `odve_i2c_mem_model`), the covergroup `odve_i2c_cg` in `odve_i2c_agent_pkg` |
| `src/agent/mst/` | `odve_i2c_mst_drv_base`: controller, generates SCL |
| `src/agent/slv/` | `odve_i2c_slv_drv`: target |
| `src/agent/mon/` | `odve_i2c_mon`: transfer reconstruction, protocol and timing checks, coverage |
| `seq/` | `odve_i2c_item_seq` (one prepared item), `odve_i2c_rand_seq`, `odve_i2c_slv_model_seq` (responder) |
| `list/` | `agent.f` (interface + item + agent packages), `item.f`, `seq.f` |
| `vrf/dut/` | `odve_i2c_tgt_phy.sv` (synthesizable target bit/byte layer, reused by smbus/pmbus), `dut.sv` (16-register target) |
| `vrf/tb/` | `top.sv`, `env/` (env, `cc`, scoreboard), `tests/` |

`list/agent.f` needs `odve_rand_pkg` compiled before it (the item draws from
it) - `vrf/list/fl_tb.f` lists it first, as must any TB that uses the agent.

## Roles and modes (`odve_i2c_cfg`)

- `role = ODVE_I2C_MASTER`: sequencer + controller driver. Drive
  `odve_i2c_item`s: `kind` (`I2C_WRITE`, `I2C_READ`, `I2C_WRITE_READ`),
  `addr`, `addr10`, `wdata[$]`, `nrd`; results come back in the item
  (`addr_ack`, `wack[]`, `wr_nack`, `rdata[]`). `rd_count_hdr`/`rd_extra` read
  a count-prefixed block (SMBus). Error injection: `abort_byte`/`abort_bit`
  (STOP inside a written byte), `tmo_byte`/`tmo_cycles` (hold SCL low, then STOP).
- `role = ODVE_I2C_SLAVE`: target at `addr7` (`en_addr7`) and `addr10`
  (`en_addr10`), general call with `gc_en`, plus any address its model
  `claims()`. Behaviour per event comes from a model (`odve_i2c_slv_model`,
  default `odve_i2c_mem_model`: 16 registers, pointer, CTRL = register 15
  bits [5:0] = stretch cycles):
  - `slv_mode = ODVE_I2C_SLV_MEM`: `cfg.model.handle()` in the driver;
  - `slv_mode = ODVE_I2C_SLV_SEQ`: events go to `slv_sqr.req_fifo`; start
    `odve_i2c_slv_model_seq` (or your own) on `slv_sqr` and it answers.
  `t_timeout` (cycles, 0 = off) resets the target after SCL low that long (SMBus).
- `has_mon`: one monitor per bus (the TB's slave agent has none).
- Timing (clk cycles, default 1 cycle = 0.5 us of a 100 kHz bus): `t_low`,
  `t_high`, `t_hd_sta`, `t_su_sta`, `t_su_sto`, `t_buf`; monitor minima
  `min_t_low`, `min_t_high`, `min_t_hd_sta`, `min_t_su_sto`, `min_t_buf`.

The monitor (`mon`) publishes one `odve_i2c_item` per transfer on
`item_collected_port`; errors use the ids `I2C_BUS_ERR` (START/STOP inside a
byte, SDA ownership, ACKed last read byte) and `I2C_TIMING`; counters
`n_seen`, `n_bus_err`, `n_timing_err`, `n_aborted`, `n_stretched`.

## Testbench and plusargs

`+i2c_slave=dut` (default) puts the RTL target on the bus; `+i2c_slave=mem`
/ `+i2c_slave=seq` disconnect it and use the slave agent instead. The
scoreboard (`vrf/tb/env/scb.sv`) models the target independently and checks
every transfer the monitor reports.

```bash
cd odve/comp/agents/i2c/vrf/work/run
source sourceme
make aclean all run TESTNAME=i2c_rand_test                # ModelSim/Questa
make aclean all run TESTNAME=i2c_rand_test VERILATOR=1    # Verilator
./regress.py submit -j 2 -exer [-ropts="VERILATOR=1"] [-cov]
```

## Tests

| Test | What | Requirements |
| --- | --- | --- |
| `i2c_basic_test` | 7-bit writes, combined reads, current-address reads, pointer-only write | 001-006, 010 |
| `i2c_addr10_test` | 10-bit write / read / combined, mixed with 7-bit | 007 |
| `i2c_rand_test` | 60 random transfers, all kinds, 7/10-bit, 0..20 bytes, bad addresses/pointers | 001-008, 010 |
| `i2c_nack_test` | absent 7/10-bit addresses, header/low-byte mismatch, pointer NACK | 003, 007, 008 |
| `i2c_stretch_test` | CTRL stretching on, random traffic, then off | 011 |
| `i2c_gencall_test` | general call 06h reset, 04h NACK, START byte | 009 |
| `i2c_abort_test` | STOP inside data/address bytes, recovery | 013, 014 |

`submit.list`: all seven against the DUT, plus `basic/rand/nack/stretch`
with `+i2c_slave=mem` and `rand/addr10/gencall/stretch/abort` with
`+i2c_slave=seq` (16 runs). `mini.list`: `i2c_rand` (dut and seq).

## Known limitations

Single controller (no arbitration/clock synchronization), Standard-mode
timing only (scaled), no Hs/Fm+/UFm, no START-byte procedure, bus clear or
Device ID, general call 04h not supported by the target models. SMBus
Quick Command read works only when the target's first data bit is 1 (the
controller must STOP while the target already drives bit 7).
