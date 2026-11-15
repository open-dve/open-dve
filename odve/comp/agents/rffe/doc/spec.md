# MIPI RFFE - protocol summary for the odve agent

What the `rffe` agent, its RTL slave (`vrf/dut/dut.sv`) and its testbench
implement, written for verification engineers. The MIPI RFFE specification
itself is **members-only**; nothing here is copied from it. Every fact below is
marked with the public source it was taken from, or as an **assumption** of
this model where no public source was found.

## 1. References

| # | Title | Version / date | URL | Access | Used for |
| --- | --- | --- | --- | --- | --- |
| R1 | MIPI Alliance Specification for RF Front-End Control Interface (RFFE) | v1.x / v2.x / v3.0 | https://www.mipi.org/specifications/rf-front-end | **members only - not read** | (authoritative; not available) |
| R2 | National Instruments, "MIPI RFFE Communication for RF Semiconductor Devices" (white paper) | web page, read 2026-11-15 | https://www.ni.com/en/solutions/semiconductor/rf-validation-characterization/5g-device-validation/mipi-rffe-communication-for-rf-semiconductor-devices.html | public | command list with address widths and byte counts; "No Response Frame (all 0s)"; 2 uA pull-downs per slave; ~10 MHz typical rate |
| R3 | Prodigy Technovations, "RFFE protocol" article | web page (prodigytechno.com/?p=19604), read 2026-11-15 | https://prodigytechno.com/?p=19604 | public | SSC definition, 13-bit command frame (4-bit SA + 8-bit command + parity), 9-bit data/address frames, odd parity, NRF all zero incl. parity (active or passive), SCLK always from the bus owner master, SDATA bidirectional for read-capable slaves, v1 single master / v2 up to 4 masters |
| R4 | US patent 10,970,243, "Front end serial bus automatic bus park tri-state activation" | granted 2021 | https://patents.google.com/patent/US10970243 | public (read via Google Patents) | "half of a clock cycle for the current driver to drive the data bus line to a logic low and then tristate" (bus park); "An SREAD command allows for the RFFE bus master ... to sample the data bus line not on the falling edge of the serial clock (SCLK) but instead on the following rising clock edge"; master samples read data at falling edges otherwise; read frame = SSC (SCLK held 0), SA[3:0], CMD[2:0], ADDR[4:0], parity, then D[7:0] from the slave, ending with a bus park |
| R5 | US patent 10,496,568, "Technique for RFFE and SPMI register-0 write datagram functional extension" | granted 2019 | https://patents.google.com/patent/US10496568 | public (read via Google Patents) | SSC, 4-bit slave address, 8-bit command code, parity bit (P) - the same for RFFE and SPMI; "the lone command code having a most significant bit of '1' corresponds to a Register-0 Write command" (7-bit data); register commands: 5 address bits + one 8-bit data frame; extended: 8 address bits, up to 16 bytes; extended long: 16-bit address, up to 8 bytes; "up to 15 slave devices may be coupled to one RFFE bus" |
| R6 | TI E2E forum thread "extended write format for LM8335 not working" | 2016 | https://e2e.ti.com/support/interface-group/interface/f/interface-forum/499889/extended-write-format-for-lm8335-not-working | public - **only the search-engine excerpt was read** | the extended register write auto-increments the register address for each data byte (the device conforms to RFFE v1.10) |
| R7 | Linux kernel `include/linux/spmi.h`, `drivers/spmi/spmi.c` (v6.6) | 2023 | https://github.com/torvalds/linux/blob/v6.6/include/linux/spmi.h | public (GPL) | SPMI command codes, which RFFE shares for the command subset modelled here (see 4.2) |

Not available and not used: the RFFE specification text (R1), its timing
tables, the trigger / masked-write / interrupt chapters.

## 2. Signals and electrical model

| Signal | Driven by | Notes |
| --- | --- | --- |
| `SCLK` | the (bus owner) master only [R3] | the agent's master driver generates it from the TB clock |
| `SDATA` | master during command/address/write data frames and its bus park; the addressed slave during read data frames and its bus park [R3, R4] | bidirectional |
| `VIO` | - | not modelled (no power / reset pin model) |

SDATA is push-pull with a bus keeper/weak pull-down (R2 mentions per-slave
pull-downs). In the testbench there is **no `inout`/`tri`**: every driver has
its own `*_o`/`*_oe` (`odve_rffe_if`: `m_sdata_o/oe` for the master agent,
`s_sdata_o/oe` for the slave agent; the RTL slaves have `sdata_o/sdata_oe`
ports), and `vrf/tb/top.sv` resolves the line: the enabled driver's value, or
the bus keeper's last value when nobody drives (0 after every bus park).
`oe_all` carries every enable to the monitor, which flags contention (two
enables at once).

Clocking model: receivers sample at the SCLK falling edge (R4: the master
samples read data "during each falling clock edge" unless SREAD); the bit is
launched at the rising edge (**assumption**, consistent with R4's slave
flip-flop that follows the data while SCLK is high); SCLK and SDATA are low
when the bus is idle (**assumption**).

## 3. Sequence structure and timing

```
            SSC         command frame (13 bits)        address/data frames (9 bits each)   BPC
SCLK  ______________/~\_/~\_/~\ ... /~\_/~\_/~\_ ... _/~\_/~\ ... /~\_/~\_______________/~\______
SDATA ____/~~~~~\___< S3>< S2>...<C0>< P ><A7>...<A0>< P ><D7>...< P >                 <0 >-z--
          SSC: SDATA high then low, SCLK low        each frame MSB first, odd parity      bus park
```

- **SSC** [R3]: SDATA rises and then falls while SCLK stays low (master drives
  it high for one SCLK period, then low for one). The agent's master holds
  each level for one SCLK period (2 x `sclk_half` TB clocks). An SSC is
  unique on the bus because data only changes while SCLK is high.
- **Command frame** [R3, R5]: `SA[3:0]` (USID), `C[7:0]`, parity `P` - 13 bits.
- **Address / data frame** [R3]: 8 bits MSB first + parity.
- **Parity** [R3]: odd - the number of ones in the frame including `P` is odd.
- **Bus park cycle (BPC)** [R4]: one SCLK cycle; the current SDATA driver
  drives 0 while SCLK is high and releases SDATA at the falling edge.
- **Write**: SSC, command frame, address frame(s), data frame(s), master BPC.
- **Read** [R4 for the hand-over; turnaround details are an **assumption**]:

```
SCLK  ... _/~\_/~\_  /~\_   /~\_/~\_ ... /~\_  /~\_
SDATA ... <A0>< P >  <0>z   <D7><D6> ... < P >  <0>z
          master     master  slave (data frames)  slave
                     BPC                          BPC
```
  The master parks the bus after its last frame; the addressed slave drives
  the data frames from the next rising edge, then parks the bus itself.
- **Half-speed read** [R4]: the master may clock the read data frames at a
  lower rate and sample on the following rising edge (SREAD). Modelled as
  `cfg.half_speed_read`: read data frames at half the SCLK rate, sampled at
  the next rising edge; the RTL slave needs no change (it reacts to edges).
  Whether the spec halves exactly or allows any lower rate: not known (R1).

## 4. Command sequences

### 4.1 Addressing

- 4-bit USID in the command frame [R3, R5]. **USID 0 is the broadcast ID**:
  every slave accepts a write to it; reads are not sent to USID 0. R5's "up
  to 15 slave devices" on one bus is consistent with one of the 16 IDs being
  reserved, but the broadcast rule itself is from the task brief and common
  RFFE usage, not from a document read here (**assumption**). The monitor flags a read to USID 0 as an error.
- Register address: 5 bits (register commands), 8 bits (extended), 16 bits
  (extended long) [R2, R5].
- Multi-byte accesses address consecutive registers [R6]. **Assumption:**
  extended addresses wrap at 8 bits, long ones at 16 bits.

### 4.2 Command codes

The command-field encodings below are the ones the Linux SPMI core uses
(R7: `SPMI_CMD_EXT_WRITE 0x00`, `EXT_READ 0x20`, `EXT_WRITEL 0x30`,
`EXT_READL 0x38`, `WRITE 0x40`, `READ 0x60`, `ZERO_WRITE 0x80`); RFFE uses the
same frame format and command set for these sequences (R5 treats "RFFE and
SPMI" Register-0 Write as the same datagram). That RFFE reuses the SPMI codes
bit for bit is an **assumption** (no public RFFE code table was found).

| Kind (`odve_rffe_kind_e`) | Command field | Frames after the command | Bytes | Source |
| --- | --- | --- | --- | --- |
| Register 0 Write | `1DDD_DDDD` | none (7 data bits in the command) | 7 bits | R2, R5, R7 |
| Register Write | `010A_AAAA` | 1 data | 1 | R2, R7 |
| Register Read | `011A_AAAA` | BPC, 1 data (slave), BPC | 1 | R2, R7 |
| Extended Register Write | `0000_BBBB` | 1 address, BC+1 data | 1..16 | R2, R7 |
| Extended Register Read | `0010_BBBB` | 1 address, BPC, BC+1 data, BPC | 1..16 | R2, R7 |
| Extended Register Write Long | `0011_0BBB` | 2 address (MSB first), BC+1 data | 1..8 | R5, R7 (R2's table says "up to 16" for the write; R5 says up to 8 and the 3-bit BC field allows 8 - the agent uses 8) |
| Extended Register Read Long | `0011_1BBB` | 2 address, BPC, BC+1 data, BPC | 1..8 | R2, R7 |
| (`0001_xxxx`: masked write, other v2 codes) | - | not modelled: the RTL slave ignores them, the monitor reports "unsupported command" | | |

Register 0 Write sets register 0 to `{0, D[6:0]}` (bit 7 cleared:
**assumption**).

## 5. Error and special conditions

| Condition | Model | Source |
| --- | --- | --- |
| No Response Frame (NRF) | a data frame of all zeros including parity; a slave not addressed leaves SDATA undriven (passive: the parked 0 is read), an addressed slave reading an unimplemented register drives nine zeros (active). Not a parity error. | R2, R3 |
| Parity error in the command frame | the slave ignores the sequence (reads: passive NRF) | **assumption** |
| Parity error in an address frame | the slave ignores the sequence | **assumption** |
| Parity error in a write data frame | that frame and the following ones are dropped; earlier frames are written (the RTL slave writes each frame as it arrives) | **assumption** |
| Write to an unimplemented register | ignored | **assumption** |
| SSC inside a sequence | the slaves restart on it; the monitor reports an aborted sequence | **assumption** |
| Contention, data change at the sampling edge, wrong driver, non-zero BPC | monitor errors | model checks |

## 6. Timing parameters the agent models

| Knob | Default | Meaning |
| --- | --- | --- |
| `cfg.sclk_half` | 2 | TB clocks (10 ns) per SCLK half period: SCLK = 25 MHz in simulation. Must be >= 2, because the RTL slave oversamples and answers one clock after an SCLK edge. Real RFFE rates (R2: ~10 MHz typical) are not otherwise modelled. |
| `cfg.idle_halfs` | 4 | idle half periods between sequences (0 = back to back) |
| `cfg.half_speed_read` | 0 | read data frames at half rate, sampled on the next rising edge |

No analog timing (setup/hold in ns, slew limits, VIO levels) is modelled; the
monitor's "SDATA changed at the falling edge" check is the cycle-level
equivalent of setup.

## 7. Modelled / not modelled

Modelled: SSC, command/address/data frames, odd parity on every frame,
Register 0 Write, Register Write/Read, Extended Register Write/Read (1..16),
Extended Register Write/Read Long (1..8), bus park cycle, read turnaround,
half-speed read, broadcast USID 0 for writes, NRF (active and passive),
parity-error handling in the slave, back-to-back sequences, one master with
two slaves (one RTL + RTL or slave agent).

Not modelled: multi-master operation and bus ownership hand-over (RFFE v2),
masked write and the other `0001_xxxx` codes, trigger registers
(`PM_TRIG` etc.), USID programming sequences, the standard registers
(product/manufacturer ID, `PM_TRIG`, USID register), interrupts / Synchronous
Read (v2.1+), extended clock rates, VIO / power-up behaviour, analog timing.
