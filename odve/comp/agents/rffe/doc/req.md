# RFFE agent - requirements and traceability

Numbered requirements of the `rffe` agent, its RTL slave and testbench.
"Spec" points into `doc/spec.md` (sections and its references R1..R7);
"assumption" means the behaviour is this model's choice where the public
sources were silent. "Verified by" names what actually runs in `submit`
(`vrf/work/rlist/submit.list`): tests, the monitor's protocol checks
(`src/agent/mon/odve_rffe_mon.sv`), the scoreboard (`vrf/tb/env/scb.sv`) and
coverpoints of `odve_rffe_cg`.

The monitor's checks and the scoreboard run in **every** submit test, on
every sequence; "all" below means all 17 runs.

## Bus, frames, timing

| ID | Requirement | Spec | Verified by |
| --- | --- | --- | --- |
| REQ-RFFE-001 | SCLK is driven by the master only; SDATA has one driver at a time; every driver has its own output enable (no tristate resolution). | 2, R3 | monitor: contention check (`oe_all`), "frame not driven by the master alone", "master drives during a read data frame" - all |
| REQ-RFFE-002 | A sequence starts with an SSC: SDATA rises, then falls, while SCLK is low. The slaves (RTL and agent) and the monitor synchronise on it. | 3, R3 | every sequence of all tests (a missed SSC loses the sequence: the scoreboard's read checks fail) |
| REQ-RFFE-003 | Command frame = 4-bit USID, 8-bit command, parity, MSB first (13 bits). Address and data frames = 8 bits MSB first + parity. | 3, R3, R5 | monitor decode + scoreboard on all; `cp_kind` |
| REQ-RFFE-004 | Every frame carries odd parity. | 3, R3 | monitor parity check (`cfg.chk_parity`) silent on all clean tests; `par_err_test` (rffe_par, rffe_par_mem, rffe_par_seq); `cp_perr` |
| REQ-RFFE-005 | Data is stable at the SCLK falling edge it is sampled at (launched at the rising edge). | 2, R4; assumption for the launch edge | monitor "SDATA changed at the SCLK falling edge" - all |
| REQ-RFFE-006 | Every write sequence ends with a bus park cycle: the master drives 0 while SCLK is high and releases SDATA at the falling edge. | 3, R4 | monitor "master bus park cycle is not 0" - all |
| REQ-RFFE-007 | A read turns the bus around: master BPC after its last frame, the addressed slave drives the data frames, then the slave's BPC; the master does not drive during the slave's frames. | 3, R4; assumption for the slave BPC | monitor checks (turnaround, both BPCs) on all reads; `reg_test`, `ext_test`, `extl_test` |

## Command sequences

| ID | Requirement | Spec | Verified by |
| --- | --- | --- | --- |
| REQ-RFFE-010 | Register 0 Write (`1DDD_DDDD`) sets register 0 of the addressed slave(s) to `{0, D[6:0]}`. | 4.2, R5; bit 7 = 0 assumption | `reg_test`, `boundary_test` (0x00, 0x7F + read back); scoreboard; `cp_kind.reg0_wr` |
| REQ-RFFE-011 | Register Write (`010A_AAAA` + 1 data frame) writes one register at a 5-bit address. | 4.2, R5, R7 | `reg_test` (all 32 registers of both slaves); scoreboard |
| REQ-RFFE-012 | Register Read (`011A_AAAA`) returns one register. | 4.2, R4, R7 | `reg_test`, `boundary_test`; scoreboard read check |
| REQ-RFFE-013 | Extended Register Write (`0000_BBBB` + 8-bit address + BC+1 = 1..16 data frames). | 4.2, R2, R5 | `ext_test`, `boundary_test` (1 and 16 bytes); `cp_len` |
| REQ-RFFE-014 | Extended Register Read (`0010_BBBB`, 1..16 bytes). | 4.2, R2, R5 | `ext_test`, `boundary_test`; scoreboard |
| REQ-RFFE-015 | Extended Register Write Long (`0011_0BBB` + 16-bit address in two frames, MSB first, 1..8 bytes). | 4.2, R5, R7 | `extl_test`, `boundary_test` |
| REQ-RFFE-016 | Extended Register Read Long (`0011_1BBB`, 1..8 bytes). | 4.2, R2, R5 | `extl_test`, `boundary_test` |
| REQ-RFFE-017 | Multi-byte accesses address consecutive registers; extended addresses wrap at 8 bits, long ones at 16 bits. | 4.1, R6; wrap = assumption | `boundary_test` (0xF8 + 16 bytes, 0xFFFC + 8 bytes); scoreboard (`byte_addr`) |
| REQ-RFFE-018 | Sequences may follow each other with no idle time beyond the bus park. | 3 | `rand_test` (`idle_halfs = 0`) on dut / mem / seq |

## Addressing and responses

| ID | Requirement | Spec | Verified by |
| --- | --- | --- | --- |
| REQ-RFFE-020 | A write to the broadcast USID 0 is taken by every slave. | 4.1 (assumption) | `bcast_test` (rffe_bcast, rffe_bcast_seq): 50% broadcast writes of every kind, then reads of each slave; scoreboard; `cp_bcast` |
| REQ-RFFE-021 | A slave answers only its own USID (and 0 for writes): the second RTL slave (USID A) is on the bus in every test. | 4.1, R3 | scoreboard per-USID model, all tests |
| REQ-RFFE-022 | A read frame from an unimplemented register, an absent USID or after a request the slave ignored is a No Response Frame: all nine bits 0, not a parity error. | 5, R2, R3 | `nrf_test` (rffe_nrf, rffe_nrf_mem), `extl_test`, `boundary_test`, `par_err_test`; scoreboard NRF check; `cp_nrf` |
| REQ-RFFE-023 | The master agent returns the read data and the NRF mask of every read to its sequence. | - | `nrf_test` (checks the master's items) |
| REQ-RFFE-024 | Half-speed read: with `cfg.half_speed_read` the master clocks read data frames at half rate and samples on the next rising edge; slaves and monitor handle it, the monitor reports it. | 3, R4 | `half_speed_test` (rffe_hs, rffe_hs_seq): every read seen at half speed, data checked; `cp_half` |
| REQ-RFFE-025 | A read addressed to the broadcast USID 0 is ignored by the slaves and reported by the monitor. | 4.1 (assumption) | **not verified** - the master's sequences never generate it and no negative test exists; the RTL slave's `hit` term and the monitor check are in the code but unexercised |

## Errors

| ID | Requirement | Spec | Verified by |
| --- | --- | --- | --- |
| REQ-RFFE-030 | A parity error in the command frame makes the slave ignore the sequence (no write, reads answered by nobody = NRF). | 5 (assumption) | `par_err_test` x3 slaves: scoreboard model + read checks |
| REQ-RFFE-031 | A parity error in an address frame makes the slave ignore the sequence. | 5 (assumption) | `par_err_test` x3 |
| REQ-RFFE-032 | A parity error in a write data frame drops that frame and the following ones; earlier frames are written. | 5 (assumption) | `par_err_test` x3 |
| REQ-RFFE-033 | The monitor detects every parity error in master frames (count equals the number injected by the master driver). | 3 | `par_err_test`: `scb.exp_par_err` vs observed |
| REQ-RFFE-034 | The monitor reports contention, a data change at the sampling edge, a non-zero bus park, a wrong driver, an SSC inside a sequence and unsupported command codes. | 5 | **partially verified**: these checks run in every test and must stay silent (they caught real slave bugs during development - a missing slave BPC); no submit test injects these violations on purpose |

## Agent roles and modes

| ID | Requirement | Spec | Verified by |
| --- | --- | --- | --- |
| REQ-RFFE-040 | The slave agent in MEM mode (registers in the driver) behaves like the RTL slave. | - | `rffe_rand_mem`, `rffe_bound_mem`, `rffe_par_mem`, `rffe_nrf_mem`: the same scoreboard as against the RTL slave |
| REQ-RFFE-041 | The slave agent in SEQ mode (requests to a responding sequence, `odve_rffe_slv_mem_seq`) behaves like the RTL slave. | - | `rffe_rand_seq`, `rffe_bcast_seq`, `rffe_par_seq`, `rffe_hs_seq` |
| REQ-RFFE-042 | Values are random only through `odve_rand` streams (same values on both simulators for one seed). | odve rules | `rand_check.py odve/comp/agents/rffe` exit 0 (not a submit run) |
| REQ-RFFE-050 | Functional coverage: `odve_rffe_cg` sampled by the monitor once per complete sequence. | - | `./regress.py submit -cov` (see README for the figure) |

## Traceability: requirement -> submit runs

| Requirement | rffe_reg | rffe_ext | rffe_extl | rffe_bound(_mem) | rffe_bcast(_seq) | rffe_par(_mem/_seq) | rffe_nrf(_mem) | rffe_hs(_seq) | rffe_rand(_mem/_seq) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 001-007 | x | x | x | x | x | x | x | x | x |
| 010 | x | | | x | x | x | | x | x |
| 011, 012 | x | | | x | x | x | | x | x |
| 013, 014 | | x | | x | x | x | x | x | x |
| 015, 016 | | | x | x | x | x | x | x | x |
| 017 | | | | x | | | | | |
| 018 | | | | | | | | | x |
| 020 | | | | | x | | | | x |
| 021 | x | x | x | x | x | x | x | x | x |
| 022 | | x | x | x | | x | x | | x |
| 023 | | | | | | | x | | |
| 024 | | | | | | | | x | |
| 025 | not verified | | | | | | | | |
| 030-033 | | | | | | x | | | |
| 034 | partial (silent checks in all) | | | | | | | | |
| 040 | | | | x (_mem) | | x (_mem) | x (_mem) | | x (_mem) |
| 041 | | | | | x (_seq) | x (_seq) | | x (_seq) | x (_seq) |

Summary: 31 requirements. 29 verified (27 by submit runs, REQ-RFFE-042 by
`rand_check.py`, REQ-RFFE-050 by the `-cov` regression), REQ-RFFE-034
partially (checks active but no deliberate violation), REQ-RFFE-025 not
verified.
