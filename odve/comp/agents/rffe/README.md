# odve RFFE agent

UVM agent for the MIPI RF Front-End Control Interface (RFFE): a master that
owns SCLK and generates every command sequence, a slave (autonomous register
file or reactive, sequence-driven), and a monitor that rebuilds complete
sequences from the pins and checks the protocol. A synthesizable RTL RFFE
slave (`vrf/dut/dut.sv`) and a self-checking testbench verify both agent roles
against each other and against RTL, on ModelSim and Verilator.

- Protocol summary, sources and what is an assumption: [`doc/spec.md`](doc/spec.md)
  (the RFFE specification is MIPI members-only; public sources only).
- Requirements and traceability: [`doc/req.md`](doc/req.md).

## Layout

| Path | Contents |
| --- | --- |
| `intf/odve_rffe_if.sv` | `sclk`, resolved `sdata`, `m_sdata_o/oe` (master agent), `s_sdata_o/oe` (slave agent), `oe_all` (every SDATA enable, for the contention check) |
| `src/item/` | `odve_rffe_item` (kind, usid, addr, nbytes, data[], nrf_mask, parity injection, observed errors, half_speed) + `odve_rffe_kind_e` |
| `src/agent/` | `odve_rffe_cfg`, `odve_rffe_sqr`, `odve_rffe_slv_sqr`, `odve_rffe_agent`, `mon/`, `mst/`, `slv/`; package with the covergroup `odve_rffe_cg` |
| `seq/` | `odve_rffe_base_seq` (random, knobs), `odve_rffe_dir_seq` (directed `add`/`addw`), `odve_rffe_slv_mem_seq` (responder of the reactive slave) |
| `list/` | `agent.f`, `item.f`, `seq.f` |
| `vrf/dut/dut.sv` | RTL slave: `usid` input, 64 byte registers, all modelled commands, broadcast writes, NRF, parity handling; `sdata_i/sdata_o/sdata_oe` |
| `vrf/tb/` | `top.sv` (bus resolution + keeper, two RTL slaves USID 5 and A), `env/` (`cc`, `scb`, `env`), `tests/` |
| `vrf/work/` | `run/`, `mini/`, `check/`, `common/`, `rlist/{submit,mini,check}.list` |

## Agent

`cfg.role`:
- `ODVE_RFFE_MASTER` - sequencer + `odve_rffe_mst_drv_base`: SSC, frames with
  odd parity, bus park, read turnaround; writes read data and the NRF mask
  back into the item.
- `ODVE_RFFE_SLAVE` - `odve_rffe_slv_drv`, answering `cfg.usid` (and USID 0
  for writes), with `cfg.slv_mode`:
  - `ODVE_RFFE_SLV_MEM` - registers inside the driver (`cfg.nregs`).
  - `ODVE_RFFE_SLV_SEQ` - each decoded request goes to `slv_sqr.req_fifo`
    (instance `slv_req_fifo`); a responding sequence (`odve_rffe_slv_mem_seq`
    or your own) returns read data / NRF mask.

| cfg knob | Default | Meaning |
| --- | --- | --- |
| `has_mon` | 1 | build the monitor (one per bus) |
| `sclk_half` | 2 | TB clocks per SCLK half period (>= 2) |
| `idle_halfs` | 4 | idle half periods between sequences |
| `half_speed_read` | 0 | read data at half rate, sampled on the next rising edge |
| `usid` | 5 | slave: its USID |
| `nregs` | 64 | slave MEM mode: implemented registers |
| `chk_parity` | 1 | monitor: parity errors in master frames are `UVM_ERROR`s (clear when injecting) |

Item knobs for `user_randomize()` (via `` `odve_rand(item) ``, values from the
`odve_rand` stream `item.rng` the sequence hands over): `kind_mask`, `usids`,
`nregs`, `oor_pct`, `bcast_pct`, `inj_pct`. `inj_par_frame` (0 = command,
then address, then write data frames) makes the master invert that frame's
parity bit.

Monitor checks (`UVM_ERROR`): SDATA contention, data change at the sampling
edge, master frames not driven by the master alone, the master driving during
read data, parity errors (master frames: `chk_parity`; read data: always),
non-zero bus park, read to USID 0, unsupported command code, SSC inside a
sequence. Coverage `odve_rffe_cg`: kind, length, address class, broadcast,
parity error, NRF, half speed, write/read transitions, kind x parity error.

## Testbench

Two slaves on one bus: the primary (USID 5) is the RTL `dut_i` or the slave
agent, the secondary (USID A) is always the RTL `dut2_i`. The scoreboard
models both register files and checks every read data frame.

| Plusarg | Values |
| --- | --- |
| `+rffe_slave=` | `dut` (default), `mem` (slave agent, MEM mode), `seq` (slave agent, SEQ mode + `odve_rffe_slv_mem_seq`) |

## Running

```bash
cd odve/comp/agents/rffe/vrf/work/run
source sourceme
make all run TESTNAME=rand_test                 # ModelSim
make all run TESTNAME=rand_test VERILATOR=1     # Verilator
./regress.py submit -j 2 -exer                  # ModelSim regression
./regress.py submit -j 2 -exer -ropts="VERILATOR=1"
./regress.py submit -j 2 -cov -ropts="VERILATOR=1"   # + functional coverage
```

## Tests (`submit.list`)

| Run | Test | Slave | Requirements |
| --- | --- | --- | --- |
| rffe_reg | reg_test | dut | 010-012 |
| rffe_ext | ext_test | dut | 013, 014 |
| rffe_extl | extl_test | dut | 015, 016, 022 |
| rffe_bound / rffe_bound_mem | boundary_test | dut / mem | 012-017, 021, 022 |
| rffe_bcast / rffe_bcast_seq | bcast_test | dut / seq | 020 |
| rffe_par / rffe_par_mem / rffe_par_seq | par_err_test | dut / mem / seq | 004, 030-033 |
| rffe_nrf / rffe_nrf_mem | nrf_test | dut / mem | 022, 023 |
| rffe_hs / rffe_hs_seq | half_speed_test | dut / seq | 024 |
| rffe_rand / rffe_rand_mem / rffe_rand_seq | rand_test | dut / mem / seq | 018, 040, 041 |

Requirements 001-007 and 021 are checked in every run by the monitor and the
scoreboard. `mini.list`: `rffe_rand`.

## Known limitations

- Built from public sources only (spec members-only): command codes are the
  SPMI ones (Linux), parity-error and NRF handling, wrap-around, the read
  turnaround and broadcast rules are assumptions - see `doc/spec.md`.
- Single master; no multi-master / bus ownership, masked write, trigger
  registers, standard registers, interrupts.
- Cycle-level timing only (SCLK = TB clock / 4 by default); no analog timing.
- The read-to-broadcast check and the monitor's violation checks have no
  negative test (REQ-RFFE-025, -034).
