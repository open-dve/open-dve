# odve PMBus agent

UVM agent for PMBus (Power System Management Protocol, revision 1.3.1 Part
I/II), layered on the `smbus` agent, which is layered on the `i2c` agent.
The host (master) sends PMBus commands - each as the SMBus protocol of its
Part II Table 31 transaction type - and decodes LINEAR11 / ULINEAR16
values; the device (slave) is a PMBus device model on the SMBus slave
(paging, OPERATION, ON_OFF_CONFIG, VOUT_MODE/VOUT_COMMAND, STATUS_BYTE/
WORD/CML, READ_VOUT/IOUT, CAPABILITY, PMBUS_REVISION, CLEAR_FAULTS, the
Part II 10.8/10.9 fault responses, SMBALERT#). Protocol summary:
`doc/spec.md`; requirements and tests: `doc/req.md`.

## Reuse (design choice)

PMBus adds a command language to SMBus and nothing to its signals, so:
no interface of its own (SMBCLK/SMBDAT = `odve_i2c_if`, SMBALERT# =
`odve_smbus_if`); `list/agent.f` includes `smbus/list/agent.f` (which
includes the i2c lists) and `smbus/list/seq.f`; `odve_pmbus_agent` contains
an `odve_smbus_agent` named `smb` (whose cfg - role, address, Table 31
command table, model - it derives); the device model extends
`odve_smbus_dev_model`; the RTL DUT is the smbus message engine
(`smbus/vrf/dut/odve_smbus_tgt_eng.sv`) on the i2c target layer
(`i2c/vrf/dut/odve_i2c_tgt_phy.sv`) plus the PMBus command set in
`vrf/dut/dut.sv`.

## Layout

| Path | Contents |
| --- | --- |
| `src/item/` | `odve_pmbus_item`, command codes `PMB_*`, `odve_pmbus_cmd_kind()` (Table 31), `odve_pmbus_cmd_name()`, LINEAR11/ULINEAR16 helpers |
| `src/agent/` | `odve_pmbus_cfg`, `odve_pmbus_agent`, `odve_pmbus_sqr`, `odve_pmbus_value()`, covergroup `odve_pmbus_cg` |
| `src/agent/mst/` | `odve_pmbus_mst_drv`: command -> SMBus message on `smb.sqr` |
| `src/agent/slv/` | `odve_pmbus_dev_model`: the PMBus device (smbus model hooks) |
| `src/agent/mon/` | `odve_pmbus_mon`: page/VOUT_MODE tracking, value decoding, PMB_PROTO checks, coverage |
| `seq/` | `odve_pmbus_item_seq`, `odve_pmbus_rand_seq`, `odve_pmbus_slv_seq` (responder) |
| `vrf/dut/dut.sv` | the PMBus device RTL (command set, paging, status) |

## Configuration (`odve_pmbus_cfg`)

- `role` `ODVE_PMBUS_MASTER` / `ODVE_PMBUS_SLAVE`; `slv_mode`
  `ODVE_PMBUS_SLV_MEM` (model in the i2c slave driver) / `ODVE_PMBUS_SLV_SEQ`
  (start `odve_pmbus_slv_seq` with `model = cfg.model` on
  `<agent>.smb.i2c.slv_sqr`).
- `vif` (SMBALERT#), `i2c_vif` (SMBCLK/SMBDAT), optional `smb_cfg`;
  `addr` (40h), `model`, `npages` (2), `vout_exp` (VOUT_MODE exponent used
  for ULINEAR16 until a VOUT_MODE read is seen; -9).
- Item: `op` (`PMB_WRITE`, `PMB_READ`, `PMB_SEND`), `cmd`, `wdata`, `pec`;
  injection `force_proto` (another SMBus protocol), `bad_pec`; results
  `rdata`, `value`, `ack`, `nack_byte`, `pec_ok`; monitor adds `page`,
  `alert`, `raw_wr`/`raw_rd`.
- Monitor error id `PMB_PROTO`; the SMBus checks (`SMB_PEC`, `SMB_TIMEOUT`,
  `SMB_SEXT`) and the I2C checks run underneath.

## Running

```bash
cd odve/comp/agents/pmbus/vrf/work/run
source sourceme
make aclean all run TESTNAME=pmbus_rand_test [VERILATOR=1]
./regress.py submit -j 2 -exer [-ropts="VERILATOR=1"] [-cov]
```
`+pmbus_slave=dut|mem|seq` selects the device (default the RTL).

## Tests

| Test | What | Requirements |
| --- | --- | --- |
| `pmbus_basic_test` | identification, OPERATION/ON_OFF_CONFIG, VOUT_COMMAND/READ_VOUT/READ_IOUT values, STATUS, both pages, with/without PEC, format helpers | 002-010, 017 |
| `pmbus_page_test` | per-page state, invalid PAGE values | 004, 010, 013, 015 |
| `pmbus_fault_test` | unsupported codes, read-only writes, invalid data, too many bytes, reading past PEC, read at START, STATUS_CML clearing, ARA, CLEAR_FAULTS | 001, 007, 011, 013-016 |
| `pmbus_pec_test` | all commands with PEC, wrong PEC on every writable command | 012, 015, 017 |
| `pmbus_rand_test` | 40 random commands, both pages, 5 % invalid | 001, 004, 008, 011, 013 |

`submit.list`: all five on the DUT, `basic/fault/rand` with `mem`,
`basic/page/fault/pec/rand` with `seq` (13 runs).

## Known limitations

PMBus 1.3.1 (not 1.4, which needs registration). No PAGE FFh, group
command, ZONE, PAGE_PLUS, store/restore, fault limits and responses,
DIRECT/VID/IEEE formats, BUSY, CONTROL pin; STATUS_BYTE/WORD read only in
the TB device. A Write Word to a byte command without PEC is reported by
the device as a PEC failure (it is indistinguishable from Write Byte + PEC).
