# SMBus agent - requirements

Spec references are to SMBus 3.3 (see `spec.md`). Runs are entries of
`vrf/work/rlist/submit.list` (16, all on both simulators): `<test>` against
the RTL device, `_mem` / `_seq` against the slave agent.

| ID | Requirement | Spec | Verified by |
| --- | --- | --- | --- |
| REQ-SMB-001 | Messages are carried by the I2C layer (START, Sr, STOP, ACK/NACK, 7-bit address); the smbus monitor decodes the i2c monitor's transfers. | 5, 6.5 | every run; the i2c monitor's checks stay active underneath |
| REQ-SMB-002 | Quick Command, both R/W# values; the device takes the R/W# bit as the command. | 6.5.1 | `smbus_proto_test` (STATUS.QUICK read back after each), `smbus_rand_test`; `cp_proto.quick_w/quick_r` |
| REQ-SMB-003 | Send Byte. | 6.5.2 | `smbus_proto_test`, `smbus_alert_test`, `smbus_rand_test`; `cp_proto.send_byte` |
| REQ-SMB-004 | Receive Byte. | 6.5.3 | `smbus_proto_test` and every STATUS read; `cp_proto.recv_byte` |
| REQ-SMB-005 | Write Byte and Write Word (low byte first). | 6.5.4 | `smbus_proto_test`, `smbus_rand_test`; scoreboard register model |
| REQ-SMB-006 | Read Byte and Read Word: command, repeated START, read; the host NACKs the last byte. | 6.5.5 | `smbus_proto_test`, `smbus_rand_test`; scoreboard data check |
| REQ-SMB-007 | Process Call: word written, word returned in the same message. | 6.5.6 | `smbus_proto_test`, `smbus_rand_test`; scoreboard (inverted word) |
| REQ-SMB-008 | Block Write / Block Read with a byte count 0..32 that excludes the PEC. | 6.5.7 | `smbus_proto_test` (0, 1, 5, 32), `smbus_rand_test`; `cp_nw`, `cp_count` |
| REQ-SMB-009 | Block Write-Block Read Process Call (M written, N returned). | 6.5.8 | `smbus_proto_test` (M = 4, 0), `smbus_rand_test` |
| REQ-SMB-010 | PEC generation: CRC-8 (x^8+x^2+x+1) over all bytes from the START, addresses included; the host appends it to writes, the device to reads. | 6.4 | every PEC message: the monitor recomputes it (SMB_PEC), the host checks the device's; `cp_pec_ok.good` |
| REQ-SMB-011 | PEC checking: a wrong PEC from the host is NACKed by the device and the message is not processed; a wrong PEC from the device is detected by host and monitor. | 6.4.1 | `smbus_pec_test` (dut, mem, seq): 4 write protocols with a wrong PEC, read-back unchanged, STATUS.PEC_ERR; device-side corruption in mem/seq; injected count = flagged count |
| REQ-SMB-012 | Every protocol works with and without PEC. | 6.4 | `smbus_proto_test` (both passes), `smbus_rand_test` (50 %); cross `x_proto_pec` |
| REQ-SMB-013 | SMBALERT#: the device asserts it (SET_ALERT, errors); only an alerting device ACKs the ARA and returns its address in the 7 MSBs; it releases SMBALERT# after that byte is read; CLEAR_STATUS releases it. | A.2 Fig. 65 | `smbus_alert_test` (dut, seq), `smbus_pec_test`, `smbus_rand_test`; scoreboard compares SMBALERT# after every message; `cp_alert`, `cp_proto.ara` |
| REQ-SMB-014 | ARA read with PEC. | A.2 Fig. 66 | `smbus_alert_test`, `smbus_pec_test` |
| REQ-SMB-015 | Clock-low timeout: after SMBCLK low longer than tTIMEOUT (scaled 600 cycles) the device releases the bus and resets (before tTIMEOUT,MAX, monitor check SMB_TIMEOUT) and drops the message; a low phase below tTIMEOUT,MIN does not reset it. | 4.2.2, Table 2 note 3 | `smbus_timeout_test` (dut, mem, seq): writes and reads timed out, STATUS.TMO, read-back unchanged, 300-cycle hold without reset, monitor counts exactly 2 timeouts; `cp_timeout` |
| REQ-SMB-016 | Unsupported command codes (written or read) and block counts above the device's limit are NACKed and flagged in STATUS; reading a write-only code is flagged. | 6.5 ("results ... undefined", device definition), I2C 3.1.6 #3 | `smbus_err_test` (dut, mem), `smbus_alert_test`; scoreboard ACK prediction; `cp_ack.nack`, `cp_proto.unknown` |
| REQ-SMB-017 | A write is carried out only when the message is complete and error free (a short message is ignored without error). | PMBus Part II 10.8.4 (device definition) | `smbus_err_test`, `smbus_pec_test`, `smbus_timeout_test`; scoreboard commits only complete messages |
| REQ-SMB-018 | Cumulative device clock stretching per message stays within tLOW:SEXT. | 4.2.3/4.2.4 | monitor SMB_SEXT check active in every run; nothing stretches (passive only) |
| REQ-SMB-019 | Both roles: host against the RTL device and against the slave agent in MEM and SEQ mode. | - | `_mem` / `_seq` runs |
| REQ-SMB-020 | Host Notify, Write/Read 32/64, ARP, multi-master arbitration, tLOW:MEXT, SMBDAT low timeout. | 6.5.9-6.5.13, 6.6, 4.2.5 | not verified (not modelled) |

## Traceability: requirement -> submit runs

| Requirement | Runs |
| --- | --- |
| REQ-SMB-001 | all 16 |
| REQ-SMB-002..010, 012 | smbus_proto, smbus_proto_mem, smbus_proto_seq, smbus_rand, smbus_rand_mem, smbus_rand_seq |
| REQ-SMB-011 | smbus_pec, smbus_pec_mem, smbus_pec_seq |
| REQ-SMB-013, 014 | smbus_alert, smbus_alert_seq, smbus_pec*, smbus_rand* |
| REQ-SMB-015 | smbus_timeout, smbus_timeout_mem, smbus_timeout_seq |
| REQ-SMB-016, 017 | smbus_err, smbus_err_mem, smbus_pec*, smbus_timeout* |
| REQ-SMB-018 | all 16 (passive) |
| REQ-SMB-019 | the `_mem` and `_seq` runs |
| REQ-SMB-020 | not verified |

19 requirements verified (1 passively), 1 not verified.
