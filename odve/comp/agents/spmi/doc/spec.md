# MIPI SPMI - protocol summary for the odve agent

What the `spmi` agent, its RTL slave (`vrf/dut/dut.sv`) and its testbench
implement, written for verification engineers. The MIPI SPMI specification
(v1.0 2008, v2.0 2012) is **members-only**; nothing here is copied from it.
Every fact below is marked with the public source it was taken from, or as an
**assumption** of this model where no public source was found.

## 1. References

| # | Title | Version / date | URL | Access | Used for |
| --- | --- | --- | --- | --- | --- |
| S1 | MIPI Alliance Specification for System Power Management Interface (SPMI) | v2.0 (adopted Q3 2012) | https://www.mipi.org/specifications/system-power-management-interface | **members only - not read** | (authoritative; not available) |
| S2 | MIPI Alliance, "MIPI SPMI System Power Management Interface" overview slides (MIPI_SPM_Interface_Overview_r01.pdf) | 2012 | https://www.mipi.org/hubfs/MIPI_SPM_Interface_Overview_r01.pdf | public | 2-wire bidirectional SDATA/SCLK; up to 4 masters, up to 16 slaves; SCLK only during a transaction; LS 32 kHz-15 MHz, HS 32 kHz-26 MHz; master and slave arbitration; slave group IDs; 8-/16-bit addressing; bursts up to 16 bytes (8-bit address) / 8 bytes (16-bit address); **odd parity**; "ACK/NACK on certain commands (SPMI v2.0)"; v2.0 masters work with v1.0 non-request-capable slaves "if the Master ignores the value present on SDATA during the ACK/NACK cycle"; dedicated Reset, Sleep, Shutdown, Wakeup, Authenticate commands; Register 0 Write; pull-down on SDATA (device or PCB); 1.2/1.8 V; 50 pF |
| S3 | Linux kernel `include/linux/spmi.h`, `drivers/spmi/spmi.c` | v6.6 (2023) | https://github.com/torvalds/linux/blob/v6.6/include/linux/spmi.h | public (GPL) | command codes: `EXT_WRITE 0x00`, `RESET 0x10`, `SLEEP 0x11`, `SHUTDOWN 0x12`, `WAKEUP 0x13`, `AUTHENTICATE 0x14`, `MSTR_READ 0x15`, `MSTR_WRITE 0x16`, `TRANSFER_BUS_OWNERSHIP 0x1A`, `DDB_MASTER_READ 0x1B`, `DDB_SLAVE_READ 0x1C`, `EXT_READ 0x20`, `EXT_WRITEL 0x30`, `EXT_READL 0x38`, `WRITE 0x40`, `READ 0x60`, `ZERO_WRITE 0x80`; limits: register read/write 5-bit address, extended 8-bit address 1..16 bytes, extended long 16-bit address 1..8 bytes, zero write = 7-bit data to register 0 |
| S4 | Prodigy Technovations, "SPMI Protocol Introduction" | web page (prodigytechno.com/?p=19673), read 2026-11-15 | https://www.prodigytechno.com/?p=19673 | public | SSC = "rising edge followed by a falling edge on SDATA while SCLK remains at a logic low level" (master drives SDATA high one period, low one period); command frame 13 bits (4-bit address, 8-bit command, parity); data/address frames 9 bits; a command sequence = bus arbitration, SSC, frames, ACK/NACK (for command sequences that have it), bus park; SCLK controlled by the master |
| S5 | US patent 10,496,568, "Technique for RFFE and SPMI register-0 write datagram functional extension" | granted 2019 | https://patents.google.com/patent/US10496568 | public (read via Google Patents) | SPMI and RFFE share the command frame (SSC, 4-bit slave address, 8-bit command code, parity) and the Register-0 Write (the only code with MSB 1, 7 data bits) |
| S6 | US patents 12,164,460 and 11,360,916 (SPMI acknowledgement) | 2024 / 2022 | https://patents.google.com/patent/US12164460 | public - **only search-engine excerpts were read** | ACK/NACK is sent after the first bus park and may be followed by a second bus park; a receiver that does not drive leaves the line low (keeper / pull-down). The two patents describe the ACK polarity differently. |
| S7 | Tektronix application note "Debugging SPMI power management buses with an oscilloscope" | - | https://www.tek.com/en/documents/application-note/debugging-spmi-power-management-buses-oscilloscope | public - **not readable here (HTTP 403)**; the search-engine excerpt says the SSC is a positive pulse on SDATA while SCLK is low | SSC (confirms S4) |

Not available and not used: the SPMI specification text (S1): exact
ACK/NACK timing and polarity, the bus park definition, arbitration
sequences, timing tables.

## 2. Signals and electrical model

| Signal | Driven by | Notes |
| --- | --- | --- |
| `SCLK` | the bus owner master only, and only during a sequence [S2, S4] | the agent's master driver generates it from the TB clock |
| `SDATA` | master during its frames and bus park; the addressed slave during read data, the ACK/NACK bit and its bus park | bidirectional [S2] |

SDATA is push-pull with a pull-down [S2] (modelled as a bus keeper that holds
the last value, which is 0 after every bus park). In the testbench there is
**no `inout`/`tri`**: every driver has its own `*_o`/`*_oe` (`odve_spmi_if`:
`m_sdata_o/oe`, `s_sdata_o/oe`; the RTL slaves' `sdata_o/sdata_oe` ports) and
`vrf/tb/top.sv` resolves the line from the enables; `oe_all` carries every
enable to the monitor, which flags contention.

Clocking model (**assumption**, the same as the RFFE agent, whose public
sources state the falling-edge sampling): a bit is launched at the SCLK
rising edge and sampled at the falling edge; SCLK and SDATA are low when the
bus is idle (**assumption**; a search-engine summary of the vendor pages said
the same, the pages read here did not state it).

## 3. Sequence structure and timing

```
         SSC         command frame (13 bits)      address/data frames       BPC   ACK  BPC
SCLK  ____________/~\_/~\_ ... /~\_/~\_ ... /~\_/~\_ ... /~\_/~\_          /~\_  /~\_ /~\_
SDATA __/~~~~\____<S3><S2>... <C0>< P ><A7>... < P ><D7>... < P >        <0>z  <A>  <0>z
        SSC        master                                                 mst   slv  slv
```

- **Bus arbitration** [S2, S4]: not modelled - the agent is the only master
  and owns the bus; no request-capable slaves (see 7).
- **SSC** [S4, S7]: SDATA high for one SCLK period then low for one, SCLK low.
- **Command frame** [S4, S5]: `SA[3:0]` (SID), `C[7:0]`, parity - 13 bits.
- **Address / data frames** [S4]: 8 bits MSB first + parity.
- **Parity** [S2]: odd.
- **Bus park (BPC)** (**assumption**, taken over from RFFE): the current
  driver drives 0 while SCLK is high and releases at the falling edge.
- **ACK/NACK** [S2, S6; timing and polarity are **assumptions**]: every
  non-read command (Register 0 Write, all writes, Reset/Sleep/Shutdown/Wakeup)
  ends with: master BPC, one ACK/NACK bit driven by the addressed slave
  (**1 = ACK**, 0 = NACK; a slave that does not respond leaves the parked 0,
  i.e. NACK), slave BPC. Reads have no ACK/NACK bit (their data frames carry
  parity).
- **Read**: master BPC after its last frame, the slave's data frames, slave
  BPC (as in RFFE; **assumption** for SPMI).

## 4. Command sequences

Slave ID: 4 bits, up to 16 slaves [S2]. Register addresses: 5 / 8 / 16 bits
[S3]. Multi-byte accesses address consecutive registers; extended addresses
wrap at 8 bits, long at 16 (**assumption**).

| Kind (`odve_spmi_kind_e`) | Command field [S3] | Frames after the command | Bytes [S3] | ACK/NACK |
| --- | --- | --- | --- | --- |
| Register 0 Write | `1DDD_DDDD` | none | 7 bits | yes |
| Register Write | `010A_AAAA` | 1 data | 1 | yes |
| Register Read | `011A_AAAA` | BPC, 1 data (slave), BPC | 1 | - |
| Extended Register Write | `0000_BBBB` | 1 address, BC+1 data | 1..16 | yes |
| Extended Register Read | `0010_BBBB` | 1 address, BPC, BC+1 data, BPC | 1..16 | - |
| Extended Register Write Long | `0011_0BBB` | 2 address, BC+1 data | 1..8 | yes |
| Extended Register Read Long | `0011_1BBB` | 2 address, BPC, BC+1 data, BPC | 1..8 | - |
| Reset | `0001_0000` | none | - | yes |
| Sleep | `0001_0001` | none | - | yes |
| Shutdown | `0001_0010` | none | - | yes |
| Wakeup | `0001_0011` | none | - | yes |
| Authenticate `0x14`, Master Read/Write `0x15/0x16`, Transfer Bus Ownership `0x1A`, DDB reads `0x1B/0x1C` | | **not modelled**: the RTL slave ignores them, the monitor reports "unsupported command" | | |

Which commands carry ACK/NACK: S2 says "certain commands"; the choice above
(every non-read) is an **assumption**.

Effect of the PM commands in this model (**assumption** - the public sources
name the commands only): Reset clears the slave's registers and sets the
power state ACTIVE; Sleep -> SLEEP; Shutdown -> SHUTDOWN; Wakeup -> ACTIVE.
The slave keeps answering every command in every state. The RTL slave and
the slave agent expose the state as a read-only register at address 0x40
(`NREG`): 0 ACTIVE, 1 SLEEP, 2 SHUTDOWN (and as the RTL port `pm_state`).

## 5. Error and special conditions

| Condition | Model | Source |
| --- | --- | --- |
| Parity error in the command frame | the slave ignores the sequence: no ACK (NACK seen), no read data (NRF) | assumption |
| Parity error in an address frame | write: nothing written, NACK; read: ignored (NRF) | assumption |
| Parity error in a write data frame | that frame and the following ones dropped, earlier ones written, NACK | assumption |
| Command to an absent SID | nobody drives: NACK / NRF | S6 (undriven line reads low) |
| Read of an unimplemented register | No Response Frame: nine zeros, parity included, driven by the slave | assumption (taken over from RFFE) |
| Write to an unimplemented / read-only register | ignored, ACK | assumption |
| SSC inside a sequence | slaves restart; monitor reports an aborted sequence | assumption |
| Contention, data change at the sampling edge, wrong driver, non-zero BPC | monitor errors | model checks |

## 6. Timing parameters the agent models

| Knob | Default | Meaning |
| --- | --- | --- |
| `cfg.sclk_half` | 2 | TB clocks (10 ns) per SCLK half period: SCLK = 25 MHz in simulation (S2 allows up to 26 MHz HS). >= 2: the RTL slave oversamples and answers one clock after an edge. |
| `cfg.idle_halfs` | 4 | idle half periods between sequences (0 = back to back) |

No analog timing is modelled.

## 7. Modelled / not modelled

Modelled: SSC, command/address/data frames, odd parity, Register 0 Write,
Register Write/Read, Extended Register Write/Read (1..16), Extended Register
Write/Read Long (1..8), Reset/Sleep/Shutdown/Wakeup, ACK/NACK, bus park, read
turnaround, NRF, parity-error handling, back-to-back sequences, **one master
with two slaves** (SID 5: RTL or slave agent; SID A: RTL).

Not modelled: **bus arbitration** (master/slave arbitration, A-bit and
SR-bit, priority levels, round robin) - with a single master the master
simply starts with the SSC; multiple masters, request-capable slaves,
Master Read/Write, Transfer Bus Ownership, Authenticate, DDB reads, group
slave IDs, SPMI v1.0 compatibility mode (ignoring the ACK cycle), the power
state's effect on command acceptance, low/high speed classes beyond the
cycle model, analog timing.
