# PMBus - protocol summary for verification

## References

| Document | Version | Date | URL | Access |
| --- | --- | --- | --- | --- |
| PMBus Power System Management Protocol Specification, Part I - General Requirements, Transport and Electrical Interface | Rev. 1.3.1 | 13 March 2015 | https://pmbus.org/wp-content/uploads/2022/01/PMBus-Specification-Rev-1-3-1-Part-I-20150313.pdf | public (archive) |
| PMBus Power System Management Protocol Specification, Part II - Command Language | Rev. 1.3.1 | 13 March 2015 | https://pmbus.org/wp-content/uploads/2022/01/PMBus-Specification-Rev-1-3-1-Part-II-20150313.pdf | public (archive) |
| SMBus Specification (transport) | 3.3 | 12 May 2024 | http://smbus.org/specs/SMBus_3_3_20240512.pdf | public |

The current PMBus revision (1.4, per the pmbus.org specification archive
page) is free but requires registration; it was not used. Revision 1.3.1 is
the newest one downloadable without registration from the pmbus.org
archive. Sections read in Part II: 7.3 (LINEAR11), 8.3-8.4.1 (VOUT_MODE,
ULINEAR16), 10.2.3-10.2.5 (clearing status bits), 10.6.1 (SMBALERT#), 10.8
(data transmission faults), 10.9 (data content faults), 11.10 (PAGE), 12.1
(OPERATION), 12.2 (ON_OFF_CONFIG), 15.1 (CLEAR_FAULTS), 17.1/17.2
(STATUS_BYTE/STATUS_WORD), 17.7 table of STATUS_CML bits, 22.1
(PMBUS_REVISION), Appendix I Table 31 (command summary). Part I was only
skimmed (title, structure); its transport chapter defers to SMBus.

## Signals and electrical model

PMBus uses the SMBus signals: SMBCLK, SMBDAT (open drain, the i2c agent's
`odve_i2c_if`) and SMBALERT# (`odve_smbus_if`). The optional CONTROL pin is
not modelled (taken as asserted). No tristates: per-party pulls resolved as
pull-ups (see the i2c and smbus specs).

## Message formats

Every PMBus command is an SMBus message of the type given by Table 31
(Part II 5.4: all packets start with a write address and the command code):

```
Write Byte  OPERATION   S 40h Wr A 01h A Data A [PEC A] P
Read Word   READ_IOUT   S 40h Wr A 8Ch A Sr 40h Rd A Low A High [A PEC] N P
Send Byte   CLEAR_FAULTS S 40h Wr A 03h A [PEC A] P
```

Commands used here (Table 31):

| Code | Name | Write | Read | Bytes | Format |
| --- | --- | --- | --- | --- | --- |
| 00h | PAGE | Write Byte | Read Byte | 1 | raw |
| 01h | OPERATION | Write Byte | Read Byte | 1 | bits |
| 02h | ON_OFF_CONFIG | Write Byte | Read Byte | 1 | bits |
| 03h | CLEAR_FAULTS | Send Byte | - | 0 | - |
| 19h | CAPABILITY | - | Read Byte | 1 | bits |
| 20h | VOUT_MODE | Write Byte | Read Byte | 1 | mode + exponent |
| 21h | VOUT_COMMAND | Write Word | Read Word | 2 | ULINEAR16 |
| 78h | STATUS_BYTE | Write Byte | Read Byte | 1 | bits |
| 79h | STATUS_WORD | Write Word | Read Word | 2 | bits |
| 7Eh | STATUS_CML | Write Byte | Read Byte | 1 | bits |
| 8Bh | READ_VOUT | - | Read Word | 2 | ULINEAR16 |
| 8Ch | READ_IOUT | - | Read Word | 2 | LINEAR11 |
| 98h | PMBUS_REVISION | - | Read Byte | 1 | 2 x 4 bits |

The agent also names (for decoding) PHASE, WRITE_PROTECT, STORE/RESTORE_DEFAULT_ALL,
VOUT_TRIM, VOUT_CAL_OFFSET, VOUT_MAX, STATUS_VOUT, STATUS_IOUT, READ_VIN,
READ_TEMPERATURE_1, MFR_ID; the TB device does not support them.

## Data formats

```
LINEAR11 (7.3)          | N (5 bit, 2's c.) | Y (11 bit, 2's complement) |   X = Y * 2^N
                          15             11   10                        0
VOUT_MODE (8.3)         | rel | mode[1:0] | parameter (5) |  mode 00 = ULINEAR16, parameter = exponent N
ULINEAR16 (8.4.1.1)     | V (16 bit unsigned) |   Voltage = V * 2^N, N from VOUT_MODE
```
Examples: F00Ah = 10 * 2^-2 = 2.5 A; with VOUT_MODE 17h (N = -9) 0266h = 1.199 V.

## Paging (11.10)

PAGE selects which output the following commands address; pages 00h-1Fh
are for multiple outputs, FFh means all outputs. The TB device has pages 0
and 1; OPERATION, ON_OFF_CONFIG, VOUT_COMMAND, STATUS_BYTE/WORD, READ_VOUT,
READ_IOUT are per page.

## Status and faults

STATUS_BYTE (17.1): 7 BUSY, 6 OFF, 5 VOUT_OV, 4 IOUT_OC, 3 VIN_UV, 2
TEMPERATURE, 1 CML, 0 NONE_OF_THE_ABOVE. STATUS_WORD (17.2) = STATUS_BYTE +
high byte (7 VOUT, 6 IOUT/POUT, 5 INPUT, 4 MFR, 3 PG_STATUS#, 2 FANS, 1
OTHER, 0 UNKNOWN). STATUS_CML: 7 invalid/unsupported command, 6 invalid/
unsupported data, 5 PEC failed, 1 other communication fault.

| Fault (Part II) | Device response |
| --- | --- |
| Corrupted data / PEC (10.8.1) | NACK the PEC (preferred), ignore the command, CML + bit 5, notify |
| Too few bits, START/STOP in a byte (10.8.2/3) | flush, CML + bit 1, notify |
| Host sends too few bytes (10.8.4) | preferably no error |
| Host sends too many bytes (10.8.5) | NACK the extra bytes, flush, CML + bit 6, notify |
| Reading too many bytes (10.8.6) | send FFh, CML + bit 1, notify |
| Read bit set at the start (10.9.1) | ACK the address, send FFh, CML + bit 1, notify |
| Unsupported command (10.9.2) | NACK the code and data, flush, CML + bit 7, notify |
| Invalid or unsupported data (10.9.3) | NACK the data if possible, flush, CML + bit 6, notify |

Status bits stay set until cleared by writing 1s to that status register
(10.2.4, not STATUS_BYTE/WORD), CLEAR_FAULTS (15.1, also releases
SMBALERT#) or power; OFF and PG_STATUS# always show the current state.
Notification is SMBALERT# + ARA (10.6.1, SMBus A.2).

## The TB device (`vrf/dut/dut.sv`, `odve_pmbus_dev_model`)

Address 40h, pages 0/1, VOUT_MODE fixed 17h (ULINEAR16, N = -9),
CAPABILITY 90h (PEC, 100 kHz, SMBALERT#), PMBUS_REVISION 33h, OPERATION
accepted when bits [5:4] = 00 and [1:0] = 00 (no margining, AVSBus,
reserved bit), ON_OFF_CONFIG when bits [7:5] = 0, output on =
!OOC[4] || !OOC[3] || OPERATION[7], READ_VOUT = VOUT_COMMAND when on,
READ_IOUT = 2.5 A / 1.25 A when on. STATUS_BYTE/WORD/CAPABILITY/READ_*/
PMBUS_REVISION are read only (a data byte to them is NACKed, CML bit 7).
Timeouts and START/STOP inside a byte set CML bit 1.

## Modelled / not modelled

Modelled: the 13 commands above on two pages, with and without PEC;
LINEAR11 and ULINEAR16 encoding/decoding; STATUS_BYTE, STATUS_WORD (OFF,
CML, PG_STATUS#), STATUS_CML; the fault responses of the table; SMBALERT#
with ARA, CLEAR_FAULTS, bit clearing of STATUS_CML; monitor checks that a
command uses its Table 31 protocol and that no message starts with a read.

Not modelled: PAGE FFh (all pages - rejected as invalid data by the TB
device), group command (4.3), ZONE_READ/WRITE, PAGE_PLUS_READ/WRITE, the
memory model (STORE/RESTORE), fault limits and responses, warnings,
VOUT_TRIM/MARGIN/MAX/scale loop, DIRECT, VID and IEEE half-precision
formats, the CONTROL pin, BUSY (10.8.7), writing STATUS_BYTE (BUSY clear)
and STATUS_WORD, manufacturer commands, AVSBus (Part III), Part I
electrical specifications.

Design choice: a host that sends a Write Word to a byte command without PEC
looks, on the bus, exactly like a Write Byte with PEC; the device checks the
extra byte as a PEC and reports a PEC failure (bit 5) unless it happens to
be the correct PEC. The "too many bytes" case (bit 6) is the byte after
that.
