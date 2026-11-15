# odve I2S agent

UVM agent for the I2S (Inter-IC Sound) serial audio bus - Philips/NXP I2S,
left-justified, right-justified and TDM/DSP frames - with a standalone
verification environment around an RTL I2S receive -> process -> transmit
pipeline. Protocol summary and sources: [doc/spec.md](doc/spec.md);
requirements and their traceability to tests: [doc/req.md](doc/req.md).

## What the agent does

One agent instance = one device on one bus, with two independent choices
(UM11732 section 2):

| `cfg.dir` | `cfg.clk_role` | driver | what it drives |
|---|---|---|---|
| `ODVE_I2S_TX` | `ODVE_I2S_CLK_MASTER` (controller) | `mst/odve_i2s_mst_drv` | SCK, WS, SD |
| `ODVE_I2S_TX` | `ODVE_I2S_CLK_SLAVE` (target) | `slv/odve_i2s_slv_drv` | SD, framed by the WS it receives |
| `ODVE_I2S_RX` | `ODVE_I2S_CLK_MASTER` | `mst/odve_i2s_mst_drv` | SCK, WS |
| `ODVE_I2S_RX` | `ODVE_I2S_CLK_SLAVE` | `slv/odve_i2s_slv_drv` | nothing (the monitor receives) |

A transmitter takes its frames from the sequencer (`cfg.src =
ODVE_I2S_SRC_SEQ`, `try_next_item` at each frame start, an idle all-zero
frame when nothing is pending, `item.gap` idle frames before an item) or
generates `cfg.gen_frames` frames itself (`ODVE_I2S_SRC_GEN`, the
autonomous counterpart of apb's `SLV_MEM`). Every frame it puts on the bus
is published on `drv.sent_port`.

The monitor (`mon/odve_i2s_mon`) rebuilds every frame from the pins
(rising-edge sampling), publishes it on `item_collected_port`, samples the
covergroup `odve_i2s_cg` (in `odve_i2s_agent_pkg`, `ifdef ODVE_COV_NATIVE`)
and reports protocol errors: `I2S_WS` (WS glitch / misaligned),
`I2S_FRAME` (frame length), `I2S_X`, `I2S_PAD`, `I2S_MONO`, `I2S_TIMING`
(SCK duty >= 0.35T, SD/WS set-up >= 0.2T), `I2S_CONTENTION`.

## Layout

```
intf/odve_i2s_if.sv            sck/ws/sd (resolved), a_* (agent drive + enables), d_* (DUT drive), mclk
src/item/                      odve_i2s_item (one frame: n_slots samples), enums (format, value kinds)
src/agent/odve_i2s_cfg.sv      knobs below + frame geometry (ws_of, delay, offset, sd_of)
src/agent/odve_i2s_drv_base.sv common TX logic (frame load, SD per position, sent_port)
src/agent/mst/ slv/ mon/       controller driver, target driver, monitor
src/agent/odve_i2s_agent*.sv   agent, package (enums + covergroup)
seq/                           base/frame/corner/gap sequences
list/                          agent.f, item.f, seq.f
doc/                           spec.md, req.md
vrf/                           DUT, TB, tests, work dirs
```

## cfg knobs (`odve_i2s_cfg`)

| Knob | Default | Meaning |
|---|---|---|
| `dir`, `clk_role`, `src` | TX, MASTER, SEQ | see above |
| `fmt` | `ODVE_I2S_FMT_I2S` | `I2S`, `LJ`, `RJ`, `TDM` |
| `word_len` / `slot_len` / `n_slots` | 16 / 32 / 2 | 16, 24, 32 / 16, 32 / 2 (I2S/LJ/RJ), 2..8 (TDM) |
| `mono` | 0 | left == right (stereo formats) |
| `sck_half_ns` | 80 | controller SCK half period |
| `has_mon` | 1 | one monitor per bus |
| `chk_pad`, `chk_timing` | 1, 1 | padding-bit and timing checks |
| `gen_frames` | 16 | `SRC_GEN`: frames generated, then idle |
| `inj_kind`, `inj_frame` | NONE, 4 | controller error injection: `WS_GLITCH`, `WS_SHIFT` |

All random values come from `odve_rand` streams (`odve_i2s_item::user_randomize`
via `` `odve_rand ``, an item stream spawned per frame).

## Testbench (`vrf/`)

```
             port A (a_if)                         port B (b_if)
 agt_tx  --SCK/WS/SD-->  [ dut: RX -> swap+negate -> TX ]  --SCK/WS/SD-->  agt_rx
(TX agent)               (vrf/dut/dut.sv, RTL)                           (RX agent)
```

- DUT `vrf/dut/dut.sv`: synthesizable, 10 ns system clock; port A receiver,
  port B transmitter, each clock controller or target (config pins); output
  slot k = saturating -(input slot k^1); one frame of buffering, idle frames
  on underrun.
- Scoreboard `vrf/tb/env/scb.sv`: driver-sent vs. port A monitor (agent TX
  vs. monitor/receiver agent) and reference model vs. port B monitor.
- Plusargs (`vrf/tb/env/cc.sv`, override the test's choices):

| Plusarg | Values | Meaning |
|---|---|---|
| `+i2s_slave=` | `dut` (default), `agent` | port A receiver: the DUT, or a receiver agent (agents checked against each other, no DUT traffic) |
| `+i2s_a_clk=` | `tx` (default), `rx` | port A clock controller: transmitter agent, or the receiver (DUT / receiver agent) |
| `+i2s_b_clk=` | `tx` (default), `rx` | port B clock controller: DUT, or receiver agent |
| `+i2s_fmt=` | `i2s`, `lj`, `rj`, `tdm` | frame format |
| `+i2s_wlen=`, `+i2s_slen=`, `+i2s_slots=` | 16/24/32, 16/32, 2..8 | frame shape |
| `+i2s_mono`, `+i2s_frames=N`, `+i2s_sck_half=NS` | | mono, frames sent, SCK half period (multiple of 10, >= 40) |
| `+i2s_inj=` | `glitch`, `shift` | WS error injection (needs `+i2s_a_clk=tx`) |

## How to run

```bash
cd odve/comp/agents/i2s/vrf/work/run
source sourceme
make aclean all run TESTNAME=i2s_std_test                       # ModelSim/Questa
make aclean all run TESTNAME=i2s_tdm_test VERILATOR=1           # Verilator
make run TESTNAME=i2s_lj_test RUN_OPTS+='+i2s_a_clk=rx +i2s_b_clk=rx'
./regress.py submit -j 2 -exer                                  # ModelSim
./regress.py submit -j 2 -exer -ropts="VERILATOR=1"             # Verilator
./regress.py submit -j 2 -cov -ropts="VERILATOR=1"              # + functional coverage
```

## Tests (`vrf/tb/tests/`) and requirements

| Test | Scenario | Requirements (doc/req.md) |
|---|---|---|
| `i2s_std_test` | I2S, random frames back-to-back (word/slot length by plusarg) | 002-006, 008, 009, 019, 021, 022 |
| `i2s_lj_test` / `i2s_rj_test` | left-/right-justified, 24 in 32 | 015 / 016 |
| `i2s_tdm_test` | TDM 4 x 32 (slots/lengths by plusarg) | 017 |
| `i2s_mono_test` | mono frames | 018 |
| `i2s_corner_test` | 0, +/-full scale, +/-1 (saturation) | 002, 021 |
| `i2s_gap_test` | 0..3 idle frames between frames | 019 |
| `i2s_gen_test` | autonomous transmitter (`SRC_GEN`) | 020 |
| `i2s_ws_err_test` | WS glitch / frame one SCK short, must be detected; recovery | 010, 011, 012 |
| `i2s_timing_err_test` | DUT target transmitter at T = 80 ns violates tsr, must be detected | 014 |

`vrf/work/rlist/submit.list` runs them over formats, word lengths and all
clock-role combinations (36 runs); `mini.list` has one I2S run. The
requirement -> run table is in doc/req.md.

## Known limitations

- Transmitter and receiver word lengths are always equal (no truncation /
  zero-fill scenarios, REQ-I2S-007).
- Data and WS launched on the falling edge only; LJ/RJ always WS high =
  left; TDM only with a one-SCK sync pulse and one-SCK data delay.
- Only rising-edge set-up and SCK duty are checked; tdtr/thtr/thr/tRC are
  not (zero-time edges).
- MCLK is a free-running signal, not used by any device.
- A target transmitter in LJ/RJ sends idle frames until it has seen one
  frame start (it cannot know the first frame position earlier).
- Mono is a TB convention (duplicated sample), not defined by UM11732.
