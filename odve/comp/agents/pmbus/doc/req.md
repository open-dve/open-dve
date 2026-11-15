# PMBus agent - requirements

Spec references are to PMBus 1.3.1 Part II (see `spec.md`). Runs are the
13 entries of `vrf/work/rlist/submit.list`: `<test>` against the RTL device,
`_mem` / `_seq` against the slave agent.

| ID | Requirement | Spec | Verified by |
| --- | --- | --- | --- |
| REQ-PMB-001 | Every command is sent with the SMBus protocol of its Table 31 transaction type and starts with a write address; the monitor flags other protocols and messages that start with a read (PMB_PROTO). | 5.4.1, Table 31, 10.9.1 | every run (monitor check); `pmbus_fault_test` provokes it twice and requires exactly 2 flags |
| REQ-PMB-002 | PMBUS_REVISION reads 33h (Part I 1.3, Part II 1.3). | 22.1 Table 27 | `pmbus_basic_test` (with and without PEC) |
| REQ-PMB-003 | CAPABILITY reads 90h (PEC, 100 kHz, SMBALERT#). | 11.12 | `pmbus_basic_test`, `pmbus_pec_test` |
| REQ-PMB-004 | PAGE selects the output: OPERATION, ON_OFF_CONFIG, VOUT_COMMAND, STATUS, READ_VOUT/IOUT per page; PAGE reads back. | 11.10 | `pmbus_page_test` (dut, seq), `pmbus_basic_test`, `pmbus_rand_test`; scoreboard per-page model; cross `x_paged_page` |
| REQ-PMB-005 | OPERATION bit 7 turns the output on/off; STATUS OFF follows. | 12.1.1, 17.1 | `pmbus_basic_test`, `pmbus_page_test` |
| REQ-PMB-006 | ON_OFF_CONFIG bits 4/3 decide whether OPERATION is needed; reserved bits [7:5] are invalid data. | 12.2 Table 10 | `pmbus_basic_test`, `pmbus_page_test`, `pmbus_fault_test` |
| REQ-PMB-007 | VOUT_MODE reads the ULINEAR16 mode and exponent; a write to the fixed VOUT_MODE is rejected as invalid data. | 8.3.1 Table 2 | `pmbus_basic_test`, `pmbus_fault_test` |
| REQ-PMB-008 | VOUT_COMMAND / READ_VOUT in ULINEAR16 (V * 2^N, N from VOUT_MODE); host and monitor decode the value. | 8.4.1.1, 13.2, 18.4 | `pmbus_basic_test` (1.2 V, 1.8 V within 1 LSB), `pmbus_page_test`, `pmbus_rand_test`; `cp_vbin` |
| REQ-PMB-009 | READ_IOUT in LINEAR11 (Y * 2^N); encode/decode helpers. | 7.3, 18.5 | `pmbus_basic_test` (2.5 A, 1.25 A, 0 A; helper checks incl. negative values) |
| REQ-PMB-010 | STATUS_BYTE (OFF, CML) and STATUS_WORD (+ PG_STATUS#) reflect state; OFF/PG_STATUS# always current. | 17.1, 17.2, 10.2.3 | `pmbus_basic_test`, `pmbus_page_test`, `pmbus_fault_test`; scoreboard compares every status read |
| REQ-PMB-011 | Unsupported command codes (a manufacturer code, a Table 31 code the device lacks, written or read) and data to read-only codes are NACKed and set STATUS_CML bit 7. | 10.9.2 | `pmbus_fault_test` (dut, mem, seq), `pmbus_rand_test`; `cp_cmd.unsupported`, `cp_cml.cmd_err` |
| REQ-PMB-012 | A wrong PEC is NACKed, the command is not executed, STATUS_CML bit 5 is set. | 10.8.1 | `pmbus_pec_test` (dut, seq): 6 write commands, read-back unchanged; monitor SMB_PEC count = injected |
| REQ-PMB-013 | Invalid data (PAGE 2/9/FFh, OPERATION with margining, ON_OFF_CONFIG reserved bits, VOUT_MODE write) is not executed and sets STATUS_CML bit 6. | 10.9.3, 12.1.7, 12.2 | `pmbus_fault_test`, `pmbus_page_test`, `pmbus_rand_test`; `cp_cml.data_err` |
| REQ-PMB-014 | Too many bytes written: NACK, not executed, bit 6; reading past the PEC: FFh, bit 1; a message starting with a read: FFh, bit 1; a read of the send-only CLEAR_FAULTS: bit 7. | 10.8.5, 10.8.6, 10.9.1 | `pmbus_fault_test` |
| REQ-PMB-015 | Writing 1s to STATUS_CML clears exactly those bits; CLEAR_FAULTS clears all and releases SMBALERT#; STATUS_BYTE.CML follows STATUS_CML. | 10.2.4, 10.2.5.1, 15.1 | `pmbus_fault_test`, `pmbus_page_test`, `pmbus_pec_test` |
| REQ-PMB-016 | Every communication fault notifies the host by SMBALERT#; the ARA read returns the device address and releases it. | 10.2.2, 10.6.1, SMBus A.2 | `pmbus_fault_test`; scoreboard compares SMBALERT# after every message in every run; `cp_alert` |
| REQ-PMB-017 | Every command works with and without PEC. | 10.8.1, SMBus 6.4 | `pmbus_basic_test` (both passes), `pmbus_pec_test`, `pmbus_rand_test`; `cp_pec` |
| REQ-PMB-018 | Both roles: host against the RTL device and against the slave agent in MEM and SEQ mode. | - | `_mem` / `_seq` runs |
| REQ-PMB-019 | PAGE FFh, group command, ZONE, PAGE_PLUS, STORE/RESTORE, fault limits and responses, DIRECT/VID/IEEE formats, BUSY, CONTROL pin. | 4.3, 4.4, 10.5, 10.8.7, 11.x | not verified (not modelled) |

SMBus-level behaviour underneath (timeouts, ARA, PEC arithmetic, every
protocol) is verified by the smbus agent's own requirements (`../smbus/doc/req.md`).

## Traceability: requirement -> submit runs

| Requirement | Runs |
| --- | --- |
| REQ-PMB-001 | all 13 (monitor), pmbus_fault, pmbus_fault_mem, pmbus_fault_seq (injected) |
| REQ-PMB-002, 003, 005, 006, 008, 009, 010, 017 | pmbus_basic, pmbus_basic_mem, pmbus_basic_seq (+ pmbus_rand*, pmbus_page*, pmbus_pec*) |
| REQ-PMB-004 | pmbus_page, pmbus_page_seq, pmbus_basic*, pmbus_rand* |
| REQ-PMB-007, 011, 013, 014, 015, 016 | pmbus_fault, pmbus_fault_mem, pmbus_fault_seq (+ pmbus_page*, pmbus_rand*) |
| REQ-PMB-012 | pmbus_pec, pmbus_pec_seq |
| REQ-PMB-018 | the `_mem` and `_seq` runs |
| REQ-PMB-019 | not verified |

18 requirements verified, 1 not verified.
