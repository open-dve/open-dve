# JTAG agent - requirements

Requirements of the odve `jtag` agent and its testbench, traced to the
protocol summary (`doc/spec.md`, which cites the public sources R1-R6 - the
IEEE 1149.1 text itself was not available) and to what verifies them in the
`submit` regression (`vrf/work/rlist/submit.list`). "Every run" means every
entry of `submit`, on all target variants (`+jtag_slave=dut|chain|mem|seq`).

Verification mechanisms:

- **SCB** - `vrf/tb/env/scb.sv`: a model of the TAP chain (one
  `odve_jtag_tap_model` per TAP) that recomputes every bit shifted out of
  every IR/DR scan the monitor reports and applies every update; any
  difference is a `SCB_TDO` UVM_ERROR. Fails a run with no scan at all.
- **MON** - protocol checks in `odve_jtag_mon` (UVM_ERROR ids `JTAG_X`,
  `JTAG_OE`, `JTAG_IRCAP`, `JTAG_LEN`), active in every run.
- **TEST** - explicit `expect_ok(...)` checks in the test (`TEST` errors).
- **COV** - coverpoints of `odve_jtag_cg` / `odve_jtag_fsm_cg` (FCOV=1).

## Requirements

**REQ-JTAG-001** The TAP controller has the 16 states and moves between
them on the TMS level at each rising TCK, per the transition table.
Spec: spec.md "TAP controller" (R2, R3, R4). Verified: `goto_test`
(`jtag_goto`, `jtag_goto_mem`) walks to all 16 states and 40 random ones;
after each move the master's copy, the monitor's, the RTL DUT's
(`dbg_state`) or the slave agent's state must equal the target (TEST);
every scan in every run only checks clean if the DUT/model and the monitor
agree on the states (SCB). COV `odve_jtag_fsm_cg.cp_state`, `cp_arc`.

**REQ-JTAG-002** Five or more TCKs with TMS=1 bring the TAP to
Test-Logic-Reset from any state. Spec: "TAP controller" (R2, R3). Verified:
`reset_test` (`jtag_reset`, `jtag_reset_seq`) from each of the 16 states,
then reads IDCODE (TEST, SCB); the master driver also errors if its own copy
is not in TLR after the sequence. COV `cp_trst.tms`.

**REQ-JTAG-003** TRST_n low resets the TAP asynchronously to
Test-Logic-Reset, also in the middle of a scan; the interrupted scan updates
nothing. Spec: "Signals", "Error / abnormal conditions" (R2). Verified:
`reset_test` (TRST_n from random states and from Shift-DR), `idcode_test`
(all variants); the monitor drops the cut scan and reports a reset (SCB
model stays consistent). COV `cp_trst.trst`.

**REQ-JTAG-004** Power-on reset and Test-Logic-Reset select IDCODE.
Spec: "Instructions" (R5, R6). Verified: `idcode_test` reads the IDCODE
without an IR scan after power-on, after a TMS reset and after TRST_n
(TEST, SCB); `reset_test` after every reset.

**REQ-JTAG-005** IDCODE is a 32-bit read-only register with bit 0 = 1 and
the TAP's value (TAP k: `32'h1234_5679 + k * 32'h1000_0000`). Spec:
"Instructions" (R5). Verified: `idcode_test` on `dut`, `mem`, `seq`, `chain`
(both TAPs' IDs in a 64-bit scan) (TEST, SCB); `chain_test`.

**REQ-JTAG-006** BYPASS (all-ones opcode) selects a 1-bit register that
captures 0: a DR scan comes back delayed by one bit per TAP. Spec:
"Instructions" (R2, R5). Verified: `bypass_test` (`jtag_bypass`,
`jtag_bypass_chain`: 2-bit delay) with random lengths 1..64 (TEST, SCB);
`chain_test`. COV `cp_instr.bypass`.

**REQ-JTAG-007** Every opcode without an assigned register selects BYPASS.
Spec: "Instructions". Verified: `bypass_test` (0011, 0101, 1001, 1110),
`rand_test` (random unassigned opcodes) (TEST, SCB). COV `cp_instr.unassigned`.

**REQ-JTAG-008** EXTEST and SAMPLE/PRELOAD are present: both select the
8-bit boundary register, which captures the pins and latches the shifted
value at Update-DR. Spec: "Instructions" (R2, R4). Verified: `bsr_test`
(`jtag_bsr`, `jtag_bsr_mem`) checks the captured pins (TEST) and every bit
(SCB). The `pins_o` drive under EXTEST is **not verified** (no checker
observes the DUT's `pins_o`). COV `cp_instr.extest`, `cp_instr.sample`.

**REQ-JTAG-009** USERDATA is a 32-bit read/write register: a DR scan
returns the current value and Update-DR stores the shifted value; scans
may follow each other with no Run-Test/Idle cycle in between. Spec:
"Instructions". Verified: `user_test` (`jtag_user`, `_mem`, `_seq`)
12 back-to-back writes incl. all-ones/all-zeros, each read checked (TEST,
SCB). COV `cp_instr.user`, `cp_idle.b2b`.

**REQ-JTAG-010** USERDATA keeps its value over a TMS reset and is cleared
by TRST_n and power-on reset. Spec: "Instructions" (model choice).
Verified: `reset_test`, `user_test` (TEST, SCB).

**REQ-JTAG-011** Capture-IR loads a pattern whose two LSBs are 01; the
monitor flags an IR scan whose first two bits out are not 1, 0. Spec:
"Scans and timing" (R3, common knowledge). Verified: MON `JTAG_IRCAP` on
every IR scan of every run; `chain_test` checks the 8-bit chain capture
0x11 (TEST); `err_test` with `+jtag_err=ircap` (`jtag_err_ircap`) injects
0000 in the slave agent and requires the monitor to report it.

**REQ-JTAG-012** IR and DR scans have any length from 0 to
`ODVE_JTAG_MAX_LEN-1` (255) bits: shorter than the register keeps part of
the capture, longer passes TDI through. Spec: "Scans and timing".
Verified: `len_test` (`jtag_len`, `jtag_len_seq`): IR 0..9 bits, DR 0, 1, 2,
31, 32, 33, 64, 100, 255 bits (SCB); `rand_test` 0..80 bits. COV `cp_len`.
A scan longer than 256 bits is flagged by MON `JTAG_LEN` (not exercised).

**REQ-JTAG-013** A scan can stop in Pause-IR/Pause-DR for any number of
TCKs and resume through Exit2 -> Shift, or end through Exit2 -> Update,
without changing the shifted data. Spec: "Scans and timing" (R2).
Verified: `pause_test` (`jtag_pause`, `jtag_pause_mem`) pauses DR scans
after bit 1, 5, 16, len-1, len (Exit2 -> Update) and an IR scan before and
at its end (TEST, SCB); `rand_test`. The master pauses a scan at most
once; scans with several pauses are not generated (the monitor would count
them). COV `cp_pause`, `x_kind_pause`,
`cp_arc.resume_dr/resume_ir/ex2_upd_dr/ex2_upd_ir`.

**REQ-JTAG-014** The host can run any number of TCKs in Run-Test/Idle
between operations; the monitor counts them. Spec: "TAP controller".
Verified: idle cycles in `idcode_test`, `user_test`, `bsr_test`,
`rand_test` (IDLE operations); COV `cp_idle`.

**REQ-JTAG-015** TMS and TDI change at the falling TCK and are sampled at
the rising TCK; TDO changes at the falling TCK and is sampled by host and
monitor at the rising TCK. Spec: "Signals", "Scans and timing" (R2, R3,
R4). Verified: by construction of master driver, slave driver and RTL
(`always_ff @(negedge tck)` for TDO), checked end to end by SCB in every
run (a TDO sampled at the wrong edge shifts every scan by a bit).

**REQ-JTAG-016** TDO is enabled exactly in Shift-IR and Shift-DR (3-state
otherwise, read as 1 on the bus). Spec: "Signals" (R4). Verified: MON
`JTAG_OE` in every run; `err_test` with `+jtag_err=oe` (`jtag_err_oe`)
injects an always-on enable and requires the monitor to report it.

**REQ-JTAG-017** In a daisy chain the IR scan is the concatenation of all
IRs and the DR scan the concatenation of the selected registers, the TAP
nearest TDO first out. Spec: "Daisy chain". Verified: `chain_test`
(IDCODE+IDCODE 64 bits, BYPASS+BYPASS, USERDATA+BYPASS both ways, values
kept per TAP) (TEST, SCB); `idcode_test`, `bypass_test`, `rand_test` on
`+jtag_slave=chain`.

**REQ-JTAG-018** The master agent (JTAG host) offers reset (TMS or TRST_n),
goto-state, IR scan, DR scan (with optional pause) and idle-cycle
operations, returning the bits shifted out. Spec: "TAP controller",
"Scans and timing". Verified: used by every test; results checked by TEST
and SCB.

**REQ-JTAG-019** The slave agent is a behavioural TAP with IDCODE, BYPASS,
USERDATA and boundary registers, autonomous (`SLV_MEM`) or with its data
registers in a responding sequence (`SLV_SEQ`), and behaves like the RTL
TAP. Verified: `*_mem` and `*_seq` entries of `submit` run the same tests
against the same scoreboard model as the RTL (SCB, TEST, MON).

**REQ-JTAG-020** The monitor reconstructs every reset and every scan from
the pins alone - TAP state from TMS, captured value (bits out), updated
value (bits in), pauses, idle cycles - and publishes it. Verified: every
run (SCB checks every published scan; fails a run without scans); `goto_test`
compares the monitor's state.

**REQ-JTAG-021** The monitor flags unknown TMS at a rising TCK and unknown
TDI/TDO while shifting (`JTAG_X`). Verified: active in every run (no false
reports); **the failing path is not verified** (no X injection test).

**REQ-JTAG-022** All random values come from `odve_rand` streams (same
values for the same `+SEED` on both simulators); no `rand`, `randomize()`,
`$urandom`, `$random`. Verified: `script/rand/rand_check.py
odve/comp/agents/jtag` exits 0 (static check, not a simulation).

## Traceability

| Requirement | Tests (submit entries) | Mechanism |
|-------------|------------------------|-----------|
| REQ-JTAG-001 | jtag_goto, jtag_goto_mem; all | TEST, SCB, COV |
| REQ-JTAG-002 | jtag_reset, jtag_reset_seq, jtag_idcode* | TEST, SCB, COV |
| REQ-JTAG-003 | jtag_reset, jtag_reset_seq, jtag_idcode* , jtag_rand* | TEST, SCB, COV |
| REQ-JTAG-004 | jtag_idcode, _mem, _seq, _chain; jtag_reset* | TEST, SCB |
| REQ-JTAG-005 | jtag_idcode, _mem, _seq, _chain; jtag_chain | TEST, SCB |
| REQ-JTAG-006 | jtag_bypass, jtag_bypass_chain, jtag_chain | TEST, SCB, COV |
| REQ-JTAG-007 | jtag_bypass, jtag_bypass_chain, jtag_rand* | TEST, SCB, COV |
| REQ-JTAG-008 | jtag_bsr, jtag_bsr_mem (pins_o not verified) | TEST, SCB, COV |
| REQ-JTAG-009 | jtag_user, _mem, _seq | TEST, SCB, COV |
| REQ-JTAG-010 | jtag_reset, jtag_reset_seq, jtag_user* | TEST, SCB |
| REQ-JTAG-011 | all (MON); jtag_chain; jtag_err_ircap | MON, TEST |
| REQ-JTAG-012 | jtag_len, jtag_len_seq, jtag_rand* | SCB, COV |
| REQ-JTAG-013 | jtag_pause, jtag_pause_mem, jtag_rand* | TEST, SCB, COV |
| REQ-JTAG-014 | jtag_idcode*, jtag_user*, jtag_bsr*, jtag_rand* | SCB, COV |
| REQ-JTAG-015 | all | SCB |
| REQ-JTAG-016 | all (MON); jtag_err_oe | MON |
| REQ-JTAG-017 | jtag_chain, jtag_idcode_chain, jtag_bypass_chain, jtag_rand_chain | TEST, SCB |
| REQ-JTAG-018 | all | TEST, SCB |
| REQ-JTAG-019 | all *_mem, *_seq | TEST, SCB, MON |
| REQ-JTAG-020 | all | SCB |
| REQ-JTAG-021 | all (positive only; failing path not verified) | MON |
| REQ-JTAG-022 | - (rand_check.py) | static |

22 requirements: 20 fully verified in `submit`; REQ-JTAG-008 partly (the
`pins_o` drive under EXTEST is not checked), REQ-JTAG-021 only in the
positive sense; REQ-JTAG-022 by the static checker.
