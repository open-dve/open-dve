# SPMI agent - requirements and traceability

Numbered requirements of the `spmi` agent, its RTL slave and testbench.
"Spec" points into `doc/spec.md` (sections and references S1..S7);
"assumption" means the behaviour is this model's choice where the public
sources were silent. "Verified by" names what runs in `submit`
(`vrf/work/rlist/submit.list`): tests, the monitor's protocol checks
(`src/agent/mon/odve_spmi_mon.sv`), the scoreboard (`vrf/tb/env/scb.sv`) and
coverpoints of `odve_spmi_cg`. The monitor's checks and the scoreboard run in
**every** submit test on every sequence; "all" means all 16 runs.

## Bus, frames, timing

| ID | Requirement | Spec | Verified by |
| --- | --- | --- | --- |
| REQ-SPMI-001 | SCLK is driven by the master only; SDATA has one driver at a time; every driver has its own output enable. | 2, S2, S4 | monitor: contention, "not driven by the master alone", master driving during read data / ACK - all |
| REQ-SPMI-002 | A sequence starts with an SSC: SDATA rises, then falls, while SCLK is low. | 3, S4, S7 | every sequence of all tests |
| REQ-SPMI-003 | Command frame = 4-bit SID, 8-bit command, parity (13 bits, MSB first); address/data frames = 8 bits + parity. | 3, S4, S5 | monitor decode + scoreboard - all; `cp_kind` |
| REQ-SPMI-004 | Every frame carries odd parity. | 3, S2 | monitor parity check silent on clean tests; `par_err_test` x3; `cp_perr` |
| REQ-SPMI-005 | Data is stable at the SCLK falling edge it is sampled at. | 2 (assumption) | monitor "SDATA changed at the SCLK falling edge" - all |
| REQ-SPMI-006 | A bus park cycle (0 while SCLK high, released at the falling edge) follows the master's last frame and the slave's last bit. | 3 (assumption) | monitor BPC checks - all |
| REQ-SPMI-007 | A read turns the bus around: master BPC, the slave's data frames (master not driving), slave BPC. | 3 (assumption) | monitor - every read; `reg_test`, `ext_test`, `extl_test` |
| REQ-SPMI-008 | Every non-read command ends with master BPC, one ACK/NACK bit driven by the addressed slave (1 = ACK), slave BPC. | 3, S2, S6 (timing/polarity assumption) | monitor (ACK cycle, driver check, NACK = error unless `chk_parity` is cleared); scoreboard ACK expectation - all; `cp_ack` |

## Command sequences

| ID | Requirement | Spec | Verified by |
| --- | --- | --- | --- |
| REQ-SPMI-010 | Register 0 Write (`1DDD_DDDD`) sets register 0 to `{0, D[6:0]}`, ACKed. | 4, S3, S5 | `reg_test`, `boundary_test`; scoreboard |
| REQ-SPMI-011 | Register Write (`010A_AAAA` + 1 data), ACKed. | 4, S3 | `reg_test` (all 32 registers of both slaves) |
| REQ-SPMI-012 | Register Read (`011A_AAAA`) returns one register. | 4, S3 | `reg_test`, `boundary_test` |
| REQ-SPMI-013 | Extended Register Write (`0000_BBBB`, 8-bit address, 1..16 bytes), ACKed. | 4, S2, S3 | `ext_test`, `boundary_test`; `cp_len` |
| REQ-SPMI-014 | Extended Register Read (`0010_BBBB`, 1..16 bytes). | 4, S3 | `ext_test`, `boundary_test` |
| REQ-SPMI-015 | Extended Register Write Long (`0011_0BBB`, 16-bit address, 1..8 bytes), ACKed. | 4, S2, S3 | `extl_test`, `boundary_test` |
| REQ-SPMI-016 | Extended Register Read Long (`0011_1BBB`, 1..8 bytes). | 4, S3 | `extl_test`, `boundary_test` |
| REQ-SPMI-017 | Multi-byte accesses address consecutive registers; extended addresses wrap at 8 bits, long at 16. | 4 (wrap assumption) | `boundary_test` (0xF8 + 16, 0xFFFC + 8) |
| REQ-SPMI-018 | Sequences may follow each other with no idle time beyond the bus park. | 3 | `rand_test` (`idle_halfs = 0`) on dut / mem / seq |

## Addressing and responses

| ID | Requirement | Spec | Verified by |
| --- | --- | --- | --- |
| REQ-SPMI-021 | A slave answers only its own SID: the second RTL slave (SID A) is on the bus in every test. | 4, S2 | scoreboard per-SID model - all |
| REQ-SPMI-022 | Reads of unimplemented registers (beyond 0x40), of absent SIDs or after a request the slave ignored return No Response Frames (nine zeros, not a parity error). | 5 (assumption) | `nrf_test` (spmi_nrf, spmi_nrf_seq), `extl_test`, `boundary_test`, `par_err_test`; scoreboard; `cp_nrf` |
| REQ-SPMI-023 | The master agent returns read data, NRF mask and the ACK bit to its sequence. | - | `nrf_test` (NRF, NACK on the master's items), `pm_test` (ACK on the master's items) |
| REQ-SPMI-024 | Every correctly received non-read command to a present SID is ACKed. | 3, S2 | scoreboard ACK check - all; `cp_ack.ack` |
| REQ-SPMI-025 | A write or PM command to an absent SID sees NACK (nobody drives the ACK bit). | 5, S6 | `nrf_test` (master items + scoreboard); `cp_ack.nack` |
| REQ-SPMI-026 | The slave's power state is readable at 0x40 (0 ACTIVE, 1 SLEEP, 2 SHUTDOWN), writes to it are ignored. | 4 (model-specific) | `pm_test`, `boundary_test` (burst over 0x40); scoreboard |

## Power management commands

| ID | Requirement | Spec | Verified by |
| --- | --- | --- | --- |
| REQ-SPMI-050 | Reset (`0x10`) clears the addressed slave's registers and sets ACTIVE. | 4, S2, S3 (effect: assumption) | `pm_test` x3 (registers read back as 0, state ACTIVE, the other slave untouched); scoreboard |
| REQ-SPMI-051 | Sleep (`0x11`) sets SLEEP. | 4, S3 | `pm_test` x3 |
| REQ-SPMI-052 | Shutdown (`0x12`) sets SHUTDOWN. | 4, S3 | `pm_test` x3 |
| REQ-SPMI-053 | Wakeup (`0x13`) sets ACTIVE. | 4, S3 | `pm_test` x3 |
| REQ-SPMI-054 | Every PM command to a present SID is ACKed; PM commands only affect the addressed slave. | 3, 4 | `pm_test` (master items + scoreboard), `rand_test`, `par_err_test` |

## Errors

| ID | Requirement | Spec | Verified by |
| --- | --- | --- | --- |
| REQ-SPMI-030 | A parity error in the command frame: the slave ignores the sequence (NACK seen / NRF). | 5 (assumption) | `par_err_test` x3 (every kind incl. PM): scoreboard ACK + model + reads |
| REQ-SPMI-031 | A parity error in an address frame: write dropped and NACKed; read ignored (NRF). | 5 (assumption) | `par_err_test` x3 |
| REQ-SPMI-032 | A parity error in a write data frame: it and the following frames dropped, earlier ones written, NACK. | 5 (assumption) | `par_err_test` x3 |
| REQ-SPMI-033 | The monitor detects every parity error in master frames (count equals the number injected). | 3 | `par_err_test`: `scb.exp_par_err` vs observed |
| REQ-SPMI-034 | The monitor reports contention, a data change at the sampling edge, a non-zero bus park, a wrong driver, an SSC inside a sequence and unsupported command codes. | 5 | **partially verified**: active and silent in every test; no submit test injects these violations |

## Not modelled

| ID | Requirement | Spec | Verified by |
| --- | --- | --- | --- |
| REQ-SPMI-060 | Bus arbitration between up to 4 masters and request-capable slaves. | S2, S4 | **not verified (not modelled)**: one master owns the bus |
| REQ-SPMI-061 | Authenticate, Master Read/Write, Transfer Bus Ownership, DDB reads, group SIDs. | S2, S3 | **not verified (not modelled)**: the RTL slave ignores the codes, the monitor reports them as unsupported |

## Agent roles, randomness, coverage

| ID | Requirement | Spec | Verified by |
| --- | --- | --- | --- |
| REQ-SPMI-040 | The slave agent in MEM mode behaves like the RTL slave (registers, power state, ACK/NACK). | - | `spmi_rand_mem`, `spmi_bound_mem`, `spmi_pm_mem`, `spmi_par_mem` |
| REQ-SPMI-041 | The slave agent in SEQ mode (requests to `odve_spmi_slv_mem_seq`) behaves like the RTL slave. | - | `spmi_rand_seq`, `spmi_pm_seq`, `spmi_par_seq`, `spmi_nrf_seq` |
| REQ-SPMI-042 | Values are random only through `odve_rand` streams. | odve rules | `rand_check.py odve/comp/agents/spmi` exit 0 |
| REQ-SPMI-070 | Functional coverage: `odve_spmi_cg` sampled once per complete sequence. | - | `./regress.py submit -cov` |

## Traceability: requirement -> submit runs

| Requirement | spmi_reg | spmi_ext | spmi_extl | spmi_bound(_mem) | spmi_pm(_mem/_seq) | spmi_par(_mem/_seq) | spmi_nrf(_seq) | spmi_rand(_mem/_seq) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 001-008 | x | x | x | x | x | x | x | x |
| 010-012 | x | | | x | x | x | | x |
| 013, 014 | | x | | x | x | x | x | x |
| 015, 016 | | | x | x | x | x | x | x |
| 017 | | | | x | | | | |
| 018 | | | | | | | | x |
| 021 | x | x | x | x | x | x | x | x |
| 022 | | x | x | x | | x | x | x |
| 023 | | | | | x | | x | |
| 024 | x | x | x | x | x | x | | x |
| 025 | | | | | | | x | |
| 026 | | | | x | x | | | x |
| 030-033 | | | | | | x | | |
| 034 | partial (silent checks in all) | | | | | | | |
| 040 | | | | x (_mem) | x (_mem) | x (_mem) | | x (_mem) |
| 041 | | | | | x (_seq) | x (_seq) | x (_seq) | x (_seq) |
| 050-054 | | | | | x | x | | x |
| 060, 061 | not verified (not modelled) | | | | | | | |

Summary: 39 requirements. 36 verified (34 by submit runs, REQ-SPMI-042 by
`rand_check.py`, REQ-SPMI-070 by the `-cov` regression), REQ-SPMI-034
partially (checks active but no deliberate violation), REQ-SPMI-060 and -061
not verified (not modelled).
