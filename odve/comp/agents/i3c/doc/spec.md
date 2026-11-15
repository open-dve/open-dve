# I3C (SDR) - protocol summary for verification

What the `i3c` agent and its RTL target model, written for verification
engineers. It is a summary, not the specification: where the two disagree,
the specification wins.

## 1. References

| Document | Version / date | URL | Access | Used for |
| --- | --- | --- | --- | --- |
| MIPI I3C Basic(SM) Specification | v1.2 (announced 6 Aug 2025); earlier public versions v1.0 (Dec 2018), v1.1.1 | https://www.mipi.org/mipi-i3c-basic-download (v1.2), https://www.mipi.org/mipi-i3c-basic-download-previous-versions | public (royalty-free, download after a request form) | the governing document. **Not read for this work**: the PDF is delivered after a web form, which could not be completed here. No section numbers of it are quoted below. |
| MIPI I3C / I3C Basic FAQ | web page, read 2026-11 | https://www.mipi.org/resources/I3C-frequently-asked-questions | public | SDR rate, push-pull vs open-drain, address arbitration, ENTDAA, 48-bit Provisioned ID, BCR/DCR, IBI with MDB and T-bit end, Hot-Join, CCC broadcast address 7'h7E, I3C Basic vs I3C feature differences, HDR mode list |
| MIPI press release "MIPI Releases I3C Basic v1.2" | 6 Aug 2025 | https://www.mipi.org/press-releases/mipi-releases-i3c-basic-v1-2-utility-and-control-bus-interface-for-mobile-iot-data-center-applications | public | current public version, positioning (subset of member I3C, typical 11.1 Mbps) |
| Linux kernel documentation, "I3C protocol" | kernel docs, read 2026-11 | https://docs.kernel.org/driver-api/i3c/protocol.html | public | DAA reports PID + BCR + DCR, IBI priority = lower dynamic address wins, CCC ID bit 7 = broadcast(0)/direct(1), read CCCs are direct only, payload length implied by the CCC, Hot-Join flow |
| Linux kernel `include/linux/i3c/ccc.h` | master, read 2026-11 | https://github.com/torvalds/linux/blob/master/include/linux/i3c/ccc.h | public (GPL source) | CCC code values (ENEC 0x00/0x80, DISEC 0x01/0x81, RSTDAA 0x06, ENTDAA 0x07, SETMWL 0x09/0x89, SETDASA 0x87, GETMWL 0x8B, GETPID 0x8D, GETBCR 0x8E, GETDCR 0x8F, GETSTATUS 0x90), ENEC/DISEC event bits (SIR bit 0, HJ bit 3), GETSTATUS bits (protocol error bit 5, pending interrupt [3:0], activity mode [7:6]) |
| MIPI I3C (full) Specification v1.1.1 / v1.2 | - | https://www.mipi.org/specifications/i3c-sensor-specification | MIPI members only | not available |

The CCC codes, event bits and GETSTATUS bits come from `ccc.h` above. Other
bit-level details that none of the sources read here spell out - the write
T-bit being odd parity, the ENTDAA frame layout (64 ID bits, 7-bit address +
odd parity, ACK), BCR bits [2:1], the Hot-Join address 7'h02, the T-bit
release on SCL rising - are written from general knowledge of I3C SDR as
published by controller vendors; they are marked *(public implementations)*
and must be checked against the I3C Basic PDF before the agent is used for
sign-off.

## 2. Signals and electrical model

| Signal | Driven by | Mode |
| --- | --- | --- |
| SCL | controller only | push-pull, always (SDR has no clock stretching) |
| SDA | controller and targets | open-drain (+ pull-up / high-keeper) in arbitration phases and ACK bits; push-pull for data, CCC codes, T-bits |

| Phase | SDA mode | Who drives |
| --- | --- | --- |
| START, STOP, repeated START (Sr) | - | controller (a target may pull SDA low on an idle bus to *request* a START: IBI / Hot-Join) |
| address header after START (7 bits + RnW) | open-drain | controller, and any target arbitrating an IBI / Hot-Join; 0 wins |
| address header after Sr | push-pull (model choice: no arbitration after Sr) | controller |
| ACK/NACK of a header | open-drain | addressed target(s) (for an IBI: the controller) |
| write data + T (parity) | push-pull | controller |
| read data + T (end of data) | push-pull, released on SCL rising after T=1 | target; the controller may then pull SDA low (Sr) to abort |
| ENTDAA ID (64 bits), address + parity, ACK | open-drain (model: all of the round) | targets without an address (arbitrated) / controller / winner |

In the testbench every SDA driver has its own `*_sda_oe` / `*_sda_o` /
`*_sda_pp` (controller `m_`, target agent `t_`, RTL target `d_`), and the
interface resolves the bus with plain logic - no `inout`, `tri` or `wand`:

```
pull_low   = |(oe & ~o)                 // anyone driving 0 (open-drain or push-pull)
drive_hi   = |(oe &  o)                 // anyone driving 1 (push-pull only)
sda        = ~pull_low                  // pull-up / high-keeper
contention = pull_low & drive_hi        // flagged by the monitor
```

## 3. Bus conditions and bit timing

SDA may change only while SCL is low; an SDA edge while SCL is high is a
condition:

```
           START             data bit            Sr                 STOP
SCL  ‾‾‾‾‾‾‾‾‾‾‾\______/‾‾‾‾‾‾\______/‾‾‾‾‾‾‾‾‾‾‾\______/‾‾‾‾‾‾‾‾‾‾‾\
SDA  ‾‾‾‾‾‾\_______X=========X_______/‾‾‾‾‾‾\_______/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾  (STOP: low -> high under SCL high)
           ^ SDA falls, SCL high       ^ SDA high then falls under SCL high
```

The agent's controller is cycle-based on the interface clock (`clk`, 10 ns
in the TB): SCL low `t_low` clks, high `t_high` clks (default 3 + 3, one bit
= 60 ns, ~16.7 MHz - deliberately scaled for fast simulation, not the
12.5 MHz SDR maximum). SDA is changed one clk after SCL falls and sampled
one clk after SCL rises; a target reacts on the clk after it sees SCL fall.
Bus free time after STOP: `t_buf` clks; a target requests a START only after
`t_aval` clks of idle bus (Bus Available, scaled).

## 4. Frame formats

Notation: `S` START, `Sr` repeated START, `P` STOP, `A`/`N` ACK/NACK
(open-drain), `T` T-bit, `[x]` from the target, `od`/`pp` open-drain/push-pull.

### 4.1 Private write / read

```
S 7E/W(od) [A] Sr DA/W(pp) [A] D0 T D1 T ... Dn T P          write, T = odd parity of the byte
S 7E/W(od) [A] Sr DA/R(pp) [A] [D0 T=1] [D1 T=1] ... [Dn T=0] P   read, the target ends with T=0
S DA/W(od) [A] D0 T ... P                                    without the 7E header (arbitrated, allowed)
```

Write T-bit: odd parity over the byte (T = 1 when the byte has an even
number of ones) *(public implementations)*. Read T-bit: 1 = more data, 0 =
end of data. After a T=1 the target releases SDA on the SCL rising edge; the
controller may pull SDA low while SCL is high - a repeated START - to stop
the read (abort), then send P or another header.

Model of the targets' register file (agent and DUT alike): the first write
byte is the register pointer (mod 16), later bytes are written with
auto-increment; reads start at the pointer and auto-increment; the target
sends T=0 on the byte of the last register (15).

### 4.2 CCCs (Common Command Codes)

```
broadcast:  S 7E/W [A] CCC T [D0 T ...] P
direct:     S 7E/W [A] CCC T Sr DA/RnW [A] D0 T ... (Sr DA2/RnW ...) P
```

CCC bit 7: 0 = broadcast, 1 = direct. Payload length is implied by the CCC.
Modelled set *(codes: public implementations)*:

| CCC | code | dir | payload | effect in the model |
| --- | --- | --- | --- | --- |
| ENEC | 0x00 / 0x80 | W | 1 byte: bit0 ENINT, bit3 ENHJ | enable IBI / Hot-Join |
| DISEC | 0x01 / 0x81 | W | 1 byte (same bits) | disable |
| RSTDAA | 0x06 | bcast | - | every target forgets its dynamic address |
| ENTDAA | 0x07 | bcast | rounds, see 4.3 | dynamic address assignment |
| SETMWL | 0x09 / 0x89 | W | 2 bytes, MSB first | max write length (stored, read back; not enforced) |
| SETDASA | 0x87 | W | 1 byte: DA << 1 | to the target's static address; only a target without DA ACKs |
| GETMWL | 0x8B | R | 2 bytes | |
| GETPID | 0x8D | R | 6 bytes, PID[47:40] first | |
| GETBCR | 0x8E | R | 1 byte | |
| GETDCR | 0x8F | R | 1 byte | |
| GETSTATUS | 0x90 | R | 2 bytes, MSB first: [5] protocol error, [3:0] pending interrupt | reading clears [5] |

A direct CCC stays in force across Sr until P or `Sr 7E/W` (a new CCC); a
broadcast CCC ends at the next Sr.

### 4.3 ENTDAA

```
S 7E/W [A] 0x07 T
  Sr 7E/R(pp) [A by every target without a DA]
     [PID 48 bits][BCR 8][DCR 8]   open-drain, MSB first; a target that sends 1 and sees 0 has lost and drops out of the round
     DA 7 bits + parity (odd) (od, controller)
     [A from the winner]  (NACK if the parity is wrong; the target stays unassigned)
  Sr 7E/R ... next round
  Sr 7E/R  N   (nobody left)
P
```

The lowest {PID, BCR, DCR} wins each round. BCR bits used: [2] IBI with
payload (MDB), [1] IBI capable; [7:6] = 00 (target).

### 4.4 In-Band Interrupt and Hot-Join

```
idle bus (SCL, SDA high >= t_aval):  target pulls SDA low (START request)
S {DA,R}(od, arbitrated against the controller's 7E/W and other targets)  A/N(controller)
   [MDB T=0]  (only if BCR[2] and ACKed)   P  (or Sr + the controller's own transfer after a NACK)
Hot-Join: S {7'h02,W} A/N P   (target without DA, ENHJ set)
```

A target may also arbitrate in the header after any START of the
controller (never after Sr). Lower address wins (0 dominates); 7'h02 beats
every dynamic address and 7E. A NACKed IBI stays pending and is retried;
the controller stops it with DISEC (sent after the Sr that follows its
NACK, since a target cannot arbitrate after Sr). A NACKed Hot-Join is
dropped by the agent's target (model choice).

## 5. Error conditions the model checks

| Condition | Who detects | Effect |
| --- | --- | --- |
| write T-bit parity wrong | target (DUT, agent), monitor | target ignores that byte and the rest of the transfer, GETSTATUS[5] = 1 |
| ENTDAA address parity wrong | target, monitor | winner NACKs, takes part in the next round |
| address nobody owns | - | NACK, controller sends P |
| SDA push-pull high against a low | monitor | UVM_ERROR (contention) |
| push-pull high during an open-drain phase | monitor | UVM_ERROR |
| SCL low/high shorter than 2 clks | monitor | UVM_ERROR |
| transfer ending inside a byte, bits after T=0 | monitor | UVM_ERROR |

## 6. Modelled / not modelled

Modelled: SDR mode; START/Sr/STOP; open-drain and push-pull phases with
explicit per-driver enables; 7'h7E broadcast header; private write/read
with parity and end-of-data T-bits, controller abort; ENTDAA with
multi-target arbitration and address parity; SETDASA; RSTDAA, ENEC/DISEC,
SETMWL/GETMWL, GETPID/GETBCR/GETDCR/GETSTATUS; IBI with START request,
header arbitration, ACK/NACK, MDB; Hot-Join request.

Not modelled:

- **HDR modes** (HDR-DDR, HDR-TSP/TSL, HDR-BT) and ENTHDRx, the HDR exit
  pattern; SDR multi-lane (ML).
- Features of full I3C not in I3C Basic (per the MIPI FAQ, e.g. Timing
  Control async mode 1) and optional I3C Basic features beyond the list above:
  secondary controller / controller-role handoff (GETACCCR, controller role
  request), group addressing, SETAASA, SETNEWDA, GETMRL/SETMRL, GETMXDS,
  GETCAPS, DEFTGTS, RSTACT / target reset pattern, ENDXFER, multi-byte IBI
  payload beyond the MDB, IBI data-length rules.
- Legacy I2C targets on the bus, 50 ns spike filter, FM/FM+ timing of the
  first header, real electrical timing (tSU/tHD, tCAS/tCBP, bus available /
  idle times are clk-scaled stand-ins), the high-keeper handoff details.
- MWL is stored and read back but not enforced; GETSTATUS activity mode is 0.
