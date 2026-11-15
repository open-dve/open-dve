# SPI - protocol summary for verification

SPI has no single standards-body specification. The de-facto reference is
Motorola's (now NXP's) SPI block guide for the HC12/S12 family, which named
the CPOL/CPHA/LSBFE controls that every vendor has adopted since. This agent
follows it for the bus, and adds what the block guide leaves to the
application (multi-word frames, several chip selects).

## References

| Document | Version / date | Access | Used for |
| --- | --- | --- | --- |
| Motorola, *SPI Block User Guide*, document S12SPIV2/D | V02.07, original release 21 Jan 2000, revised 11 Dec 2002 | public PDF, e.g. <https://www.eecs.yorku.ca/course_archive/2011-12/W/3215/labs%20documentation/S12SPIV2.pdf> | sections 2.2 (signals), 3.3.1 (CPOL, CPHA, LSBFE), 4.2/4.3 (master/slave mode), 4.4 (transmission formats, figures 4-2 and 4-3 with tL/tT/tI), 4.5 (baud rate), 4.6.1 (SS output), 4.7.1 (mode fault) |
| Motorola SPI Block Guide V03.06 (S12SPIV3/D) and V04.01 | - | public copies exist (Scribd, MSU) but could not be downloaded here (bot protection) | not read; V02.07 above is what the text below cites |

Only V02.07 was read. Section numbers below refer to it.

## Signals and electrical model

| Signal | Block guide | Driven by | Here |
| --- | --- | --- | --- |
| `sclk` | SCK (2.2.4) | master | push-pull, idles at CPOL |
| `mosi` | MOSI (2.2.1) | master | push-pull |
| `miso` | MISO (2.2.2) | the selected slave | high impedance when deselected (4.3) - modelled as one value/enable pair per driver (`s_miso/s_miso_oe` for slave agents, `d_miso/d_miso_oe` for RTL slaves) resolved in `odve_spi_if`: the enabled driver's value, `1` (pull-up) when none |
| `cs_n[i]` | SS (2.2.3), active low | master, one line per slave | push-pull |

No tristate nets are used (Verilator); a second enabled MISO driver is a
contention error, no enabled driver at a sampling edge an undriven-line
error (block guide 4.3 note: never two slave outputs on the same line).

The agent and the RTL slave run on a TB system clock `clk`; the master
generates `sclk` from it (`cfg.half_period` clock cycles per half period,
4.5 describes the same idea as a divider of the module clock).

## Clock modes (3.3.1, 4.4.1)

`CPOL` = idle level of SCK (0: idles low, 1: idles high). `CPHA` selects
one of two transfer formats:

- `CPHA = 0` (4.4.2): the first data bit is on the line as soon as SS is
  low; data is latched on odd-numbered edges (the leading edge of each bit)
  and shifted on even-numbered edges (trailing).
- `CPHA = 1` (4.4.3): the first edge shifts the first bit out; data is
  latched on even-numbered edges (trailing) and shifted on odd ones.

| mode | CPOL | CPHA | sample edge | shift edge |
| --- | --- | --- | --- | --- |
| 0 | 0 | 0 | rising | falling |
| 1 | 0 | 1 | falling | rising |
| 2 | 1 | 0 | falling | rising |
| 3 | 1 | 1 | rising | falling |

`LSBFE` (3.3.1): 0 = MSB first, 1 = LSB first.

```
CPHA=0, CPOL=0, 8-bit, MSB first (figure 4-2)
cs_n  ‾‾\_____________________________________________________/‾‾‾‾‾
sclk  ______/‾‾\__/‾‾\__/‾‾\__/‾‾\__/‾‾\__/‾‾\__/‾‾\__/‾‾\__________
mosi  ====X b7  X b6  X b5  X b4  X b3  X b2  X b1  X b0  X=========
          |<tL>|  ^ sample (leading)  v shift (trailing)    |<tT>|
                                                               |<tI ...

CPHA=1, CPOL=1, 8-bit, MSB first (figure 4-3)
cs_n  ‾‾\_____________________________________________________/‾‾‾‾‾
sclk  ‾‾‾‾‾‾\__/‾‾\__/‾‾\__/‾‾\__/‾‾\__/‾‾\__/‾‾\__/‾‾\__/‾‾‾‾‾‾‾‾‾
mosi  =======X b7  X b6  X b5  X b4  X b3  X b2  X b1  X b0  X======
              v shift (leading)  ^ sample (trailing)
```

Timing parameters of figures 4-2/4-3, each "minimum 1/2 SCK":
`tL` (SS low to first SCK edge), `tT` (last edge to SS high), `tI` (SS
high time between transfers).

## Frames

The block guide's module moves 8 bits per transfer. Real slaves (sensors,
flash, converters) move several words while SS stays low; the agent models
a **frame** = everything between `cs_n` falling and rising, as a sequence of
`word_bits`-wide words (any width 1..32; 8, 16 and 32 tested), optionally
with idle SCK between words (`word_gap`).

Note: for `CPHA = 0` the block guide requires SS to go high between
successive bytes (4.4.2: "SS should not be tied low all the times in this
mode"), because its slave reloads the shifter on SS. Multi-word frames under
one SS in mode 0/2 are the de-facto practice of devices that frame
commands by SS (the RTL slave here does that); this is a deliberate
extension, not block-guide behaviour.

## Slave command protocol (RTL slave and slave-agent model)

SPI itself has no addressing beyond chip selects. The RTL slave
(`vrf/dut/dut.sv`) and the slave agent's model (`odve_spi_slv_model`) speak
one register-file protocol so that each can stand in for the other:

```
word 0   mosi: [W-1] = 1 read / 0 write, [5:0] = byte address (64 bytes)
         miso: the slave's ID byte, replicated over the word (cs0 0xA5, cs1 0x3C)
word n>0 write: byte k of the word ([8k+7:8k]) -> reg[ptr+k]
         read:  reg[ptr+k] as byte k
         ptr = address, + W/8 per word, wraps 63 -> 0
```

A word cut short by `cs_n` rising is discarded (the block guide transfers
data to the receive register only after the last bit, 4.4.2/4.4.3).

## Error / abort conditions

| Condition | Who detects | How |
| --- | --- | --- |
| more than one `cs_n` low | monitor | `SPI_MULTI_CS` |
| SCK not at CPOL when `cs_n` falls or rises | monitor | `SPI_CPOL` |
| `tL`, `tT`, `tI` shorter than the minimum | monitor | `SPI_LEAD`, `SPI_TRAIL`, `SPI_IDLE` |
| two MISO drivers enabled | monitor | `SPI_MISO_CONT` |
| no MISO driver at a sampling edge | monitor | `SPI_MISO_Z` |
| `cs_n` rises mid-word (abort) | monitor reports `partial_bits`; slaves drop the word | scoreboard |

## Timing parameters the agent models

| Parameter | cfg field | Default | Monitor limit |
| --- | --- | --- | --- |
| SCK half period | `half_period` | 4 clk | - |
| tL | `lead` | 4 clk | `min_lead` (0 = half_period) |
| tT | `trail` | 4 clk | `min_trail` |
| tI | `idle` | 4 clk | `min_idle` |
| inter-word gap | item `word_gap` | 0 | - |

The RTL slave synchronises SCK/MOSI/SS with two flops, so it needs
`half_period >= 4` and `lead >= 4` for CPHA=0 (its first bit appears 3
cycles after SS falls).

## Modelled / not modelled

Modelled: master and slave roles, the four CPOL/CPHA modes, MSB/LSB first,
word widths 1..32, multi-word frames with optional inter-word gaps, several
chip selects with a format each, tL/tT/tI generation and checking, MISO
ownership (contention, undriven), abort mid-word, configurable SCK rate.

Not modelled: mode fault (MODF, 4.7.1) and multi-master operation; the
bidirectional single-wire mode (SPC0/BIDIROE, MOMI/SISO, 4.6.2); the SS
output auto-control (SSOE/MODFEN, 4.6.1) as a register feature (the master
simply drives `cs_n`); the baud-rate register encoding (4.5) - a cycle count
instead; status flags, interrupts, double-buffered data register, low-power
modes (sections 3, 4.8, 6); SS high between bytes in CPHA=0 (see Frames);
dual/quad SPI (see the `qspi` agent).
