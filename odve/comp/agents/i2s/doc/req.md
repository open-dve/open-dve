# I2S agent - verification requirements

Each requirement: statement, source (doc/spec.md references), and how it is
verified - the `submit` runs (`vrf/work/rlist/submit.list`, entry names),
the check that decides (scoreboard `scb`, monitor error ID) and the
coverpoint of `odve_i2s_cg` that records it. "all DUT runs" = every
`submit` entry without `+i2s_slave=agent`.

Scoreboard checks: **SCB-A** = every frame the transmitter agent's driver
sent is rebuilt identically, in order, by the port A monitor (transmitter
agent vs. monitor / receiver agent); **SCB-B** = every port A frame comes
out of the DUT on port B as the reference model predicts.

| ID | Requirement | Source | Verified by |
|---|---|---|---|
| REQ-I2S-001 | The bus has three lines SCK, WS, SD; the device generating SCK and WS is the controller, SD is driven by the transmitter; each line has exactly one driver at a time. | UM11732 3; spec.md 2 | monitor `I2S_CONTENTION` in every run (positive only: contention is never injected) |
| REQ-I2S-002 | Serial data is two's complement, MSB first. | UM11732 3.1 | SCB-A and SCB-B in every run; `i2s_corner_*` (sign boundaries); `cp_val` |
| REQ-I2S-003 | The transmitter changes SD (and the controller WS) on the falling SCK edge; the receiver latches SD and WS on the rising edge. | UM11732 3.1, 3.2 | drivers by construction; monitor and DUT sample on the rising edge, so SCB-A/SCB-B fail otherwise; set-up check REQ-I2S-014 |
| REQ-I2S-004 | I2S: WS = 0 carries channel 1 (left), WS = 1 channel 2 (right). | UM11732 3.2 | monitor `I2S_WS` (expected WS per position); SCB-B (the DUT swaps channels, so a left/right mix-up mismatches) in `i2s_std_*`, `i2s_tgt_std`, `i2s_dut_clk`; `cp_fmt.i2s` |
| REQ-I2S-005 | I2S: WS changes one SCK period before the MSB; the MSB of a word is sent one period after the WS change. | UM11732 3.1, 3.2, Figure 1 | SCB-A/SCB-B with the monitor/DUT data window at frame position 1 (`i2s_std_*`, `i2s_tgt_std`, `i2s_loop_*`); `cp_fmt.i2s` |
| REQ-I2S-006 | Word lengths 16, 24 and 32 bits in slots of 16 or 32 SCK periods; MSB at a fixed position, bits after the LSB are 0. | UM11732 3.1 | `i2s_std_w16`, `_w16s32`, `_w24`, `_w32`, `i2s_lj_w16`, `i2s_rj_w16s32`, `i2s_rj_w32`, `i2s_tdm*`; monitor `I2S_PAD`; `cp_wlen`, `cp_slen`, `x_fmt_wlen` |
| REQ-I2S-007 | A receiver with a longer word zero-fills the missing LSBs; with a shorter word it ignores the bits after its LSB. | UM11732 3.1 | **not verified** (transmitter, receiver and DUT always use the same word length; spec.md 7) |
| REQ-I2S-008 | Clock role is independent of direction: a transmitter or a receiver can be controller or target (all four agent shapes). | UM11732 2, Figure 1 | TX controller + RX target: default runs; TX target + RX controller: `i2s_tgt_*`, `i2s_loop_rxc*`; DUT controller of both ports: `i2s_dut_clk`; agents controllers of both ports: `i2s_agt_clk`; `cp_role`, `x_fmt_role` |
| REQ-I2S-009 | A target derives the frame timing from WS latched on the rising edge and transmits/receives in step with the controller (incl. LJ/RJ, where the first bit shares the period of the WS change). | UM11732 3.2 | SCB-A (agent transmitter as target, `i2s_tgt_*`, `i2s_loop_rxc*`); SCB-B (DUT receiver/transmitter as target, default runs and `i2s_tgt_*`) |
| REQ-I2S-010 | The frame length is constant (slots x slot length); a frame start after a different number of SCK periods is a protocol error reported by the monitor. | spec.md 4, 6 (derived: WS changes at fixed positions, UM11732 3.2) | `i2s_ws_shift`, `i2s_ws_shift_lj` (controller ends one frame one period early): `I2S_FRAME` must be reported (test fails otherwise); `cp_err.frame_len` |
| REQ-I2S-011 | WS at a level its frame position does not allow (glitch) is a protocol error reported by the monitor. | spec.md 6 (derived from UM11732 3.2) | `i2s_ws_glitch`, `i2s_ws_glitch_tdm`: `I2S_WS` must be reported; `cp_err.ws_glitch` |
| REQ-I2S-012 | After a WS/frame error the monitor and the DUT receiver resynchronise on the next frame start; following frames are received intact. | spec.md 6 | `i2s_ws_*` runs: >= frames-3 intact frames on port A and through the DUT on port B, monitor keeps rebuilding frames |
| REQ-I2S-013 | SCK HIGH and LOW each last >= 0.35 T. | UM11732 Table 3, Figures 2-3 | monitor `I2S_TIMING` on every SCK period of every run (agent and DUT controllers); positive only - a bad duty cycle is never injected |
| REQ-I2S-014 | SD and WS are stable >= 0.2 T (tsr) before the rising SCK edge. | UM11732 Table 3, Figure 3 | monitor `I2S_TIMING` in every run; negative: `i2s_timing_err` (T = 80 ns, DUT target transmitter too slow) must report it |
| REQ-I2S-015 | Left-justified format: WS high = left, MSB in the SCK period of the WS change. | MCHP 51.5.12.5; spec.md 3.3 | `i2s_lj`, `i2s_lj_w16`, `i2s_tgt_lj`, `i2s_tgt_gen`, `i2s_loop_rxc_lj`, `i2s_mono_lj`, `i2s_ws_shift_lj` with SCB-A/SCB-B, `I2S_WS`; `cp_fmt.lj` |
| REQ-I2S-016 | Right-justified format: LSB in the last SCK period of the slot, zeros before the MSB. | MCHP 51.5.12.5; spec.md 3.3 | `i2s_rj`, `i2s_rj_w16s32`, `i2s_rj_w32`, `i2s_tgt_rj`, `i2s_corner_w24` with SCB-A/SCB-B, `I2S_PAD`; `cp_fmt.rj` |
| REQ-I2S-017 | TDM: one-SCK frame-sync pulse on WS, MSB of slot 0 one SCK later, slots back to back; 2, 4 and 8 slots. | MCHP 51.5.12.5; spec.md 3.4 | `i2s_tdm4`, `i2s_tdm8_w16`, `i2s_tdm2_w32`, `i2s_tgt_tdm8`, `i2s_agt_clk`, `i2s_loop_rxc_tdm`, `i2s_corner_w32`, `i2s_ws_glitch_tdm`; `cp_fmt.tdm`, `cp_slots` |
| REQ-I2S-018 | Mono: both channels carry the same sample; the monitor reports a mono frame with left != right. | spec.md 3.5 (TB convention) | `i2s_mono`, `i2s_mono_lj`: `I2S_MONO` + SCB-A/SCB-B; `cp_mono` (negative case not injected) |
| REQ-I2S-019 | Frames are sent back-to-back, or with idle (all-zero) frames between them; the receiving side neither loses nor duplicates frames. | spec.md 7 | back-to-back: every `submit` run with the default sequence; gaps: `i2s_gap`, `i2s_tgt_gap`; SCB-A/SCB-B in-order checks with "never received" check at the end |
| REQ-I2S-020 | The transmitter agent can source frames autonomously (no sequence) as well as from a sequence. | agent feature | `i2s_gen`, `i2s_tgt_gen`: SCB-A/SCB-B on the generated frames |
| REQ-I2S-021 | DUT: output slot k = -(input slot k^1) in word-length two's complement, -full scale saturating to +full scale. | vrf/dut/dut.sv | SCB-B in all DUT runs; saturation: `i2s_corner_*` (`cp_val.neg_min`) |
| REQ-I2S-022 | DUT receiver and transmitter each work as clock controller and as clock target. | UM11732 2 | receiver target: default runs; receiver controller: `i2s_tgt_*`, `i2s_dut_clk`; transmitter controller: default runs, `i2s_dut_clk`; transmitter target: `i2s_tgt_*`, `i2s_agt_clk`, `i2s_timing_err` (SCB-B) |
| REQ-I2S-023 | SD and WS are never X/Z at a sampling edge. | spec.md 6 | monitor `I2S_X` in every run (positive only: X is never injected) |
| REQ-I2S-024 | Transmitter delay tdtr <= 0.8 T, transmitter hold thtr >= 0, receiver hold thr >= 0, clock rise time tRC <= 0.15 Ttr. | UM11732 Table 3, Figure 4 | **not verified** (zero-time edges; tdtr is implied by REQ-I2S-014 for a 50 % clock, but not checked on its own) |
| REQ-I2S-025 | Output/input voltage levels. | UM11732 5 | **not verified** (logic-level model) |
| REQ-I2S-026 | MCLK as the system clock of the devices. | spec.md 2 | **not verified** (MCLK is a free-running signal on the interface, unused) |

Summary: 26 requirements; 22 verified by `submit` runs (REQ-I2S-001, -013,
-018 and -023 only in the passing direction: the violation is never
injected), 4 not verified (REQ-I2S-007, -024, -025, -026).

## Traceability: requirement -> submit runs

| Requirement | Runs |
|---|---|
| REQ-I2S-001 | all |
| REQ-I2S-002 | all; `i2s_corner_w16`, `i2s_corner_w24`, `i2s_corner_w32` |
| REQ-I2S-003 | all |
| REQ-I2S-004 | `i2s_std_w16`, `i2s_std_w16s32`, `i2s_std_w24`, `i2s_std_w32`, `i2s_tgt_std`, `i2s_dut_clk`, `i2s_mono`, `i2s_gap`, `i2s_gen` |
| REQ-I2S-005 | `i2s_std_*`, `i2s_tgt_std`, `i2s_dut_clk`, `i2s_loop_txc`, `i2s_loop_rxc` |
| REQ-I2S-006 | `i2s_std_w16`, `i2s_std_w16s32`, `i2s_std_w24`, `i2s_std_w32`, `i2s_lj_w16`, `i2s_tgt_lj`, `i2s_rj_w16s32`, `i2s_rj_w32`, `i2s_tdm4`, `i2s_tdm8_w16`, `i2s_tdm2_w32` |
| REQ-I2S-007 | - (not verified) |
| REQ-I2S-008 | default runs; `i2s_tgt_std`, `i2s_tgt_lj`, `i2s_tgt_rj`, `i2s_tgt_tdm8`, `i2s_tgt_gap`, `i2s_tgt_gen`, `i2s_dut_clk`, `i2s_agt_clk`, `i2s_loop_txc`, `i2s_loop_rxc`, `i2s_loop_rxc_lj`, `i2s_loop_rxc_tdm` |
| REQ-I2S-009 | `i2s_tgt_*`, `i2s_loop_rxc*`, `i2s_agt_clk`, default runs (DUT receiver target) |
| REQ-I2S-010 | `i2s_ws_shift`, `i2s_ws_shift_lj` |
| REQ-I2S-011 | `i2s_ws_glitch`, `i2s_ws_glitch_tdm` |
| REQ-I2S-012 | `i2s_ws_glitch`, `i2s_ws_glitch_tdm`, `i2s_ws_shift`, `i2s_ws_shift_lj` |
| REQ-I2S-013 | all |
| REQ-I2S-014 | all; `i2s_timing_err` (negative) |
| REQ-I2S-015 | `i2s_lj`, `i2s_lj_w16`, `i2s_tgt_lj`, `i2s_tgt_gen`, `i2s_loop_rxc_lj`, `i2s_mono_lj`, `i2s_ws_shift_lj` |
| REQ-I2S-016 | `i2s_rj`, `i2s_rj_w16s32`, `i2s_rj_w32`, `i2s_tgt_rj`, `i2s_corner_w24` |
| REQ-I2S-017 | `i2s_tdm4`, `i2s_tdm8_w16`, `i2s_tdm2_w32`, `i2s_tgt_tdm8`, `i2s_agt_clk`, `i2s_loop_rxc_tdm`, `i2s_corner_w32`, `i2s_ws_glitch_tdm` |
| REQ-I2S-018 | `i2s_mono`, `i2s_mono_lj` |
| REQ-I2S-019 | all (back-to-back); `i2s_gap`, `i2s_tgt_gap` |
| REQ-I2S-020 | `i2s_gen`, `i2s_tgt_gen` |
| REQ-I2S-021 | all DUT runs; `i2s_corner_*` |
| REQ-I2S-022 | default runs, `i2s_tgt_*`, `i2s_dut_clk`, `i2s_agt_clk`, `i2s_timing_err` |
| REQ-I2S-023 | all |
| REQ-I2S-024 | - (not verified) |
| REQ-I2S-025 | - (not verified) |
| REQ-I2S-026 | - (not verified) |
