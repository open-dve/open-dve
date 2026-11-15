# odve SPMI agent

UVM agent for the MIPI System Power Management Interface (SPMI): a master
that owns SCLK and generates every command sequence (register, extended,
extended long accesses, Register 0 Write, Reset/Sleep/Shutdown/Wakeup), a
slave (autonomous register file + power state, or reactive, sequence-driven)
that answers with read data and ACK/NACK, and a monitor that rebuilds
complete sequences from the pins and checks the protocol. A synthesizable
RTL SPMI slave (`vrf/dut/dut.sv`) and a self-checking testbench verify both
agent roles against each other and against RTL, on ModelSim and Verilator.

- Protocol summary, sources and what is an assumption: [`doc/spec.md`](doc/spec.md)
  (the SPMI specification is MIPI members-only; public sources only).
- Requirements and traceability: [`doc/req.md`](doc/req.md).

## Layout

| Path | Contents |
| --- | --- |
| `intf/odve_spmi_if.sv` | `sclk`, resolved `sdata`, `m_sdata_o/oe` (master agent), `s_sdata_o/oe` (slave agent), `oe_all` (every SDATA enable, for the contention check) |
| `src/item/` | `odve_spmi_item` (kind, sid, addr, nbytes, data[], nrf_mask, ack, parity injection, observed errors) + `odve_spmi_kind_e` |
| `src/agent/` | `odve_spmi_cfg`, `odve_spmi_sqr`, `odve_spmi_slv_sqr`, `odve_spmi_agent`, `mon/`, `mst/`, `slv/`; package with `odve_spmi_pm_e` and the covergroup `odve_spmi_cg` |
| `seq/` | `odve_spmi_base_seq` (random, knobs), `odve_spmi_dir_seq` (directed `add`/`addw`), `odve_spmi_slv_mem_seq` (responder of the reactive slave) |
| `list/` | `agent.f`, `item.f`, `seq.f` |
| `vrf/dut/dut.sv` | RTL slave: `sid` input, 64 byte registers, power state at 0x40 (and port `pm_state`), all modelled commands, ACK/NACK, NRF, parity handling; `sdata_i/sdata_o/sdata_oe` |
| `vrf/tb/` | `top.sv` (bus resolution + keeper, two RTL slaves SID 5 and A), `env/` (`cc`, `scb`, `env`), `tests/` |
| `vrf/work/` | `run/`, `mini/`, `check/`, `common/`, `rlist/{submit,mini,check}.list` |

## Agent

`cfg.role`:
- `ODVE_SPMI_MASTER` - sequencer + `odve_spmi_mst_drv_base`: SSC, frames with
  odd parity, bus park, read turnaround, ACK/NACK cycle; writes read data,
  NRF mask and the ACK bit back into the item. No bus arbitration: it is the
  only master.
- `ODVE_SPMI_SLAVE` - `odve_spmi_slv_drv`, answering `cfg.sid`, with
  `cfg.slv_mode`:
  - `ODVE_SPMI_SLV_MEM` - registers and power state inside the driver.
  - `ODVE_SPMI_SLV_SEQ` - each decoded request goes to `slv_sqr.req_fifo`
    (instance `slv_req_fifo`); a responding sequence (`odve_spmi_slv_mem_seq`
    or your own) returns read data / NRF mask / `ack` (ANDed with the
    parity verdict).

| cfg knob | Default | Meaning |
| --- | --- | --- |
| `has_mon` | 1 | build the monitor (one per bus) |
| `sclk_half` | 2 | TB clocks per SCLK half period (>= 2) |
| `idle_halfs` | 4 | idle half periods between sequences |
| `sid` | 5 | slave: its SID |
| `nregs` | 64 | slave MEM mode: implemented registers; the power state sits at `nregs` |
| `chk_parity` | 1 | monitor: parity errors in master frames and NACKs are `UVM_ERROR`s (clear when injecting errors or addressing absent SIDs) |

Item knobs for `user_randomize()` (via `` `odve_rand(item) ``, values from the
`odve_rand` stream `item.rng`): `kind_mask` (11 bits, default the 7 register
commands), `sids`, `nregs`, `oor_pct`, `inj_pct`; `inj_par_frame` inverts one
frame's parity bit (0 = command, then address, then write data frames).

Monitor checks (`UVM_ERROR`): SDATA contention, data change at the sampling
edge, master frames not driven by the master alone, the master driving
during read data or the ACK bit, parity errors and NACK (`chk_parity`),
parity errors in read data (always), non-zero bus park, unsupported command,
SSC inside a sequence. Coverage `odve_spmi_cg`: kind (11), length, address
class (incl. the power-state register), parity error, ACK/NACK, NRF,
write/read transitions, kind x parity error.

## Testbench

Two slaves on one bus: the primary (SID 5) is the RTL `dut_i` or the slave
agent, the secondary (SID A) is always the RTL `dut2_i`. The scoreboard
models both slaves (registers + power state), checks every read data frame
and every ACK/NACK bit.

| Plusarg | Values |
| --- | --- |
| `+spmi_slave=` | `dut` (default), `mem` (slave agent, MEM mode), `seq` (slave agent, SEQ mode + `odve_spmi_slv_mem_seq`) |

## Running

```bash
cd odve/comp/agents/spmi/vrf/work/run
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
| spmi_reg | reg_test | dut | 010-012 |
| spmi_ext | ext_test | dut | 013, 014 |
| spmi_extl | extl_test | dut | 015, 016, 022 |
| spmi_bound / spmi_bound_mem | boundary_test | dut / mem | 012-017, 021, 022, 026 |
| spmi_pm / spmi_pm_mem / spmi_pm_seq | pm_test | dut / mem / seq | 023, 026, 050-054 |
| spmi_par / spmi_par_mem / spmi_par_seq | par_err_test | dut / mem / seq | 004, 030-033 |
| spmi_nrf / spmi_nrf_seq | nrf_test | dut / seq | 022, 023, 025 |
| spmi_rand / spmi_rand_mem / spmi_rand_seq | rand_test | dut / mem / seq | 018, 040, 041, 054 |

Requirements 001-008, 021 and 024 are checked in every run by the monitor and
the scoreboard. `mini.list`: `spmi_rand`.

## Known limitations

- Built from public sources only (spec members-only): ACK/NACK timing and
  polarity (1 = ACK), the bus park, which commands are ACKed, the PM
  commands' effect, parity-error and NRF handling are assumptions - see
  `doc/spec.md`.
- No bus arbitration (single master), no request-capable slaves, no
  Authenticate / Master Read/Write / Transfer Bus Ownership / DDB / group
  SIDs; the power state does not gate command acceptance.
- Cycle-level timing only (SCLK = TB clock / 4 by default).
- The monitor's violation checks have no negative test (REQ-SPMI-034).
