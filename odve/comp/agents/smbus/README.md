# odve SMBus agent

UVM agent for the System Management Bus (SMBus 3.3), layered on the `i2c`
agent: the host (master) turns SMBus messages into I2C transfers on an i2c
agent it builds underneath; the device (slave) is the i2c slave driver
running an SMBus device model. All eleven 6.5.1-6.5.8 protocols, PEC
(CRC-8) generation and checking, SMBALERT# with the Alert Response Address,
clock-low timeouts. Protocol summary: `doc/spec.md`; requirements and tests:
`doc/req.md`.

## Reuse of the i2c agent (design choice)

SMBus is the I2C bit layer plus message rules, so this agent does not
duplicate it: `list/agent.f` includes `i2c/list/agent.f` and `i2c/list/seq.f`,
SMBCLK/SMBDAT are an `odve_i2c_if`, and `odve_smbus_agent` contains an
`odve_i2c_agent` named `i2c` whose cfg it derives (role, address, timeout,
model). Only SMBALERT# has its own interface, `odve_smbus_if`. The RTL
device likewise reuses `i2c/vrf/dut/odve_i2c_tgt_phy.sv`; the SMBus message
layer `vrf/dut/odve_smbus_tgt_eng.sv` is in turn reused by the pmbus DUT.

## Layout

| Path | Contents |
| --- | --- |
| `intf/odve_smbus_if.sv` | SMBALERT#, open drain (`s_`/`d_`/`x_` pulls, `alert_n`) |
| `src/item/` | `odve_smbus_item` (one message), enums `odve_smbus_proto_e` / `odve_smbus_cmd_e`, `odve_smbus_crc8()` / `odve_smbus_pec()` |
| `src/agent/` | `odve_smbus_cfg`, `odve_smbus_agent`, `odve_smbus_sqr`, covergroup `odve_smbus_cg` in `odve_smbus_agent_pkg` |
| `src/agent/mst/` | `odve_smbus_mst_drv`: SMBus message -> I2C transfer on the i2c sequencer (PEC appended / checked) |
| `src/agent/slv/` | `odve_smbus_dev_model` (message layer: command code, count, PEC, ARA, Quick, Receive Byte, errors; hooks for the command set) and `odve_smbus_ref_model` (this TB's device) |
| `src/agent/mon/` | `odve_smbus_mon`: decodes i2c transfers by `cfg.cmd_tab`, PEC, timeout and tLOW:SEXT checks, coverage |
| `seq/` | `odve_smbus_item_seq`, `odve_smbus_rand_seq` (`set_from_tab()`), `odve_smbus_slv_seq` (responder) |
| `vrf/dut/` | `odve_smbus_tgt_eng.sv` (synthesizable message layer), `dut.sv` (the device's command set) |

## Configuration (`odve_smbus_cfg`)

- `role`: `ODVE_SMBUS_MASTER` (sequencer + driver over `i2c.sqr`) or
  `ODVE_SMBUS_SLAVE` (device at `addr`, model `cfg.model`, default
  `odve_smbus_ref_model`; the agent drives SMBALERT# from `model.alert`).
- `slv_mode`: `ODVE_SMBUS_SLV_MEM` (model inside the i2c slave driver) or
  `ODVE_SMBUS_SLV_SEQ` (start `odve_smbus_slv_seq` with `model = cfg.model` on
  `<agent>.i2c.slv_sqr`; the same model object must be used so the ARA
  address match and SMBALERT# see it).
- `vif` (SMBALERT#), `i2c_vif` (SMBCLK/SMBDAT), optional `i2c_cfg`.
- `cmd_tab[256]`: what each command code means (`SMB_CMD_SEND/BYTE/WORD/PCALL/BLOCK/BPCALL`),
  used by the monitor to decode; `set_cmds()`, `set_ref_cmds()`.
- Timeouts (cycles, 1 ms = 20): `t_timeout_min` 500, `t_timeout_max` 700,
  `t_timeout_dev` 600 (the slave's reset), `t_low_sext` 500.
- Items: `proto`, `addr`, `cmd`, `wdata`, `pec`; injection `bad_pec`,
  `tmo_byte`/`tmo_cycles`, `abort_byte`/`abort_bit`; results `ack`,
  `nack_byte`, `rdata`, `count`, `pec_present`, `pec_ok`.
- Monitor error ids: `SMB_PEC`, `SMB_TIMEOUT`, `SMB_SEXT`; counters `n_seen`,
  `n_pec_err`, `n_timeout`, `n_short`.

## The TB device (`vrf/dut/dut.sv` = `odve_smbus_ref_model`)

Address 3Ah; 00h-07h byte registers, 10h-13h word registers, 20h Process
Call (returns the word inverted), 30h block register (32 bytes), 31h Block
Process Call (returns the bytes inverted), 40h CLEAR_STATUS and 41h
SET_ALERT (Send Byte), Receive Byte = STATUS `{READY=1,0,0,TMO,QUICK,ALERT_REQ,CMD_ERR,PEC_ERR}`,
Quick Command sets STATUS.QUICK = R/W#. Errors NACK and alert; the clock-low
timeout resets after 600 cycles.

## Running

```bash
cd odve/comp/agents/smbus/vrf/work/run
source sourceme
make aclean all run TESTNAME=smbus_rand_test [VERILATOR=1]
./regress.py submit -j 2 -exer [-ropts="VERILATOR=1"] [-cov]
```
`+smbus_slave=dut|mem|seq` selects the device (default the RTL).

## Tests

| Test | What | Requirements |
| --- | --- | --- |
| `smbus_proto_test` | every protocol, without and with PEC | 002-010, 012 |
| `smbus_rand_test` | 50 random messages over the command set | 001-013 |
| `smbus_pec_test` | wrong PECs from the host (and the device, agent modes) | 011, 013 |
| `smbus_alert_test` | SMBALERT#, ARA with/without PEC, CLEAR_STATUS | 013, 014 |
| `smbus_timeout_test` | 800-cycle clock-low holds in write and read, 300-cycle hold | 015 |
| `smbus_err_test` | unsupported codes, count 33, read of a send-only code, short message | 016, 017 |

`submit.list`: all six on the DUT, five with `mem`, five with `seq` (16 runs).

## Known limitations

No Host Notify, 32/64-bit protocols, ARP, multi-master; one device per
bus in the TB; block length limited to 32 by the TB device (not by the
agent); Quick Command read needs a device whose first read bit is 1.
