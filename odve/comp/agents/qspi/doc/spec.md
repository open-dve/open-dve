# Quad SPI NOR flash - protocol summary for verification

There is no single public standard for the QSPI flash command set. JEDEC
JESD216 standardises only the *discovery* table (SFDP); the instructions
themselves are vendor practice, highly consistent across Winbond, Micron,
Macronix and others. This agent takes the Winbond W25Q32FV as the command
reference.

## References

| Document | Version / date | Access | Used for |
| --- | --- | --- | --- |
| Winbond, *W25Q32FV 3V 32M-bit serial flash memory with dual/quad SPI & QPI*, datasheet | Revision H, 16 Sep 2013 | public PDF (mirror read: <https://mikrocontroller.net/attachment/266991/w25q32fv_revh_091613.pdf>) | 6.1.1-6.1.4 (SPI/dual/quad/QPI operation, modes 0 and 3), 7.1.1 (BUSY), 7.1.2 (WEL), 7.1.10 (QE, title only), 8.1.1 (IDs), 8.1.2-8.1.4 (instruction tables and their notes: lane order, dummy clocks), 8.2.7 (0Bh), 8.2.10 (BBh, continuous read mode), 8.2.11 (EBh), 8.2.15 (02h), 8.2.17 (20h), 8.2.30 (5Ah), 8.2.34 (C0h, QPI dummy clocks), 8.2.36 (38h), 9.6 (tPP, tSE, tSHSL) |
| JEDEC JESD216, *Serial Flash Discoverable Parameters (SFDP)* | 2011 and later revisions | free download after JEDEC registration | **not read**. The SFDP header layout (signature `50444653h` = "SFDP", NPH, parameter header with ID, length and 24-bit table pointer, BFP DWORD2 = density) was taken from public summaries of the Linux `spi-nor/sfdp.c` and Zephyr `jesd216.h` sources found by web search; the header values used here (revision 1.6, 9 DWORDs) are illustrative, not checked against the standard |

## Signals and electrical model

| Signal | Datasheet | Driven by |
| --- | --- | --- |
| `cs_n` | /CS | master |
| `sclk` | CLK | master |
| `io[0]` | DI / IO0 | master (instruction, address, write data); flash in dual/quad output |
| `io[1]` | DO / IO1 | flash (single-line output); master in dual/quad input |
| `io[2]`, `io[3]` | /WP / IO2, /HOLD / IO3 | quad and QPI phases only; otherwise held high (pull-ups) |

The `io` lines are bidirectional. No tristate nets: every driver - master
agent (`m_io`/`m_io_oe`), slave agent (`s_io`/`s_io_oe`), RTL flash
(`d_io`/`d_io_oe`) - has a value and an enable per line, and `odve_qspi_if`
resolves `io[i]` with plain logic (the enabled value, 1 = pull-up when none;
`io_ndrv[i]` counts enables for the contention check).

Data is latched on the rising and shifted out on the falling CLK edge;
modes 0 (CLK idles low) and 3 (idles high) are supported (6.1.1). In mode 0
the first bit is put out with /CS falling.

## Frame formats (8.1.2 - 8.1.4)

A frame is /CS low ... high: instruction (8 bits), optional 24-bit address,
optional mode bits M7-0, dummy clocks, data. Bytes are MSB first; with L
lanes, clock j of a byte carries bits [7-jL -: L] on IO[L-1:0] (notes 6-9
and 14: quad IO3 = D7/A23 first, IO0 = D4/A20; dual IO1 = D7, IO0 = D6).
Single-line input uses IO0, single-line output IO1.

| Opcode | Name | SPI cmd-addr-data | dummy (SPI) | QPI | Needs |
| --- | --- | --- | --- | --- | --- |
| 06h / 04h | write enable / disable | 1-0-0 | - | 4-0-0 | |
| 05h / 35h | read status 1 / 2 | 1-0-1 (repeats) | - | 4-0-4 | |
| 31h | write status 2 (QE = bit 1) | 1-0-1 in | - | 4-0-4 in | WEL |
| 9Fh | JEDEC ID | 1-0-1 | - | 4-0-4 | |
| 03h | read | 1-1-1 | 0 | - | |
| 0Bh | fast read | 1-1-1 | 8 | 4-4-4, 2 dummy | |
| 3Bh | dual output read | 1-1-2 | 8 | - | |
| BBh | dual I/O read | 1-2-2 | M7-0 = 4 clocks | - | |
| 6Bh | quad output read | 1-1-4 | 8 | - | QE |
| EBh | quad I/O read | 1-4-4 | M7-0 = 2 + 4 dummy | 4-4-4, M7-0 = the 2 dummy clocks | QE |
| 02h | page program | 1-1-1 | - | 4-4-4 | WEL |
| 32h | quad page program | 1-1-4 | - | - | WEL, QE |
| 20h | sector erase (4 KiB) | 1-1-0 | - | 4-4-0 | WEL |
| 5Ah | read SFDP | 1-1-1 | 8 | - | |
| 38h | enter QPI | 1-0-0 | - | - | QE |
| FFh | exit QPI | - | - | 4-0-0 | |

```
Fast Read Quad I/O (EBh), SPI mode 0 (figure 24a)
cs_n ‾\_______________________________________________________________ ...
sclk __/‾\_/‾\ ... /‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_ ...
io0  =< EBh, 8 clocks on IO0 >=<A20 A16 .. A0 >=<M4 M0>-- -- -- --<D4 D0 D4 ...
io1  ----------------------------<A21 ..    A1 >=<M5 M1>-- -- -- --<D5 D1 ...
io3  ----------------------------<A23 ..    A3 >=<M7 M3>-- -- -- --<D7 D3 ...
          instruction (master)     address (master)  mode  4 dummy  data (flash)
                                                           (released)
```

## Flash behaviour modelled (RTL DUT and slave agent)

- Array of 8 KiB (two 4 KiB sectors, 32 pages); address bits above it are
  ignored; erased = FFh. Reads stream on through the array and wrap at its
  end.
- Status 1 = {6'b0, WEL, BUSY} (7.1.1, 7.1.2); status 2 = {6'b0, QE, 0}.
  Status and ID output repeat until /CS rises (8.1.4 note 2; the JEDEC ID's
  3 bytes repeat too - a model choice, the note names status and device ID).
- WREN sets WEL, WRDI clears it. PP/QPP/SE/WRSR2 need WEL (8.2.15, 8.2.17),
  start a self-timed operation (BUSY = 1) and clear WEL when it ends.
- While BUSY only 05h/35h are accepted (7.1.1); anything else is ignored -
  the flash does not drive the lines.
- Quad instructions (6Bh, EBh, 32h) and 38h are ignored without QE (6.1.3,
  6.1.4, 8.2.36).
- Page program only clears bits (new = old AND data; a program "allows ...
  previously erased (FFh) memory locations" to be programmed, 8.2.15); bytes
  past the end of the page wrap to its start and overwrite (note 3).
  It executes only when /CS rises right after a complete byte, sector
  erase only right after the last address bit (8.2.15, 8.2.17).
- Busy times scaled down: tPP 1500, tSE 5000, tW 200 system clock cycles
  (datasheet 9.6: tPP 0.7-3 ms, tSE up to 400 ms).
- JEDEC ID EFh 40h 0Dh (SPI) / EFh 60h 0Dh (QPI) - Winbond's manufacturer
  code and type bytes (8.1.1) with capacity code 0Dh = 2^13 bytes for this
  8 KiB model. SFDP: header + one parameter header (BFP at 80h, 9 DWORDs),
  BFP DWORD2 = density in bits - 1, everything else FFh.

## Error / abort conditions

| Condition | Detected by |
| --- | --- |
| sclk not at its idle level at /CS edges | monitor `QSPI_CPOL` |
| tSLCH / tCHSH / tSHSL below the minimum (default: half an sclk period) | `QSPI_LEAD` / `QSPI_TRAIL` / `QSPI_IDLE` |
| two drivers on an io line | `QSPI_IO_CONT` |
| a lane the phase needs is undriven (e.g. the flash ignored a read) | `QSPI_IO_Z` (`cfg.chk_undriven`) |
| /CS rises inside instruction/address/dummy or mid data byte | `QSPI_TRUNC`; program not executed |
| clocks after a command without data (e.g. SE + extra clocks) | `QSPI_EXTRA`; erase not executed |
| opcode unknown in the current mode | `QSPI_UNK` (warning) |

## Modelled / not modelled

Modelled: master and slave (behavioural flash) roles; modes 0 and 3;
SPI and QPI; formats 1-1-1, 1-1-2, 1-2-2, 1-1-4, 1-4-4, 4-4-4 for read and
1-1-1, 1-1-4, 4-4-4 for program; the instructions in the table above; WEL,
BUSY, QE semantics; program/erase semantics and timing (scaled); SFDP read;
all checks above.

Not modelled: continuous read mode (M5-4 = 10, the master always sends
M7-0 = 00h), Set Read Parameters C0h (QPI dummy clocks fixed at the power-up
default 2), wrap/burst modes (77h, 0Ch), Word/Octal Word Read (E7h, E3h),
Mftr/Device ID (90h/92h/94h/ABh), unique ID, block and chip erase (52h, D8h,
C7h/60h), suspend/resume, power-down, software reset (66h/99h), status
register 1/3 writes, block protection, security registers, /WP and /HOLD
pin functions, DTR, 4-byte addressing.
