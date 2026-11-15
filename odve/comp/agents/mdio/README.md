# odve MDIO agent

UVM agent for the IEEE 802.3 station management interface (MDC/MDIO),
**Clause 22** (read/write) and **Clause 45** (address, write, read,
post-read-increment-address), with a synthesizable RTL PHY management block
as DUT. Protocol summary and sources: [doc/spec.md](doc/spec.md);
requirements and traceability: [doc/req.md](doc/req.md).

## Layout

```
intf/odve_mdio_if.sv            mdc, per-driver mdio value/enable pairs (sta_*, phy_*, dut_*), resolved mdio (pull-up)
src/item/                       odve_mdio_item (+ odve_mdio_kind_e) and its package
src/agent/odve_mdio_cfg.sv      role, slave mode, timing and PHY-model knobs
src/agent/odve_mdio_phy_model.sv  PHY/MMD register model: slave MEM mode, responder sequence, TB scoreboard
src/agent/mon/                  monitor: frame decode, protocol checks, coverage sample
src/agent/mst/                  STA driver: MDC generation, frames, error injection
src/agent/slv/                  PHY driver: MEM (model inside) or SEQ (answers from a sequence)
src/agent/odve_mdio_{sqr,slv_sqr,agent,agent_pkg}.sv   sequencers, agent, package (+ covergroup odve_mdio_cg)
seq/                            odve_mdio_base_seq (directed list), odve_mdio_rand_seq, odve_mdio_slv_resp_seq
list/                           agent.f, item.f, seq.f
vrf/dut/dut.sv                  RTL PHY: Clause 22 PHY + Clause 45 port with MMDs 1 and 3
vrf/tb/                         top, env (cc, scb, env), tests
vrf/work/                       run/mini/check work dirs, rlist/{submit,mini,check}.list
doc/                            spec.md, req.md
```

## Configuration (`odve_mdio_cfg`)

| Knob | Default | Meaning |
|---|---|---|
| `role` | `ODVE_MDIO_MASTER` | `ODVE_MDIO_MASTER` = STA (sequencer + master driver), `ODVE_MDIO_SLAVE` = PHY(s) |
| `slv_mode` | `ODVE_MDIO_SLV_MEM` | slave: register model in the driver (`MEM`) or in a responding sequence on `slv_sqr` (`SEQ`, start `odve_mdio_slv_resp_seq`, `model.configure(cfg)` first) |
| `has_mon` | 1 | one monitor per bus |
| `mdc_half` | 4 | MDC half period in system clocks (keep >= 4 with the RTL PHY: it changes its output 3 clocks after the rise) |
| `pre_min` | 32 | preamble ones a PHY needs (slave driver, monitor `MDIO_PRE`, model) |
| `phyads`, `prtads` | `{1}` | slave: Clause 22 PHY addresses / Clause 45 port addresses played |
| `id1`, `id2` | `ODVE_MDIO_ID1/ID2` | identifier register values |
| `t_su`, `t_hold` | 10, 10 (ns) | monitor setup/hold check around the MDC rising edge |

Item (`odve_mdio_item`): `kind` (`C22_WR/C22_RD/C45_ADDR/C45_WR/C45_RD/C45_RINC/C22_BAD`),
`phyad` (PRTAD), `regad` (DEVAD), `data`, `pre_len`, `idle` (MDC cycles after
the frame, 0 = back to back), `ta` (write TA to drive - error injection),
`bad_op` (OP for `C22_BAD`); results `resp`, `data`. No `rand`: values come
from `user_randomize()` with the item's `odve_rand` stream (`` `odve_rand ``).

Monitor checks (`uvm_error` IDs): `MDIO_PRE`, `MDIO_OP`, `MDIO_TA`,
`MDIO_DIR`, `MDIO_RESP`, `MDIO_IDLE`, `MDIO_CONT`, `MDIO_SETUP`,
`MDIO_HOLD` - see the header of `src/agent/mon/odve_mdio_mon.sv`.

Coverage (`FCOV=1`): `odve_mdio_cg` - frame kind, PHY/port address class,
Clause 22 register class, Clause 45 MMD (present/absent), answered/unanswered
reads (and crossed with the read kind), preamble short/32/long, frame
sequences (address->write/read/rinc, rinc->rinc, write->read, read->read).

## Testbench plusargs

`+mdio_slave=` selects who answers on the bus (read by `tb/env/cc.sv` and `tb/top.sv`):

| Value | PHYs on the bus |
|---|---|
| `dut` (default) | RTL PHY at PHY/port address 1 |
| `mem` | slave agent, MEM mode, addresses 1 and 2 |
| `seq` | slave agent, SEQ mode, addresses 1 and 2 |
| `multi` | RTL PHY at 1 and slave agent (MEM) at 2 and 3, on one bus |

## How to run

```bash
cd odve/comp/agents/mdio/vrf/work/run
source sourceme
make aclean all run TESTNAME=c22_test                     # ModelSim/Questa
make aclean all run TESTNAME=c22_test VERILATOR=1         # Verilator
make run TESTNAME=rand_test RUN_OPTS+=+mdio_slave=multi
./regress.py submit -j 2 -exer                            # ModelSim
./regress.py submit -j 2 -exer -ropts="VERILATOR=1"       # Verilator
./regress.py submit -j 2 -cov -ropts="VERILATOR=1"        # + functional coverage
```

## Tests -> requirements

| Test | What | Requirements (doc/req.md) |
|---|---|---|
| `c22_test` | reset/ID values, write every register, read all back | 004, 005, 012-015 |
| `c45_test` | MMDs 1/3: RO device registers, address+write/read, unimplemented address, absent MMD | 008, 009, 011, 016 |
| `c45_rinc_test` | block read with post-read-increment, address after the block, 16-bit wrap | 008-010 |
| `addr_miss_test` | non-matching PHY/port addresses and absent MMDs: no answer, FFFF, nothing written | 011, 018 |
| `b2b_test` | frames with no idle cycle, directed and random | 003, 017 |
| `short_pre_test` | preambles of 1/2/17/31 ones ignored and flagged, 32 and 41 accepted | 002, 003 |
| `proto_err_test` | write TA 11/00/01 and C22 OP 00/11: flagged and ignored | 006, 007 |
| `rand_test` | 150 random frames, 15 % misses, random idles, long preambles | 003, 004, 008, 009, 011, 015 |

`submit` runs all eight against the RTL PHY plus slave-agent variants
(mem, seq, multi); `mini` runs `rand_test`.

## Known limitations

- No preamble suppression (status bit 6 = 0, DUT `PRE_MIN` = 32).
- Register bits have no function (control is storage, status a constant);
  no Clause 22 -> Clause 45 indirect access via registers 13/14.
- Only MMDs 1 and 3; MDC is scaled to 80 ns and its minimum period is not checked.
- The scoreboard's reference model is the same class as the slave agent's
  register model, so agent-vs-agent runs check the agent's bus behaviour
  rather than an independent register implementation; the RTL DUT is the
  independent one.
- `phyad`/`regad` hold PRTAD/DEVAD for Clause 45 frames.
