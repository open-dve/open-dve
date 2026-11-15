# SPI agent - requirements

Spec references are to the Motorola *SPI Block User Guide* S12SPIV2/D V02.07
(see `spec.md`); "odve" marks requirements of this framework or of the
TB's slave protocol, which the block guide does not define. Every test named
here runs in `vrf/work/rlist/submit.list` (entries `spi_*`); coverpoints are
`odve_spi_cg` (agent package, sampled by the monitor) and `spi_reg_cg`
(`vrf/tb/env/env_pkg.sv`, sampled by the scoreboard).

| ID | Requirement | Spec | Verified by |
| --- | --- | --- | --- |
| REQ-SPI-001 | The master idles SCK at CPOL and keeps it there while any `cs_n` falls or rises; the monitor reports any other level (`SPI_CPOL`). | 3.3.1, 4.4.1 | every test (no `SPI_CPOL`); `err_test` injects `cpol_err` and requires `SPI_CPOL`; `cp_mode` |
| REQ-SPI-002 | CPHA=0: the first bit is valid from `cs_n` low, bits are sampled on the leading and shifted on the trailing edge, by master, slave agent, RTL slave and monitor. | 4.4.2 | `mode_test` (modes 0, 2 on both slaves, `spi_mode`/`_mem`/`_seq`), scoreboard + in-test read-back compare; `cp_mode` bins 0, 2 |
| REQ-SPI-003 | CPHA=1: bits are shifted on the leading and sampled on the trailing edge. | 4.4.3 | `mode_test` (modes 1, 3), scoreboard; `cp_mode` bins 1, 3 |
| REQ-SPI-004 | MSB-first and LSB-first word order. | 3.3.1 (LSBFE) | `mode_test` (both orders in every mode), scoreboard; `cp_order`, `x_mode_order` |
| REQ-SPI-005 | Word widths of 8, 16 and 32 bits. | odve (block guide: 8 only) | `mode_test`, `burst_test` (all three widths); `cp_bits`, `x_mode_bits` |
| REQ-SPI-006 | Several words in one frame, `cs_n` held low throughout. | odve (de-facto; see spec.md "Frames") | `rw_test`, `burst_test` (64-byte frames); `cp_len` |
| REQ-SPI-007 | Idle SCK between the words of a frame (inter-word gap) is accepted by every slave and recognised by the monitor. | odve | `burst_test` (gaps in `wr_rd` and 50 % random gaps); `cp_gap` |
| REQ-SPI-008 | Several chip selects, each slave with its own format, only one selected at a time. | 4.4 (SS per slave) | `rw_test` (cs0 mode 0/MSB/8, cs1 mode 3/LSB/16), `b2b_test` (alternating); `cp_cs` |
| REQ-SPI-009 | Two chip selects low at once is reported (`SPI_MULTI_CS`). | 4.4, 4.3 note | `err_test` (second select forced low) |
| REQ-SPI-010 | tL (cs_n low to first edge) >= the minimum, default half an SCK period; violations reported (`SPI_LEAD`). | fig. 4-2/4-3 | `b2b_test` runs at exactly the minimum; `err_test` injects tL = 1 and requires `SPI_LEAD` |
| REQ-SPI-011 | tT (last edge to cs_n high) >= the minimum; violations reported (`SPI_TRAIL`). | fig. 4-2/4-3 | `b2b_test`; `err_test` injects tT = 1 |
| REQ-SPI-012 | tI (cs_n high between frames) >= the minimum; violations reported (`SPI_IDLE`). | fig. 4-2/4-3 | `b2b_test`; `err_test` injects tI = 1 |
| REQ-SPI-013 | Only the selected slave drives MISO; two enabled drivers are reported (`SPI_MISO_CONT`). | 4.3 | slave drivers / RTL drive `*_oe` only while selected (every test, no error); `err_test` forces a second slave on |
| REQ-SPI-014 | A sampling edge with no MISO driver is reported (`SPI_MISO_Z`). | 4.3 | `err_test` (frame to an unpopulated chip select) |
| REQ-SPI-015 | `cs_n` rising mid-word aborts the frame: complete words take effect, the incomplete one is dropped by the slaves and reported by the monitor (`partial_bits`). | 4.4.2/4.4.3 (data moves to the register after the last bit) | `abort_test` (`spi_abort`, `spi_abort_mem`): read-back after every abort, scoreboard; `cp_abort` |
| REQ-SPI-016 | Write command: data words go to the register file from the start address, W/8 bytes per word. | odve slave protocol | scoreboard model on every frame (`rw_test`, `mode_test`, `burst_test`); `spi_reg_cg.cp_dir` |
| REQ-SPI-017 | Read command: data words return the register file from the start address. | odve slave protocol | scoreboard + in-test compares; `spi_reg_cg.cp_dir`, `x_dir_len` |
| REQ-SPI-018 | Word 0 out of every frame is the slave's ID replicated over the word. | odve slave protocol | scoreboard on every frame |
| REQ-SPI-019 | The address advances by W/8 per data word and wraps from 63 to 0; frames longer than the file keep wrapping. | odve slave protocol | `burst_test` (wrap, unaligned, longer-than-file); `spi_reg_cg.cp_wrap`, `cp_addr`, `cp_len.over` |
| REQ-SPI-020 | A command-only frame (no data words) changes nothing. | odve slave protocol | `burst_test`; `spi_reg_cg.cp_len.cmd_only` |
| REQ-SPI-021 | The slave agent in MEM mode (model in the driver) is interchangeable with the RTL slave. | odve | `spi_rw_mem`, `spi_mode_mem`, `spi_b2b_mem`, `spi_abort_mem` |
| REQ-SPI-022 | The slave agent in SEQ mode (model in a responding sequence, one request per word) is interchangeable with the RTL slave. | odve | `spi_rw_seq`, `spi_mode_seq`, `spi_burst_seq` |
| REQ-SPI-023 | The SCK rate is configurable (half period in system clocks); every component follows it. | 4.5 (baud rate divider) | `b2b_test` at half periods 4, 5 and 9 |
| REQ-SPI-024 | Frames follow each other back to back at the minimum tI, alternating slaves of different formats. | fig. 4-2/4-3 | `b2b_test` |
| REQ-SPI-025 | All random values come from `odve_rand` streams (same values for the same seed on both simulators). | odve (comp/agents/README.md) | `script/rand/rand_check.py odve/comp/agents/spi` exits 0 (static check, not a simulation) |
| REQ-SPI-026 | SS must be negated between bytes in CPHA=0. | 4.4.2 | not verified (deliberately not modelled: frames hold `cs_n` low over several words, see spec.md) |
| REQ-SPI-027 | Mode fault: SS of a master pulled low by another master. | 4.7.1 | not verified (multi-master not modelled) |

## Traceability

| Test (submit entries) | Requirements |
| --- | --- |
| `rw_test` (`spi_rw`, `spi_rw_mem`, `spi_rw_seq`) | 001, 006, 008, 016, 017, 018, 021, 022 |
| `mode_test` (`spi_mode`, `spi_mode_mem`, `spi_mode_seq`) | 001, 002, 003, 004, 005, 016, 017, 018, 021, 022 |
| `burst_test` (`spi_burst`, `spi_burst_seq`) | 005, 006, 007, 016, 017, 019, 020, 022 |
| `b2b_test` (`spi_b2b`, `spi_b2b_mem`) | 008, 010, 011, 012, 023, 024, 021 |
| `abort_test` (`spi_abort`, `spi_abort_mem`) | 015, 021 |
| `err_test` (`spi_err`) | 001, 009, 010, 011, 012, 013, 014 |
| `rand_check.py` | 025 |

25 of 27 requirements are verified; REQ-SPI-026 and REQ-SPI-027 are not
(behaviour deliberately outside the model).
