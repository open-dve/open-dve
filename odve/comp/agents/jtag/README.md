# odve JTAG agent (IEEE 1149.1 TAP)

A UVM agent for the JTAG test access port: TCK, TMS, TDI, TDO and the
optional TRST_n. One agent class plays either side:

- **master** = JTAG host. Owns TCK (derived from the TB clock), keeps its own
  copy of the TAP state and offers the operations reset (5x TMS=1 or a
  TRST_n pulse), goto-state (shortest TMS path to any of the 16 states), IR
  scan, DR scan (any length 0..255, optional pause in Pause-xR with Exit2
  resume) and idle cycles in Run-Test/Idle; scans return the bits shifted
  out.
- **slave** = behavioural TAP: the 16-state controller, a 4-bit IR (Capture
  0001), IDCODE, BYPASS, USERDATA (32-bit R/W) and an 8-bit boundary
  register for EXTEST/SAMPLE-PRELOAD. `SLV_MEM`: registers in the driver;
  `SLV_SEQ`: the driver asks a responding sequence at each Capture-DR /
  Update-DR / TRST_n (`odve_jtag_slv_reg_seq`).
- **monitor** (either role, `cfg.has_mon`): runs its own TAP controller from
  TMS/TRST_n, publishes every reset and every IR/DR scan (bits in = updated
  value, bits out = captured value, pauses, idle cycles before it), checks
  TDO enable only in Shift states, the Capture-IR `01` pattern and unknown
  values, and samples the coverage.

Protocol summary and sources: [`doc/spec.md`](doc/spec.md). Requirements and
traceability: [`doc/req.md`](doc/req.md).

## Layout

```
intf/odve_jtag_if.sv                 tck tms tdi trst_n | tdo tdo_oe (bus) | s_tdo s_tdo_oe (slave agent) | dbg_state
src/item/odve_jtag_item_pkg.sv       TAP state enum, odve_jtag_next(), kinds, odve_jtag_vec_t (ODVE_JTAG_MAX_LEN=256)
src/item/odve_jtag_item.sv           one operation / observed reset or scan / slave request
src/agent/odve_jtag_agent_pkg.sv     roles, slave modes, opcodes, covergroups odve_jtag_cg + odve_jtag_fsm_cg
src/agent/odve_jtag_tap_model.sv     TAP registers (capture/update), shared by slave driver, slave seq and scoreboard
src/agent/odve_jtag_cfg.sv, _agent.sv, _sqr.sv, _slv_sqr.sv
src/agent/mon/odve_jtag_mon.sv
src/agent/mst/odve_jtag_mst_drv_base.sv
src/agent/slv/odve_jtag_slv_drv.sv
seq/                                 reset/goto/ir/dr/idle sequences, odve_jtag_rand_seq, odve_jtag_slv_reg_seq
list/agent.f, item.f, seq.f
vrf/dut/jtag_tap.sv, dut.sv          RTL TAP and an NTAP daisy-chain wrapper
vrf/tb/                              top, env (cc, scb), tests
vrf/work/{run,mini,check,common,rlist}
```

## Configuration (`odve_jtag_cfg`)

| Field | Default | Meaning |
|-------|---------|---------|
| `role` | `ODVE_JTAG_MASTER` | `ODVE_JTAG_MASTER` (host) or `ODVE_JTAG_SLAVE` (TAP) |
| `slv_mode` | `ODVE_JTAG_SLV_MEM` | slave: `SLV_MEM` autonomous, `SLV_SEQ` reactive |
| `has_mon` | 1 | build the monitor (one per bus) |
| `tck_half` | 1 | master: TB clock cycles per TCK phase |
| `ir_len` | 4 | IR length of the chain (coverage of the instruction) |
| `check_ir_capture`, `check_tdo_oe` | 1 | monitor checks |
| `idcode`, `pins` | `32'h1234_5679`, `8'hA5` | slave: IDCODE value, pins seen by the boundary register |
| `err_ir_capture`, `err_tdo_oe` | 0 | slave fault injection (Capture-IR 0000 / TDO always enabled) |

Opcodes: EXTEST 0000, SAMPLE/PRELOAD 0001, IDCODE 0010, USERDATA 1000,
BYPASS 1111; any other code acts as BYPASS.

## Testbench

`vrf/dut/dut.sv` is a synthesizable chain of `NTAP` `jtag_tap`s; `top.sv`
instantiates a single TAP (`dut_i`) and a chain of two (`chain_i`) and routes
one of them, or the slave agent, onto TDO. Plusargs (read by `top.sv` and
`tb/env/cc.sv`):

| Plusarg | Values | |
|---------|--------|---|
| `+jtag_slave=` | `dut` (default), `chain`, `mem`, `seq` | who plays the target |
| `+jtag_err=` | `none` (default), `oe`, `ircap` | fault injection into the slave agent (`mem`/`seq` only), for `err_test` |

The env always has the master agent (with the monitor) and the scoreboard,
plus the slave agent (no monitor) for `mem`/`seq`. The scoreboard keeps one
`odve_jtag_tap_model` per TAP and checks every bit out of every scan.

## Running

```bash
cd odve/comp/agents/jtag/vrf/work/run
source sourceme
make aclean all run TESTNAME=rand_test RUN_OPTS+=+jtag_slave=chain         # ModelSim
make aclean all run TESTNAME=rand_test VERILATOR=1                         # Verilator
./regress.py submit -j 2 -exer                                             # 26 runs
./regress.py submit -j 2 -exer -ropts="VERILATOR=1"
./regress.py submit -j 2 -cov -ropts="VERILATOR=1"                         # + functional coverage
```

## Tests -> requirements

| Test | Entries in `submit` | Requirements |
|------|---------------------|--------------|
| `idcode_test` | jtag_idcode, _mem, _seq, _chain | 003, 004, 005, 014 |
| `bypass_test` | jtag_bypass, _chain | 006, 007 |
| `user_test` | jtag_user, _mem, _seq | 009, 010 |
| `len_test` | jtag_len, _seq | 012 |
| `pause_test` | jtag_pause, _mem | 013 |
| `reset_test` | jtag_reset, _seq | 002, 003, 004, 010 |
| `bsr_test` | jtag_bsr, _mem | 008 |
| `goto_test` | jtag_goto, _mem | 001, 020 |
| `chain_test` | jtag_chain | 011, 017 |
| `rand_test` | jtag_rand, _mem, _seq, _chain | 007, 012, 013, 014, 017 |
| `err_test` | jtag_err_oe (mem), jtag_err_ircap (seq) | 011, 016 |

All runs: 015, 018, 019 (mem/seq), 020, 021 (positive), 016/011 monitor checks.
`mini` = `jtag_rand`.

## Known limitations

- One IR length (4 bits per TAP) and one instruction set; the scoreboard
  model assumes it.
- The boundary register is a plain 8-bit register: no cell structure, no
  BSDL; `pins_o` under EXTEST is driven but not checked.
- Optional instructions (INTEST, CLAMP, HIGHZ, USERCODE, RUNBIST) and
  1149.1-2013 additions are not modelled.
- TCK is generated from the TB clock with zero-delay edges; no setup/hold
  or clock-to-out timing is modelled or checked.
- The slave agent models a single TAP (the chain is RTL only).
- The master pauses a scan at most once (one `pause_at` per item); the
  monitor counts any number of pauses.
- `goto_test` waits `#1` after each move before comparing states.
- The RTL TAPs get a power-on reset with a real falling edge (`por_n` in
  `top.sv`): Verilator has no X->0 edge at time 0, so an async reset that is
  merely low from the start is never seen there.
