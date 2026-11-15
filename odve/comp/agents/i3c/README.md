# i3c - MIPI I3C (SDR) controller / target agent

UVM agent for the SDR mode of MIPI I3C / I3C Basic, in the layout
`new_agent.sh` produces (`apb` is the reference). Protocol summary,
sources and the modelled / not-modelled list: `doc/spec.md`;
requirements and their traceability: `doc/req.md`.

## Layout

| Path | Contents |
| --- | --- |
| `intf/odve_i3c_if.sv` | SCL/SDA, per-driver `*_sda_oe/_o/_pp` (controller `m_`, target agent `t_`, RTL target `d_`), bus resolution with plain logic (pull-up, open-drain lows, push-pull highs, `contention`), DUT IBI side band |
| `src/item/` | `odve_i3c_item` (kind, addr, ccc, data, len, use_7e, perr_idx, da_pool; results ack, t_end, n_perr, ENTDAA rounds), kinds and CCC constants |
| `src/agent/` | `odve_i3c_cfg`, sequencers, `odve_i3c_agent`; `mst/` controller driver, `slv/` target driver, `mon/` monitor; covergroup `odve_i3c_cg` in `odve_i3c_agent_pkg.sv` |
| `seq/` | `odve_i3c_base_seq` (helpers), `odve_i3c_xfer_seq` (one item), `odve_i3c_priv_rand_seq` (random private transfers), `odve_i3c_slv_mem_seq` (responder of the reactive target) |
| `vrf/` | RTL target `dut/dut.sv`, env + scoreboard, tests, work dirs, rlists |

## Roles and modes (`odve_i3c_cfg`)

| `role` | agent contents | notes |
| --- | --- | --- |
| `ODVE_I3C_MASTER` (controller) | sequencer + `odve_i3c_mst_drv_base`, monitor | generates SCL; private write/read (with or without the 7E header), broadcast/direct CCCs, ENTDAA with an address pool, serves IBIs/Hot-Joins (ACK/NACK per `ibi_ack`/`hj_ack`, reads the MDB when the target's BCR[2] is known set), read abort, parity-error injection (`item.perr_idx`) |
| `ODVE_I3C_SLAVE` (target), `slv_mode = ODVE_I3C_SLV_MEM` | `odve_i3c_slv_drv` | autonomous: identity (`pid`, `bcr`, `dcr`, `static_addr`), registers (`nregs`), DA, ENEC/DISEC, MWL, status in the driver; `request_ibi(mdb)`, `request_hj()`, `offline` |
| `ODVE_I3C_SLAVE`, `slv_mode = ODVE_I3C_SLV_SEQ` | + `odve_i3c_slv_sqr` | reactive: private-transfer bytes go to the responding sequence (`odve_i3c_slv_mem_seq` or your own); CCCs/DAA stay in the driver |

Other knobs: controller timing `t_low`, `t_high` (clks, >= 3), `t_buf`;
`ibi_max_len`; monitor `perr_is_error` (clear it when injecting parity
errors on purpose); target `t_aval` (idle clks before a START request).

## Standalone testbench (`vrf/`)

`+i3c_target=` selects the targets on the bus (`tb/env/cc.sv`, `tb/top.sv`):

    dut    the RTL target (default)
    mem    the target agent alone, autonomous
    seq    the target agent alone, reactive (base_test forks the responder)
    both   RTL target + target agent (MEM): ENTDAA / IBI arbitration between them

The RTL target (`vrf/dut/dut.sv`, synthesizable, one clock, `_i/_o/_oe`
ports): PID/BCR/DCR/static address parameters, 16 x 8-bit registers
(pointer + auto-increment, T=0 on the last register), ENTDAA, SETDASA,
RSTDAA, ENEC/DISEC, SETMWL/GETMWL, GETPID/GETBCR/GETDCR/GETSTATUS, write
parity check (status bit 5), IBI with MDB (`ibi_req` pulse / `ibi_mdb`).

Scoreboard (`tb/env/scb.sv`): one model per target, fed by the controller
agent's monitor; checks ACKs, ENTDAA order/IDs/parity handling, read data
and T-bits, GET payloads, parity-error effects, IBI/Hot-Join legality and
MDBs.

| Test | `submit` entries | Requirements (doc/req.md) |
| --- | --- | --- |
| `daa_test` | i3c_daa (both), i3c_daa_dut | 011, 012, 014, 018, 010 |
| `priv_test` | i3c_priv, i3c_priv_mem, i3c_priv_seq, i3c_priv_both | 006-010, 027 |
| `ccc_test` | i3c_ccc (both), i3c_ccc_seq | 016-019, 010, 014 |
| `parity_test` | i3c_parity, i3c_parity_mem | 013, 019, 020, 021 |
| `ibi_test` | i3c_ibi (both), i3c_ibi_dut | 022-025, 016, 019 |
| `setdasa_test` | i3c_setdasa (both) | 015, 012 |
| `hotjoin_test` | i3c_hotjoin (both) | 026 |

`mini.list`: i3c_daa. Monitor checks (001-005, 028) run in every test.

## Running

    cd vrf/work/run && source sourceme
    make aclean all run TESTNAME=daa_test RUN_OPTS+=+i3c_target=both          # ModelSim/Questa
    make aclean all run TESTNAME=daa_test RUN_OPTS+=+i3c_target=both VERILATOR=1
    ./regress.py submit -j 2 -exer [-ropts="VERILATOR=1"] [-cov]

## Known limitations

- SDR only: no HDR modes, multi-lane, secondary controller, group
  addressing, legacy I2C targets; timing is clk-scaled, not electrical
  (spec.md section 6).
- The spec details marked *(public implementations)* in `doc/spec.md`
  were not checked against the I3C Basic PDF (not downloaded).
- Header after Sr is push-pull and the whole ENTDAA round is open-drain
  (model choices); a private transfer with `use_7e = 0` addressed to a
  target that is raising an IBI at the same time is not handled.
- MWL is not enforced; GETSTATUS activity mode is always 0; a NACKed
  Hot-Join is dropped by the target agent; IBI payload = MDB only.
- The RTL target has no Hot-Join; only one target per direct CCC item.
