# MDIO agent - verification requirements

References R1-R5 are those of [spec.md](spec.md) section 1 (R1, the IEEE
text, was not read: no requirement cites its section numbers). "submit"
means `vrf/work/rlist/submit.list`; every test named below runs in it, with
the slave variants listed in the traceability table.

Checker shorthands: **scb** = the scoreboard's reference model
(`odve_mdio_phy_model`: predicted answer / no answer, read data, writes
applied or ignored), **mon** = monitor protocol check (message ID), **dir** =
directed expectation in the test (`expect_rd`), **cov** = coverpoint of
`odve_mdio_cg`.

| ID | Requirement | Spec ref | Verified by |
|---|---|---|---|
| REQ-MDIO-001 | MDC is driven by the STA only; STA and PHY sample MDIO at the MDC rising edge. | R3, R4 | master driver owns `mdc`; mon decodes at rising edges; every test (a wrong edge breaks every scb check) |
| REQ-MDIO-002 | Each frame starts with a preamble of 32 ones; a PHY without preamble suppression ignores a frame preceded by fewer ones (read not answered, write not applied). | R2, R3 | `short_pre_test` (DUT, mem): scb + dir; mon `MDIO_PRE` counted by a report catcher (12 injected = 12 flagged); cov `cp_pre.pre_short` |
| REQ-MDIO-003 | A preamble of exactly 32 or more ones is accepted (idle ones count as preamble on the wire). | R2, R3 | `short_pre_test` (31 driven + 1 idle, 40), `rand_test` (long preambles), `b2b_test` (exactly 32): scb; cov `cp_pre.pre_std/pre_long` |
| REQ-MDIO-004 | Clause 22 frame: ST=01, OP=01 write / 10 read, 5-bit PHYAD, 5-bit REGAD, TA, 16 data bits, MSB first. | R2 | `c22_test`: scb + dir; cov `cp_kind.c22_wr/c22_rd` |
| REQ-MDIO-005 | Read turnaround: TA[1] driven by nobody (pulled up), TA[0] = 0 driven by the addressed PHY, which then drives the 16 data bits. | R2, R4 | mon `MDIO_TA`, `MDIO_RESP`, `MDIO_DIR` on every read of every test |
| REQ-MDIO-006 | Write-type turnaround is 10, driven by the STA; a write-type frame with another TA is flagged and not applied by the PHY. | R2, R4 | `proto_err_test` (DUT, seq): 9 bad-TA frames (11/00/01 on C22 write, C45 write, C45 address), mon `MDIO_TA` counted, scb + dir (registers unchanged) |
| REQ-MDIO-007 | A Clause 22 frame with an undefined opcode (00, 11) is flagged and ignored. | R2 (only 01/10 defined) | `proto_err_test`: mon `MDIO_OP` counted, dir (register unchanged); cov `cp_kind.c22_badop` |
| REQ-MDIO-008 | Clause 45 frame: ST=00, OP=00 address / 01 write / 11 read / 10 post-read-increment-address, PRTAD, DEVAD, TA, 16 bits. | R2, R5 | `c45_test`, `c45_rinc_test`: scb + dir; cov `cp_kind.c45_*` |
| REQ-MDIO-009 | Clause 45 write and read access the register selected by the last address frame of that port/MMD; each MMD has its own address register. | R2 | `c45_test` (both MMDs, interleaved), `rand_test`: scb; cov `cp_seq.addr_then_wr/addr_then_rd` |
| REQ-MDIO-010 | Post-read-increment-address returns the addressed register, then increments the address register (16-bit wrap FFFF -> 0000). | R2 | `c45_rinc_test` (16-register block read, read after the block, wrap): scb + dir; cov `cp_seq.addr_then_rinc/rinc_rinc` |
| REQ-MDIO-011 | A frame to a PHY/port address no PHY has, or to an MMD that is not present, gets no answer: the line stays pulled up (read data FFFF) and writes change nothing. | R3 (pull-up), R4 | `addr_miss_test` (DUT, multi), `rand_test` (15 % misses): scb (expects no answer and FFFF) + dir; cov `cp_resp.no_resp`, `x_rkind_resp` |
| REQ-MDIO-012 | The PHY drives read data after the MDC rising edge; MDIO is stable at least `t_su` (10 ns) before every rising edge, and STA-driven bits are held `t_hold` (10 ns) after it. | R3 | mon `MDIO_SETUP`, `MDIO_HOLD` on every bit of every test. No negative test: verified passively (a violation would fail the run) |
| REQ-MDIO-013 | At most one driver enables MDIO at a time; the PHY releases MDIO after the last data bit, and drives nothing outside the TA[0]+data of a read it answers. | R4 | mon `MDIO_CONT`, `MDIO_IDLE`, `MDIO_DIR`, `MDIO_RESP` on every frame of every test (a DUT that never releases was confirmed to fail `c22_test` with `MDIO_IDLE`) |
| REQ-MDIO-014 | Clause 22 standard registers: 0 control (RW, reset 0x1140), 1 status (RO 0x780D), 2/3 PHY identifier (RO); writes to 1-3 are ignored. | R2 (registers 0-3 exist; values are this model's) | `c22_test`: dir on reset values and after writing every register; scb |
| REQ-MDIO-015 | Clause 22 registers 4..31 are read/write storage. | model choice | `c22_test`, `rand_test`: scb; cov `cp_c22_reg.rw_lo/rw_hi` |
| REQ-MDIO-016 | Clause 45 MMDs 1 (PMA/PMD) and 3 (PCS) exist per port with: 0 control RW, 1 status RO, 2/3 device identifier RO, 5 devices in package RO (0x000A), RW window 0x8000..0x800F; any other address reads 0 and ignores writes. | R2 (MMD/64K space); values are this model's | `c45_test`: dir (ID) + scb; cov `cp_c45_dev` |
| REQ-MDIO-017 | Back-to-back frames (no idle cycle, the next preamble right after the last data bit, also after PHY-driven read data) work. | R2 (IDLE is not a minimum) | `b2b_test`: dir + scb + mon (contention); cov `cp_pre.pre_std` |
| REQ-MDIO-018 | Several PHYs at different addresses share one bus; each answers only its own address. | R2, R3 | `rand_test`/`addr_miss_test` with `+mdio_slave=multi` (RTL PHY at 1, agent at 2, 3), `c22_test` with `mem` (agent at 1, 2): scb |
| REQ-MDIO-019 | Agent master role (STA): generates every frame kind, preamble length, idle gap and error injection (TA, OP), and returns read data + answer flag. | - | every test (master on all runs); dir checks use the returned values |
| REQ-MDIO-020 | Agent slave role, autonomous mode (`ODVE_MDIO_SLV_MEM`): PHY/MMD register model in the driver, several addresses. | - | `mdio_c22_mem`, `mdio_short_pre_mem`, `mdio_rand_mem`, `mdio_rand_multi`, `mdio_miss_multi`: scb against the same model as the DUT runs |
| REQ-MDIO-021 | Agent slave role, reactive mode (`ODVE_MDIO_SLV_SEQ`): frames published to the slave sequencer, answered by a sequence. | - | `mdio_c45_rinc_seq`, `mdio_proto_err_seq`, `mdio_rand_seq`: scb |
| REQ-MDIO-022 | The monitor reconstructs every frame (kind, addresses, data, preamble length, TA, answered) and publishes it. | - | scb consumes only monitor items; every check above depends on it |
| REQ-MDIO-023 | Preamble suppression (frames with less than 32 preamble ones accepted, status bit 6 = 1). | R3 mentions it | **not verified** (not modelled: the DUT requires 32; spec.md section 7) |
| REQ-MDIO-024 | MDC period >= 400 ns, high/low times. | R3 | **not verified** (MDC is scaled to 80 ns for short simulations; no MDC timing check) |
| REQ-MDIO-025 | Clause 22 access to Clause 45 registers through registers 13/14. | R2 | **not verified** (not modelled: 13/14 are plain storage) |

Totals: 25 requirements, 22 verified in submit (012 only passively, no
violation injected), 3 not verified.

## Traceability: requirement -> submit runs

| Run (submit.list) | Test | Slave | Requirements |
|---|---|---|---|
| mdio_c22 | c22_test | dut | 001, 004, 005, 012, 013, 014, 015, 019, 022 |
| mdio_c45 | c45_test | dut | 001, 005, 008, 009, 011 (absent MMD), 012, 013, 016, 019, 022 |
| mdio_c45_rinc | c45_rinc_test | dut | 008, 009, 010, 012, 013 |
| mdio_addr_miss | addr_miss_test | dut | 011, 012, 013 |
| mdio_b2b | b2b_test | dut | 003, 013, 017 |
| mdio_short_pre | short_pre_test | dut | 002, 003 |
| mdio_proto_err | proto_err_test | dut | 006, 007 |
| mdio_rand | rand_test | dut | 003, 004, 008, 009, 011, 015 |
| mdio_c22_mem | c22_test | mem (1, 2) | 014, 018, 020 |
| mdio_c45_rinc_seq | c45_rinc_test | seq (1, 2) | 010, 021 |
| mdio_short_pre_mem | short_pre_test | mem | 002, 020 |
| mdio_proto_err_seq | proto_err_test | seq | 006, 007, 021 |
| mdio_rand_mem | rand_test | mem | 020 |
| mdio_rand_seq | rand_test | seq | 021 |
| mdio_rand_multi | rand_test | multi (dut 1 + agent 2, 3) | 018, 020 |
| mdio_miss_multi | addr_miss_test | multi | 011, 018 |
