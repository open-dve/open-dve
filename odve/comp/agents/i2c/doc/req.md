# I2C agent - requirements

Spec references are to NXP UM10204 Rev. 7.0 (see `spec.md`). "submit" is
`vrf/work/rlist/submit.list`; every test named there runs on both simulators.
Runs: `<test>` against the RTL target (`+i2c_slave=dut`), `_mem` / `_seq`
against the slave agent in MEM / SEQ mode.

| ID | Requirement | Spec | Verified by |
| --- | --- | --- | --- |
| REQ-I2C-001 | The master generates START, repeated START and STOP (SDA edge while SCL HIGH) and the monitor and both targets recognise them. | 3.1.4 | every test; monitor reconstructs each transfer, scoreboard checks it (any misdetected condition shows as a wrong ACK/data) |
| REQ-I2C-002 | Bytes are 8 bits MSB first followed by an acknowledge clock; data is checked byte by byte. | 3.1.5 | every test; scoreboard compares every written/read byte; coverpoints `cp_nwr`, `cp_nrd` |
| REQ-I2C-003 | A target acknowledges its own 7-bit address and nobody acknowledges an absent address; the master ends a NACKed transfer with STOP. | 3.1.6 (1), 3.1.10 | `i2c_nack_test` (dut, mem); scoreboard address-ACK check; `cp_addr_ack` |
| REQ-I2C-004 | Write transfer: controller-transmitter to target-receiver, any length (0..20 data bytes after the pointer). | 3.1.10 Fig. 11 | `i2c_basic_test`, `i2c_rand_test` (dut, mem, seq); `cp_kind.wr`, `cp_nwr` |
| REQ-I2C-005 | Read transfer: the controller acknowledges every byte but the last, which it NACKs before STOP. The monitor flags an ACKed last byte. | 3.1.6 (5), 3.1.10 Fig. 12 | `i2c_basic_test`, `i2c_rand_test`; monitor `mack_last` check (I2C_BUS_ERR) in every run; `cp_kind.rd` |
| REQ-I2C-006 | Combined format: write, repeated START, read, without releasing the bus. | 3.1.10 Fig. 13 | `i2c_basic_test`, `i2c_rand_test`; `cp_kind.wr_rd`, `cp_seq` |
| REQ-I2C-007 | 10-bit addressing: header 11110 a9 a8 + low byte; A1 by every target matching a9..a8, A2 by the one matching the low byte; read via Sr + header R to the target addressed before; a 10-bit header R after START (not Sr) is not acknowledged. | 3.1.11 Fig. 14, 15 | `i2c_addr10_test` (dut, seq), `i2c_rand_test`, `i2c_nack_test` (header and low-byte mismatch); `x_kind_addr10` |
| REQ-I2C-008 | A target NACKs a data byte it cannot accept (register pointer >= 16); the master stops. | 3.1.6 (3) | `i2c_nack_test`, `i2c_rand_test` (p_bad_ptr); scoreboard per-byte ACK check; `cp_wr_nack.nack` |
| REQ-I2C-009 | General call: the target acknowledges address 0 (write); second byte 06h resets its registers and pointer (software reset); other second bytes are NACKed; the START byte (address 0, read) is acknowledged by nobody. | 3.1.12 Table 4, 3.1.13, 3.1.14 | `i2c_gencall_test` (dut, seq); scoreboard models the reset; `cp_special.gen_call` |
| REQ-I2C-010 | Target register model (TB/DUT design, not spec): first written byte = pointer, auto-increment with wrap 15 -> 0, current-address read keeps the pointer across transfers. | - (DUT definition, `vrf/dut/dut.sv`) | `i2c_basic_test`, `i2c_rand_test`, `i2c_addr10_test`; scoreboard pointer model; `cp_nwr.wrap`, `cp_nrd.wrap` |
| REQ-I2C-011 | Clock stretching: a target may hold SCL low after an acknowledge; the controller waits until SCL is really HIGH before timing tHIGH; the monitor reports stretched transfers. | 3.1.5, 3.1.9 | `i2c_stretch_test` (dut, mem, seq): requires the monitor to see stretching with CTRL != 0 and none with CTRL = 0; scoreboard keeps checking data; `cp_stretch` |
| REQ-I2C-012 | Data validity / SDA ownership: during a bit only its transmitter, during the acknowledge only the receiver may pull SDA. | 3.1.3, 3.1.6 | monitor check (I2C_BUS_ERR) active in every run; no violation is injected (passive verification only) |
| REQ-I2C-013 | A START or STOP inside a byte is flagged by the monitor as a bus error and the transfer reported as aborted. | 3.1.3, 3.1.5 | `i2c_abort_test` (dut, seq): 8 injected aborts (after 1..7 bits of a data byte, inside an address byte), exactly 8 flagged, 7 aborted transfers reported; `cp_special.aborted` |
| REQ-I2C-014 | After an aborted transfer the target drops the partial byte and answers the next transfer normally. | 3.1.4 (S/P reset the target's byte state) | `i2c_abort_test`: full read-back checked by the scoreboard after every abort |
| REQ-I2C-015 | Bus timing: the master meets tLOW, tHIGH, tHD;STA, tSU;STA, tSU;STO, tBUF (cfg, scaled Table 11); the monitor checks tLOW, tHIGH, tHD;STA, tSU;STO, tBUF minima. | Table 11 | monitor I2C_TIMING checks active in every run (0 errors); no violation injected |
| REQ-I2C-016 | Both agent roles work: the master against the RTL target and against the slave agent; the slave agent in MEM (model in the driver) and SEQ (responding sequence) mode. | - (framework) | submit runs with `+i2c_slave=dut|mem|seq` |
| REQ-I2C-017 | Multi-controller arbitration and clock synchronization. | 3.1.7, 3.1.8 | not verified (single controller; not modelled - the master only flags a transmitted 1 read back as 0, `I2C_ARB`) |
| REQ-I2C-018 | Hs-mode, Fast-mode Plus, Ultra Fast-mode, START byte procedure, bus clear, Device ID, general call 04h/hardware general call. | 3.1.15-3.1.17, 5 | not verified (not modelled) |

## Traceability: requirement -> submit runs

| Requirement | Runs |
| --- | --- |
| REQ-I2C-001, 002 | all 16 |
| REQ-I2C-003 | i2c_nack, i2c_nack_mem |
| REQ-I2C-004, 005, 006 | i2c_basic, i2c_basic_mem, i2c_rand, i2c_rand_mem, i2c_rand_seq |
| REQ-I2C-007 | i2c_addr10, i2c_addr10_seq, i2c_rand*, i2c_nack* |
| REQ-I2C-008 | i2c_nack, i2c_nack_mem, i2c_rand* |
| REQ-I2C-009 | i2c_gencall, i2c_gencall_seq |
| REQ-I2C-010 | i2c_basic*, i2c_rand*, i2c_addr10* |
| REQ-I2C-011 | i2c_stretch, i2c_stretch_mem, i2c_stretch_seq |
| REQ-I2C-012, 015 | all 16 (passive) |
| REQ-I2C-013, 014 | i2c_abort, i2c_abort_seq |
| REQ-I2C-016 | the `_mem` and `_seq` runs |
| REQ-I2C-017, 018 | not verified |

16 requirements verified (2 of them passively, without fault injection), 2 not verified.
