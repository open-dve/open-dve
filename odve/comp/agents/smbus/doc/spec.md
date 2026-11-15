# SMBus - protocol summary for verification

## References

| Document | Version | Date | URL | Access |
| --- | --- | --- | --- | --- |
| System Management Bus (SMBus) Specification | 3.3 | 12 May 2024 | http://smbus.org/specs/SMBus_3_3_20240512.pdf | public |
| NXP UM10204, I2C-bus specification and user manual (the bit layer) | Rev. 7.0 | 1 October 2021 | https://www.nxp.com/docs/en/user-guide/UM10204.pdf | public |

Sections read: 4.2.1-4.2.2 (timing, device timeout, Table 2 tTIMEOUT),
5 (bit transfers, START/STOP, ACK/NACK, clock low extending, via the I2C
layer), 6.4 (Packet Error Checking), 6.5.1-6.5.8 (bus protocols), Appendix A.2
(SMBALERT# and the Alert Response Address, Figures 65/66). SMBus 3.x uses
"controller/target"; this agent's roles are named master (host) / slave
(device).

## Signals and electrical model

| Signal | Driven by | Type |
| --- | --- | --- |
| SMBCLK | host (clock), device (clock low extension) | open drain, pull-up |
| SMBDAT | transmitter of the bit; receiver during ACK | open drain, pull-up |
| SMBALERT# | any device wanting attention | open drain, pull-up (wired-AND) |

SMBCLK/SMBDAT are the I2C bus of `odve_i2c_if` (the i2c agent is the
transport); SMBALERT# is `odve_smbus_if`: per-party `*_alert_o/_oe`
(`s_` slave agent, `d_` DUT, `x_` spare) resolved as a pull-up
`alert_n = ~(any pull)`. No tristates.

## Message formats (6.5, `[ ]` = optional PEC)

```
Quick Command      S Addr R/W# A P
Send Byte          S Addr Wr A Data A [PEC A] P
Receive Byte       S Addr Rd A Data [A PEC] N P
Write Byte/Word    S Addr Wr A Cmd A DataL A [DataH A] [PEC A] P
Read Byte/Word     S Addr Wr A Cmd A Sr Addr Rd A DataL [A DataH] [A PEC] N P
Process Call       S Addr Wr A Cmd A DataL A DataH A Sr Addr Rd A DataL A DataH [A PEC] N P
Block Write        S Addr Wr A Cmd A Count=N A D1 A .. DN A [PEC A] P
Block Read         S Addr Wr A Cmd A Sr Addr Rd A Count=N A D1 A .. DN [A PEC] N P
Block W-R Proc.    S Addr Wr A Cmd A M A D1..DM A Sr Addr Rd A N A D1 .. DN [A PEC] N P
ARA (A.2)          S 0001100 Rd A DeviceAddr|x [A PEC] N P
```
The byte count excludes the PEC and may be 0; a block carries at most 255
data bytes (SMBus 3) - the TB device supports 32.

PEC (6.4): CRC-8, C(x) = x^8 + x^2 + x + 1, MSB first, initial value 0, over
every byte of the message from the first START, address bytes (with R/W#)
included, ACK/NACK and START/STOP excluded; appended by the device that sent
the last data byte. A target that supports PEC must accept messages with
and without it, process the message only if the PEC is correct and is
encouraged to NACK a wrong PEC (6.4.1).

```
Read Word with PEC:
SMBDAT  S |addr W|A|cmd|A|Sr|addr R|A|lo|A|hi|A|PEC|N|P
          '---------------- CRC-8 covers all of these ---'
```

## Timeouts and clock extension (4.2.2, Table 2; scaled)

| Parameter | SMBus 3.3 | Here (clk cycles, 1 ms = 20 cycles) |
| --- | --- | --- |
| tTIMEOUT,MIN | 25 ms | 500 (monitor: a message with SMBCLK low this long is a timeout) |
| tTIMEOUT,MAX | 35 ms | 700 (monitor: a target must have released the bus by then) |
| device reset | between MIN and MAX | 600 (DUT `TMO_CYC`, slave agent `t_timeout_dev`) |
| tLOW:SEXT | 25 ms | 500 (monitor: cumulative target stretching per message) |

The bit timing is the i2c agent's (1 cycle = 0.5 us, 100 kHz). The timeout
scale is 100x shorter than the bit scale so a timeout test runs in
microseconds of simulated time; both are configuration fields.

```
SMBCLK  --\__________________________ ... _______/------  host holds SMBCLK low
              |<--------- 600: device resets, releases --->|
              |<---------------- 800: host STOPs --------------->|
```

## SMBALERT# and ARA (A.2)

A device pulls SMBALERT# low; the host reads the Alert Response Address
0001 100 (Receive Byte); only alerting devices ACK it and return their
address in the 7 MSBs; the device stops pulling SMBALERT# after the host
NACKs that byte (end of the read). Writing to the ARA (R/W# = 0) should be NACKed.

## Errors

- Wrong PEC: NACK of the PEC byte (encouraged), message not processed.
- Unsupported command / invalid data: NACK (device choice; I2C 3.1.6 #3).
- Clock low > tTIMEOUT: every device resets its interface.
- START/STOP inside a byte: I2C bus error; the message is dropped.

## Modelled / not modelled

Modelled: Quick Command (W/R), Send/Receive Byte, Write/Read Byte, Write/Read
Word, Process Call, Block Write/Read (0..32 bytes), Block Write-Block Read
Process Call, each with and without PEC; PEC generation and checking on both
sides; SMBALERT# with ARA (with and without PEC); clock-low timeout in the
device and its monitor checks; tLOW:SEXT check; NACK of unsupported
commands, too-large block counts and wrong PECs.

Not modelled: SMBus Host Notify (6.5.9), Write/Read 32 and 64 (6.5.10-13),
Address Resolution Protocol and UDID (6.6), multi-master arbitration,
tLOW:MEXT, tHIGH,MAX bus-idle detection, SMBDAT low timeout (4.2.5),
electrical (DC) specifications, 400 kHz / 1 MHz classes, the host's own
reaction to a device that extends the clock past tTIMEOUT,MIN.

Quick Command read: the device already drives the first data bit when the
host wants to STOP; this works because the TB device's first byte
(STATUS, bit 7 = READY = 1) leaves SMBDAT released. A device whose first read
bit is 0 would block the STOP - an inherent property of the protocol.
