# JTAG (IEEE 1149.1 TAP) - protocol summary for verification

This is a working summary for the odve `jtag` agent, written from public
material. The standard itself (IEEE Std 1149.1, "Standard for Test Access
Port and Boundary-Scan Architecture") is sold by IEEE and was **not**
available; nothing below quotes it, and no clause numbers are given.
Everything here is either stated in the public sources listed or is a
well-known, widely documented property of the TAP (marked *common
knowledge* where no source above states it in so many words).

## References

| # | Title | Version / date | URL | Access | Used for |
|---|-------|----------------|-----|--------|----------|
| R1 | IEEE Std 1149.1, Test Access Port and Boundary-Scan Architecture | 1149.1-2013 (current revision as far as known) | https://standards.ieee.org/ieee/1149.1/4484/ | paid, **not read** | named only as the governing standard |
| R2 | Embecosm EAN5 "Howto: Porting the GNU Debugger", section on IEEE 1149.1 JTAG (TAP states, IR, BYPASS, TRST) | app note, n.d. | https://www.embecosm.com/appnotes/ean5/html/ch02s01s02.html | public | TAP states, TMS sampled at rising TCK, TDI in at rising / TDO out at falling edge, IR >= 2 bits, BYPASS = all ones, mandatory BYPASS/SAMPLE/PRELOAD/EXTEST, TRST optional asynchronous, reset by TMS=1 for 5 TCKs |
| R3 | Memfault Interrupt blog, "Diving into JTAG - Overview (Part 1)" | 2024 | https://interrupt.memfault.com/blog/diving-into-jtag-part1 | public | 4 mandatory + 1 optional (TRST) signals, transitions on TMS at rising TCK, TLR reachable by 5 TCKs with TMS=1, Capture-IR pattern "usually 0x01", TDO output on falling TCK, BYPASS for chained devices |
| R4 | XJTAG "Technical Guide to JTAG" | web page, n.d. | https://www.xjtag.com/about-jtag/jtag-a-technical-overview/ | public | mandatory BYPASS, EXTEST, SAMPLE/PRELOAD; TRST optional; TDO valid on falling TCK; every state has two exits chosen by TMS |
| R5 | Intel386 EX Embedded Microprocessor User's Manual, JTAG chapter (IDCODE register figure) | Intel manual | https://www.manualsdir.com/manuals/127325/intel-386.html?page=521 | public | IDCODE layout: version [31:28], part [27:12], manufacturer [11:1], bit 0 = 1; a 0 as first bit after reset means BYPASS (no IDCODE) |
| R6 | RISC-V External Debug Support v0.13, JTAG DTM registers | 0.13 release | https://five-embeddev.com/riscv-debug-spec/v0.13-release/jtag_registers.html | public | IDCODE is the instruction selected when the TAP is reset |

Search snippets from TU Delft OCW "Module 13 Boundary Scan Standard" and KIT
"tds2 lecture 4" were seen but their PDFs could not be read as text; they
are not relied on.

## Signals and electrical model

| Signal | Direction | Driven by | Notes |
|--------|-----------|-----------|-------|
| TCK | host -> TAPs | host (master agent) | test clock; in the agent derived from the TB clock: TCK = clk / (2 * `tck_half`) |
| TMS | host -> TAPs | host | sampled by every TAP at rising TCK; selects the next state |
| TDI | host -> first TAP | host | serial data in, sampled at rising TCK in Shift-IR/Shift-DR |
| TDO | last TAP -> host | target | changes at falling TCK, active only in Shift-IR/Shift-DR, 3-state otherwise |
| TRST_n | host -> TAPs | host | optional, active low, asynchronous reset of the TAP controller to Test-Logic-Reset |

All lines are push-pull. TDO is a 3-state output: in this testbench every
driver has an explicit enable (`tdo_oe` from the DUT, `s_tdo_oe` from the
slave agent), `top.sv` muxes the selected target onto the bus and reads 1
when no enable is active (pull-up). No `inout`/`tri` is used. In a daisy
chain TDI of TAP k+1 is TDO of TAP k; the host sees TDI of the first and TDO
of the last TAP.

## TAP controller

16 states, every state has exactly two successors, chosen by TMS at the
rising edge of TCK (R2, R3, R4). The sketch is approximate; the table below
is authoritative.

```
 (n) = state loops on TMS=n          arrows labelled with the TMS value

   Test-Logic-Reset (1) <-------------------------------------+
        | 0                                                   | 1
        v                                                     |
   Run-Test/Idle (0) --1--> Select-DR-Scan --1--> Select-IR-Scan
                                 | 0                   | 0
                             Capture-DR            Capture-IR
                             0 |     \ 1           0 |     \ 1
                             Shift-DR (0)  |       Shift-IR (0)  |
                             1 |           |       1 |           |
                             Exit1-DR <----+       Exit1-IR <----+
                             0 |     \ 1           0 |     \ 1
                             Pause-DR (0)  |       Pause-IR (0)  |
                             1 |           |       1 |           |
                             Exit2-DR      |       Exit2-IR      |
                  0: -> Shift-DR | 1       |  0: -> Shift-IR | 1  |
                             Update-DR <---+       Update-IR <---+
              Update-DR / Update-IR:  0 -> Run-Test/Idle,  1 -> Select-DR-Scan
```

Transition table (current state: next with TMS=0 / TMS=1) - this is exactly
`odve_jtag_next()` in `src/item/odve_jtag_item_pkg.sv` and the DUT's
`always_comb`:

| state | TMS=0 | TMS=1 |
|-------|-------|-------|
| Test-Logic-Reset | Run-Test/Idle | Test-Logic-Reset |
| Run-Test/Idle | Run-Test/Idle | Select-DR-Scan |
| Select-DR-Scan | Capture-DR | Select-IR-Scan |
| Capture-xR | Shift-xR | Exit1-xR |
| Shift-xR | Shift-xR | Exit1-xR |
| Exit1-xR | Pause-xR | Update-xR |
| Pause-xR | Pause-xR | Exit2-xR |
| Exit2-xR | Shift-xR | Update-xR |
| Update-xR | Run-Test/Idle | Select-DR-Scan |
| Select-IR-Scan | Capture-IR | Test-Logic-Reset |

Consequence (R2, R3): from any state, five TCKs with TMS=1 reach
Test-Logic-Reset. TRST_n low does it immediately and asynchronously (R2).

## Scans and timing

```
 TCK    __    __    __    __    __    __    __    __
     __|  |__|  |__|  |__|  |__|  |__|  |__|  |__|  |__
 TMS  X  0  X  0  X  0  X  1  X  1  X  0  X
 state  Capture | Shift | Shift | Shift | Exit1 | Update | RTI
 TDI          b0      b1      b2   (sampled at rising TCK while in Shift)
 TDO          c0      c1      c2   (changes at falling TCK, valid at the next rising edge)
 tdo_oe ______/~~~~~~~~~~~~~~~~~~~~~~~\_______
```

- Capture-xR (rising edge leaving it): the selected register loads its
  capture value. Capture-IR loads a pattern whose two LSBs are `01` (R3:
  "0x01 is usually selected"; the `01` LSBs as a requirement are *common
  knowledge* and are what host tools use to measure chain length).
- Shift-xR: each rising TCK shifts TDI into the MSB and the LSB towards TDO;
  data is LSB first. TDO presents the LSB from the falling edge (R2, R3, R4).
- Exit1/Pause/Exit2: shifting stops in Pause-xR as long as TMS=0 and resumes
  through Exit2-xR -> Shift-xR, or ends through Exit2-xR -> Update-xR.
- Update-xR: the shifted value is latched into the register's parallel
  output (instruction or data); the agent and DUT latch at the falling TCK
  in Update-xR (*common knowledge*; only the ordering relative to the next
  capture is observable).
- A scan has any length: shorter than the register leaves part of the
  captured value in it, longer passes TDI through to TDO once the register's
  own bits are out.

## Instructions and data registers (as modelled)

The IR must be at least 2 bits (R2); this agent's TAP uses 4.

| Instruction | Opcode | Data register | Capture | Update |
|-------------|--------|---------------|---------|--------|
| EXTEST | 0000 | boundary, 8 bits | pins | latch, driven on `pins_o` |
| SAMPLE/PRELOAD | 0001 | boundary, 8 bits | pins | latch (PRELOAD) |
| IDCODE | 0010 | identification, 32 bits | IDCODE value | none |
| USERDATA | 1000 | user, 32 bits | current value | new value |
| BYPASS | 1111 (all ones, R2) | bypass, 1 bit | 0 (R5) | none |
| any other | - | bypass | 0 | none |

The opcodes other than BYPASS are this design's choice (the standard leaves
them to the implementer apart from BYPASS; *common knowledge*). Unassigned
opcodes selecting BYPASS is *common knowledge*.

IDCODE layout (R5): `[31:28]` version, `[27:12]` part number, `[11:1]`
manufacturer identity, `[0]` = 1. The DUT's TAP k has
`32'h1234_5679 + k * 32'h1000_0000` (TAP 0: version 1, part 0x2345,
manufacturer 0x33C, bit 0 = 1) - invented values, not a registered
manufacturer code.

Test-Logic-Reset selects IDCODE (R5, R6; a TAP without IDCODE selects BYPASS,
which is why its first bit out is 0). In this model TRST_n (and power-on
reset) also clear USERDATA and the boundary update latch; a reset through
TMS does not.

## Daisy chain

TDI -> TAP0 -> TAP1 -> TDO. An IR scan is the concatenation of every TAP's
IR (8 bits for two 4-bit TAPs); bits shifted first end up in the TAP nearest
TDO. A DR scan is the concatenation of the registers each TAP's instruction
selects (two IDCODEs = 64 bits, two BYPASS = 2 bits). Captured IR of the
chain shifted out = `0001` of the last TAP followed by `0001` of the first.

## Error / abnormal conditions

JTAG has no acknowledge or error response. What a verification environment
can observe:

- TDO enabled outside Shift-IR/Shift-DR, or disabled inside them;
- a Capture-IR pattern whose first two bits out are not 1, 0;
- unknown (X/Z) TMS/TDI at a rising TCK, unknown TDO while shifting;
- TRST_n in the middle of a scan: the scan is abandoned, nothing is updated.

## Timing parameters the agent models

- TCK period: `2 * cfg.tck_half` TB clock periods (default 1 -> 20 ns with
  the 10 ns TB clock); TMS/TDI change at the falling edge, half a TCK before
  they are sampled.
- TRST_n: asserted between edges, held two TCK periods with TMS=1.
- No setup/hold or propagation delays (zero-delay RTL and TB).

## Modelled / not modelled

Modelled: TCK/TMS/TDI/TDO/TRST_n; all 16 states and 32 arcs; reset by 5x
TMS=1 and by TRST_n; IR and DR scans of 0..256 bits; Pause with Exit2
resume and Exit2 -> Update; Run-Test/Idle cycles; BYPASS, IDCODE,
SAMPLE/PRELOAD, EXTEST (8-bit boundary register), USERDATA (32-bit R/W);
unassigned opcodes as BYPASS; two-TAP daisy chain; TDO 3-state as an
explicit enable.

Not modelled: the real boundary-scan cell structure, BSDL, INTEST, CLAMP,
HIGHZ, USERCODE, RUNBIST and other optional instructions; IEEE 1149.1-2013
additions (init data/status, ECIDCODE, TMP controller); 1149.7 (cJTAG) and
1149.6 (AC-coupled); electrical levels, pull-ups on TMS/TDI, setup/hold and
clock-to-out times; TCK stopped in other than stable states; run-time
self-test in Run-Test/Idle.
