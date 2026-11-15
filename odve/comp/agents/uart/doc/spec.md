# UART - protocol summary for verification

There is no single UART standard. The agent follows the de-facto reference
for the asynchronous serial character format, the National/TI 16550
UART, and the RS-232 (TIA-232) conventions for the line idle state and the
RTS/CTS handshake. This page states what the agent and the RTL model, with
the source of each rule.

## 1. References

| # | Document | Version / date | Access | Used for |
|---|---|---|---|---|
| R1 | Texas Instruments, *PC16550D Universal Asynchronous Receiver/Transmitter With FIFOs*, SNLS378C | June 1995, revised May 2015 | public, <https://www.ti.com/product/PC16550D> (copy read: <https://www.cs.unc.edu/~porter/courses/comp630/ref/PC16550D.pdf>) | frame format (§8.6.2 Line Control Register), error definitions (§8.6.3 Line Status Register), 16x baud clock (§8.5.1 Programmable Baud Generator, pin descriptions of BAUDOUT/RCLK), FIFO depth and overrun in FIFO mode (§1 Features, §8.6.3 bit 1), RTS/CTS pins (§8.6.7 Modem Control Register, pin table), "False Start Bit Detection" (§1 Features) |
| R2 | Texas Instruments, *TL16C550C Asynchronous Communications Element With Autoflow Control*, SLLS177I | March 1994, revised March 2021 | public, <https://www.ti.com/product/TL16C550C> | auto-RTS / auto-CTS hardware flow control (§7.1 Autoflow Control, §7.2 Auto-RTS, §7.3 Auto-CTS). Only the section headings and the feature list were read directly; the behaviour (RTS deasserted when the RX FIFO reaches its threshold, CTS checked before each character is started, a character in progress is completed) is taken from TI's document viewer summaries of those sections. |
| R3 | TIA-232-F, *Interface Between Data Terminal Equipment and Data Circuit-Terminating Equipment Employing Serial Binary Data Interchange* | 1997 | paid standard, **not read** | only the generally known conventions are used: idle line = mark (logical 1), start bit = space, RTS/CTS as a request/permission pair. Electrical levels (±3..15 V, inversion by the line driver) are out of scope - the agent works at TTL logic level like the 16550's SIN/SOUT pins. |

Everything not covered by R1/R2 (e.g. the exact receiver resynchronisation
after a framing error, the device's echo behaviour) is a design decision of
this agent / DUT and is labelled so below.

## 2. Signals and electrical model

All lines are push-pull, one driver each, logic level (no RS-232 inversion).
Names are from the master agent's (DTE's) point of view.

| Signal | Driver | Receiver | Meaning |
|---|---|---|---|
| `txd` | master agent | peer (DUT `rxd` / slave agent) | serial data master -> peer; idle = 1 (mark) |
| `rxd` | peer (DUT `txd` / slave `s_rxd`) | master monitor | serial data peer -> master |
| `rts_n` | master agent | peer's CTS input | active low: the master can receive |
| `cts_n` | peer (DUT `rts_n` / slave `s_cts_n`) | master | active low: the master may send |

In `vrf/tb/top.sv` `+uart_slave=dut|mem|seq` selects which source drives
`rxd` and `cts_n` (a plain `assign` mux, no tristates).

## 3. Character frame (R1 §8.6.2)

```
 idle  start  D0  D1  D2  D3  D4 [D5][D6][D7] [P]  stop [stop2]  idle
 ----+      +---+   +---+   +---+   +---+   +---+------------------
     |      |   |   |   |   |   |   |   |   |   |
     +------+   +---+   +---+   +---+   +---+   +
      1 bit   LSB first, 5..8 data bits   parity  1 / 1.5 / 2 stop bits (mark)
```

- Data: 5, 6, 7 or 8 bits, least significant bit first (LCR bits 0-1).
- Parity (LCR bits 3-5): none; even (data + parity have an even number of 1s);
  odd; stick parity = mark (always 1) or space (always 0).
- Stop bits (LCR bit 2): 1; or 1.5 when the word length is 5 bits, 2 when it is
  6, 7 or 8 bits. "The Receiver checks the first Stop-bit only, regardless of
  the number of Stop bits selected" (R1 §8.6.2).
- Back to back: the next start bit may follow the last stop bit immediately.

## 4. Timing

- Bit time = 16 periods of the 16x baud clock (R1 §8.5.1: the baud generator
  "generates the 16 x clock"). In simulation the baud rate is scaled: the DUT
  has a `div` input (clocks per 16x tick) and the agent a bit period in clock
  cycles, `cfg.bit_clks` (default 64 = 16 x 4 at a 100 MHz `clk`, i.e. one bit
  per 640 ns).
- Receiver sampling (16550 practice, R1 "False Start Bit Detection"): a falling
  edge in idle starts a character; the line is checked again at the middle of
  the start bit and if it is back at mark the edge was a glitch and is ignored;
  every following bit is sampled once at its middle (every 16 ticks).
- Baud mismatch: a receiver that samples at the bit middles tolerates a
  transmitter whose rate differs as long as the accumulated error at the
  (first) stop bit stays under half a bit minus the sampling uncertainty (1/16
  bit). For the longest frame (12 bits: start, 8 data, parity, 2 stop; first
  stop sampled 10.5 bit times after the edge) this is about ±4 %; the agent
  is tested at ±3.1 % (62 and 66 clocks per bit against 64).
  (Derived figure, not a number from R1.)

## 5. Error and line conditions (R1 §8.6.3)

| Condition | Definition (R1 LSR) | Modelled |
|---|---|---|
| Parity error (PE, LSR bit 2) | received parity bit does not match the selected parity | monitor flag `pe`, DUT `st_pe`; injected by `item.bad_parity` |
| Framing error (FE, LSR bit 3) | the first stop bit is sampled as space | monitor `fe`, DUT `st_fe`; injected by `item.bad_stop` |
| Break (BI, LSR bit 4) | input held at space "for longer than a full word transmission time (start + data + parity + stop)"; only one zero character is loaded; the next character is accepted after the line returns to mark and a valid start bit follows | detected when start, data, parity and stop bit are all space (`brk`, `st_bi`; `pe`/`fe` not reported with it); the receiver then waits for mark. Injected by `kind = BREAK` (14..24 bit times) |
| Overrun (OE, LSR bit 1) | FIFO mode: the FIFO is full and the next character has been completely received; "the character in the shift register is overwritten, but it is not transferred to the FIFO" | DUT (8-entry FIFO): `st_oe`, character lost. Slave agent: counted (`n_oe`), character lost |
| False start bit | a space shorter than half a bit (R1 feature list) | ignored by DUT, slave and monitor (monitor counts `n_glitch`); injected by `kind = GLITCH` (1..bit_clks/4 clocks) |

Resynchronisation after a framing error: R1 says the 16550 "assumes that the
framing error was due to the next start bit, so it samples this start bit
twice". **Not modelled**: the DUT, the slave agent and the monitor all wait
for the line to return to mark before looking for the next start bit. The
error-injection items therefore always leave at least one bit of mark after a
bad stop bit (`idle_bits >= 1`).

## 6. Hardware flow control (R2 §7; RS-232 RTS/CTS)

```
 master                         peer (DUT / slave agent)
 rts_n  ----------------------> cts_n   peer starts a character only while low (auto-CTS)
 cts_n  <---------------------- rts_n   high while the peer's RX FIFO holds >= DEPTH-1 (auto-RTS)
```

- Auto-CTS: the transmitter checks CTS before each start bit; a character
  already started is sent completely (agent: `cfg.flow_ctrl`, DUT: `afe`).
- Auto-RTS: the receiver deasserts RTS when its FIFO reaches a threshold
  (here DEPTH-1 = 7 of 8, chosen so the one character that may already be in
  flight still fits) and asserts it again when the FIFO drains below it.
- The master's own RTS (`rts_n`) is set by the test (`drv.set_rx_ready()`),
  since the master's receiver is only a monitor.

## 7. The verification DUT (vrf/dut/dut.sv) - a design of this agent, not a standard

A UART echo device: 16550-style receiver and transmitter, configured by
pins `lcr[5:0]` (the 16550 LCR bit layout), `div` (16x tick divisor) and
`afe`; an 8-entry RX FIFO; every good character is sent back complemented
(`~data` within the data bits) in the same format. Errored characters are
not stored and are reported as a one-clock pulse on `st_valid` with
`st_pe/st_fe/st_bi/st_oe`.

## 8. Modelled / not modelled

Modelled: 5-8 data bits, all five parity modes, 1/1.5/2 stop bits, LSB-first
serialisation, mark idle, 16x mid-bit sampling with false-start rejection,
transmitter baud offset, back-to-back characters, parity/framing error,
break, overrun (DUT), RTS/CTS auto flow control on both sides, full duplex.

Not modelled: RS-232 electrical levels and inversion; the 16550 register
interface (CPU bus, divisor latch, interrupts, IIR/IER, FIFO trigger levels,
character timeout, DMA modes TXRDY/RXRDY); DTR/DSR/DCD/RI modem lines;
loopback mode (MCR bit 4); 16550's resync-on-framing-error behaviour (see §5);
software flow control (XON/XOFF); 9-bit/multidrop modes; fractional baud
divisors in the agent (bit period is a whole number of clocks); jitter or
noise beyond the explicit glitch item; the break transmit control
sequence (LCR bit 6) as a register operation (the agent sends a break as a
line event instead).
