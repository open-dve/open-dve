# odve UART agent

A UVM agent for an asynchronous serial link (UART, RS-232 style at logic
level): start bit, 5-8 data bits LSB first, none/even/odd/mark/space parity,
1/1.5/2 stop bits, 16x mid-bit sampling, break, framing/parity errors,
RTS/CTS hardware flow control. Full duplex: one master agent drives `txd`
(and `rts_n`) and its monitor watches both lines; a slave agent can play the
peer device instead of the RTL.

This agent **replaces the earlier non-UVM `uart` placeholder** (a plain-SV
driver/monitor pair with a "Hello DUT" module and a Makefile that skipped
UVM); that version is in git history. The new one was scaffolded with
`vrf-new-agent` and follows `apb`'s layout and conventions.

Protocol summary and references: [doc/spec.md](doc/spec.md).
Requirements and traceability: [doc/req.md](doc/req.md) (REQ-UART-001..021; slave-agent runs cover 020).

## Layout

```
intf/odve_uart_if.sv                 txd, rxd, rts_n, cts_n + the slave's s_rxd, s_cts_n
src/item/odve_uart_item(_pkg).sv     item, enums (kind, dir, parity, stop), parity/mask helpers
src/agent/odve_uart_cfg.sv           configuration (below)
src/agent/odve_uart_phy.sv           bit-level send / 16x-style receive, shared by drivers and monitor
src/agent/mon/odve_uart_mon.sv       monitor: both lines, protocol checks, coverage
src/agent/mst/odve_uart_mst_drv_base.sv   master driver: txd (+ injections), rts_n, auto-CTS
src/agent/slv/odve_uart_slv_drv.sv   slave driver: peer device (receive FIFO, echo, auto-RTS/CTS)
src/agent/odve_uart_sqr.sv, odve_uart_slv_sqr.sv, odve_uart_agent.sv, odve_uart_agent_pkg.sv (covergroup)
seq/                                 base (random) seq, pattern seq, slave echo responder seq
list/agent.f, item.f, seq.f
vrf/dut/dut.sv                       RTL echo device (16550-style RX/TX, 8-entry RX FIFO)
vrf/tb/                              top, uart_tb_if (DUT config/status pins), env/{env,scb,cc}, tests/
vrf/work/{run,mini,check,common,rlist}
doc/spec.md, doc/req.md
```

## Roles and modes

- `cfg.role = ODVE_UART_MASTER`: sequencer + `odve_uart_mst_drv_base`.
  Item kinds: `DATA` (one character; `bad_parity`, `bad_stop` inject errors),
  `BREAK` (`brk_bits` bit times of space), `GLITCH` (`glitch_clks` of space:
  a false start bit); `idle_bits` of mark before each. The master's receiver
  is its monitor; `drv.set_rx_ready(0|1)` drives `rts_n`.
- `cfg.role = ODVE_UART_SLAVE`: `odve_uart_slv_drv`, a peer device that
  receives on `txd` and answers on `s_rxd`:
  - `ODVE_UART_SLV_MEM` (autonomous): receive FIFO of `cfg.fifo_depth` in the
    driver, answers each good character with its complement (`~data`, the
    same as the RTL), drops errored characters, counts overruns.
  - `ODVE_UART_SLV_SEQ` (reactive): each good character goes into
    `slv_sqr.req_fifo` (instance name `slv_req_fifo`); the responding sequence
    (`odve_uart_slv_echo_seq`, or your own) returns the item to send back
    (`kind = NONE`: nothing).
- `cfg.has_mon` (default 1): the monitor watches **both** lines of the link,
  so a link needs only one (the TB clears it on the slave agent).

## Configuration (`odve_uart_cfg`)

| Field | Default | Meaning |
|---|---|---|
| `data_bits` | 8 | 5..8 |
| `parity` | `ODVE_UART_PAR_NONE` | `NONE/EVEN/ODD/MARK/SPACE` |
| `stop` | `ODVE_UART_STOP1` | `STOP1/STOP1_5/STOP2` |
| `bit_clks` | 32 | nominal bit period in `clk` cycles (16x oversampling: a multiple of 16); every receiver samples with it |
| `tx_bit_clks` | 0 | != 0: this agent transmits at another bit period (baud mismatch) |
| `flow_ctrl` | 0 | RTS/CTS: wait for `cts_n` low before each character (master), drive `s_cts_n` from the FIFO level and wait for `rts_n` (slave) |
| `allow_tx_err` | 0 | monitor: errors on `txd` are injected, not violations |
| `fifo_depth` | 8 | slave: receive FIFO size (auto-RTS threshold `fifo_depth-1`) |
| `role`, `slv_mode`, `has_mon`, `vif` | | as above |

`cfg.copy_format()` copies format, `bit_clks` and `flow_ctrl` from another
cfg; the env's `set_format(bits, parity, stop, flow)` applies one format to
master, slave agent and RTL (call it only while the link is idle).

## Monitor checks and coverage

The monitor (`odve_uart_mon`) rebuilds each character from the pins and
publishes it with `dir` (TX = `txd`, RX = `rxd`), format, `pe`/`fe`/`brk`,
`gap_bits`, `t_end`. It reports `uvm_error` on a parity/framing error or
break on `rxd` (and on `txd` unless `allow_tx_err`), a stop bit shorter than
configured (second stop bit / second half of 1.5), and a false start bit on
`rxd`. False start bits on `txd` are counted (`n_glitch[0]`).

Covergroup `odve_uart_cg` (agent package, `` `ifdef ODVE_COV_NATIVE ``):
direction, data bits, parity, stop bits, error kind, data class (all 0 / all
1 / other), idle gap (back to back / short / long), crosses bits x parity,
bits x stop (16550-legal combinations) and direction x error.

## Testbench (`vrf/`)

- DUT `vrf/dut/dut.sv`: UART echo device, see doc/spec.md section 7. Pins
  `lcr[5:0]` (16550 LCR layout), `div`, `afe`, `rxd/txd`, `cts_n/rts_n`,
  status pulses `st_valid/st_oe/st_pe/st_fe/st_bi`.
- `+uart_slave=dut|mem|seq` (default `dut`): who answers the master - the
  RTL or the slave agent in MEM / SEQ mode (`vrf/tb/top.sv` routes `rxd` and
  `cts_n`, `tb/env/cc.sv` builds the slave agent).
- Scoreboard (`tb/env/scb.sv`): every good `txd` character must come back on
  `rxd` complemented, in order; errored ones must not; nothing unexpected on
  `rxd`. With the RTL it also pairs each DUT status pulse with the `txd`
  character it belongs to (by time) and compares the flags; an overrun is an
  error unless the test expects it.

### Tests (`vrf/tb/tests/`) and lists

| Test | What | Requirements |
|---|---|---|
| `basic_test` | 8N1, 40 random characters, random gaps | 001, 002, 017, 019 |
| `format_test` | all 40 16550 formats (5-8 bits x 5 parities x 2 stop settings), random + edge patterns | 003-005, 017 |
| `b2b_test` | back-to-back characters in 8E2, 5N1, 7O1 | 005, 009, 018 |
| `baud_test` | master transmits at 31 and 33 clk/bit against 32 (±3.1 %) | 005, 008, 009, 018 |
| `err_test` | bad parity, bad stop bit, break, glitch (3 of each + 40 % random), three formats | 007, 010-013 |
| `overrun_test` | RTL only: 11 characters into the 8-entry FIFO while held off -> 3 overruns | 014 |
| `flow_test` | RTS/CTS: master not ready, peer must hold, master must stall; then free-running | 015, 016 |

`vrf/work/rlist/submit.list` runs each against the RTL and the slave agent
modes (15 runs, names `uart_*`); `mini.list` runs `uart_basic`.

## How to run

```bash
cd odve/comp/agents/uart/vrf/work/run
source sourceme
make aclean all run TESTNAME=basic_test                       # ModelSim/Questa
make aclean all run TESTNAME=basic_test VERILATOR=1           # Verilator
make run TESTNAME=err_test RUN_OPTS+=+uart_slave=mem          # slave agent as the peer
./regress.py submit -j 2 -exer                                # ModelSim
./regress.py submit -j 2 -exer -ropts="VERILATOR=1"           # Verilator
./regress.py submit -j 2 -cov -ropts="VERILATOR=1"            # + functional coverage
```

## Known limitations

- The 16550 register interface (CPU bus, interrupts, divisor latch, FIFO
  trigger levels, character timeout), modem lines other than RTS/CTS,
  loopback and XON/XOFF are not modelled (doc/spec.md section 8).
- After a framing error every receiver here waits for mark before the next
  start bit; the 16550's "resample the stop bit as a start bit" recovery is
  not modelled.
- The bit period is a whole number of clocks; baud offsets are therefore
  steps of 1/`bit_clks` (3.1 % at the default 32).
- Overrun is checked against the RTL only; the slave agent models it
  (`n_oe`) but has no status pins for the scoreboard.
- The master agent sends breaks as a line event (`kind = BREAK`), not via a
  16550-style break-control bit.
