# QSPI agent - requirements

Spec references are to the Winbond W25Q32FV datasheet rev. H ("DS", see
`spec.md`); "odve" marks framework or model requirements the datasheet does
not state. Every test named runs in `vrf/work/rlist/submit.list` (entries
`qspi_*`). Coverpoints: `odve_qspi_cg` (agent package, sampled by the
monitor) and `qspi_flash_cg` (`vrf/tb/env/env_pkg.sv`, sampled by the
scoreboard).

| ID | Requirement | Spec | Verified by |
| --- | --- | --- | --- |
| REQ-QSPI-001 | SPI modes 0 and 3: input latched on rising, output shifted on falling CLK; in mode 0 the first bit is valid at /CS fall. | DS 6.1.1 | `read_test` in mode 0 (`qspi_read`, `_mem`) and 3 (`qspi_read_m3`, `qspi_read_seq_m3`), `rand_test` mode 3; scoreboard; `cp_mode`, `x_qpi_mode` |
| REQ-QSPI-002 | CLK at its idle level when /CS falls and rises (`QSPI_CPOL`). | DS 6.1.1 | every test (no error); `err_test` injects |
| REQ-QSPI-003 | Read Data 03h, 1-1-1, no dummy clocks. | DS 8.1.3 | `read_test`; `cp_cmd.read`, `cp_fmt.f111` |
| REQ-QSPI-004 | Fast Read 0Bh, 1-1-1, 8 dummy clocks. | DS 8.2.7 | `read_test`; `cp_cmd.fread` |
| REQ-QSPI-005 | Fast Read Dual Output 3Bh, 1-1-2, 8 dummy clocks, IO1 = D7 first. | DS 8.1.3 notes 7 | `read_test`; `cp_fmt.f112` |
| REQ-QSPI-006 | Fast Read Dual I/O BBh, 1-2-2, M7-0 in 4 clocks. | DS 8.1.3 note 6, 8.2.10 | `read_test`; `cp_fmt.f122` |
| REQ-QSPI-007 | Fast Read Quad Output 6Bh, 1-1-4, 8 dummy clocks, needs QE. | DS 6.1.3, 8.1.3 note 9 | `read_test` (QE set), `err_test` (QE clear); `cp_fmt.f114` |
| REQ-QSPI-008 | Fast Read Quad I/O EBh, 1-4-4, M7-0 in 2 clocks + 4 dummy, needs QE. | DS 8.2.11, notes 8, 10 | `read_test`, `err_test`; `cp_fmt.f144` |
| REQ-QSPI-009 | QPI 4-4-4 reads 0Bh and EBh with 2 dummy clocks (EBh: M7-0 are the dummy clocks). | DS 8.1.4 note 15, 8.2.11 (QPI), 8.2.34 | `read_test`, `rand_test`; `cp_fmt.f444`, `cp_qpi` |
| REQ-QSPI-010 | Reads stream through the array, crossing pages and wrapping at its end; address bits above the array are ignored. | DS 8.2.6 (odve: wrap at 8 KiB) | `read_test`; `qspi_flash_cg.cp_wrap` |
| REQ-QSPI-011 | WREN sets and WRDI clears WEL. | DS 7.1.2, 8.2.1 | `id_test` (SPI and QPI), `prog_test`; `qspi_flash_cg.cp_kind` |
| REQ-QSPI-012 | Read Status 1 = {WEL, BUSY}, repeated until /CS rises. | DS 7.1.1, 7.1.2, 8.1.4 note 2 | `id_test`, `busy_test` (700-byte status read across the end of an erase) |
| REQ-QSPI-013 | Write Status 2 (31h) with WEL sets QE; Read Status 2 shows it. | DS 7.1.10, 8.1.2 | `id_test` (set and clear) |
| REQ-QSPI-014 | JEDEC ID 9Fh: manufacturer, type (40h SPI / 60h QPI), capacity. | DS 8.1.1 | `id_test`; `cp_cmd.rdid` |
| REQ-QSPI-015 | Read SFDP 5Ah: 1-1-1 + 8 dummy, 256-byte space (A7-A0), "SFDP" signature, BFP density. | DS 8.2.30; JESD216 (not read, see spec.md) | `id_test` (incl. wrap inside the SFDP space) |
| REQ-QSPI-016 | Enter QPI 38h only with QE; Exit QPI FFh. | DS 6.1.4, 8.2.36 | `id_test`, `read_test`, `prog_test`; `err_test` (38h with QE clear: stays SPI) |
| REQ-QSPI-017 | Page Program 02h (1-1-1): needs WEL; only clears bits; bytes past the page end wrap to its start; more than 256 bytes overwrite. | DS 8.2.15, 8.1.4 note 3 | `prog_test`; `qspi_flash_cg.cp_overprog`, `cp_wrap`, `cp_outcome.no_wel` |
| REQ-QSPI-018 | Quad Page Program 32h (1-1-4), needs QE. | DS 8.1.3 | `prog_test`, `err_test` (QE clear); `cp_cmd.qpp` |
| REQ-QSPI-019 | QPI Page Program 02h (4-4-4). | DS 8.1.4 | `prog_test`, `rand_test` |
| REQ-QSPI-020 | Sector Erase 20h sets the 4 KiB sector to FFh, needs WEL. | DS 8.2.17 | `prog_test` (both sectors, SPI and QPI, and without WEL), `busy_test` |
| REQ-QSPI-021 | While BUSY only 05h/35h are taken; any other instruction is ignored and a read leaves the lines undriven. | DS 7.1.1 | `busy_test` (`qspi_busy`, `qspi_busy_seq`): read, program, WRDI during program/erase; `cp_outcome.busy` |
| REQ-QSPI-022 | BUSY falls at the end of the self-timed operation and WEL is then clear. | DS 7.1.1, 7.1.2 | `busy_test`, every program/erase helper (status poll); `qspi_flash_cg.cp_busy` |
| REQ-QSPI-023 | A page program whose /CS rises mid byte is not executed. | DS 8.2.15 | `err_test` (`QSPI_TRUNC`); `cp_outcome.inexact` |
| REQ-QSPI-024 | A sector erase with clocks after the address is not executed. | DS 8.2.17 | `err_test` (`QSPI_EXTRA`) |
| REQ-QSPI-025 | Quad instructions (6Bh, EBh, 32h, 38h) are ignored while QE = 0. | DS 6.1.3, 6.1.4 | `err_test`; `cp_outcome.no_qe` |
| REQ-QSPI-026 | One driver per io line: contention reported (`QSPI_IO_CONT`); a lane the phase needs undriven is reported (`QSPI_IO_Z`). | DS 8.2.10/8.2.11 ("IO pins should be high-impedance prior to the falling edge of the first data out clock") | every test (none reported); `err_test` injects both |
| REQ-QSPI-027 | /CS lead, trail and deselect times at least the minimum (`QSPI_LEAD`, `QSPI_TRAIL`, `QSPI_IDLE`). | DS 9.6 (tSLCH, tCHSH, tSHSL) | `err_test` injects each |
| REQ-QSPI-028 | /CS rising inside instruction/address is reported (`QSPI_TRUNC`) and has no effect. | DS 8.2.15/8.2.17 | `err_test` |
| REQ-QSPI-029 | An opcode not defined in the current mode is reported (`QSPI_UNK`, warning) and ignored. | DS 8.1.2-8.1.4 | `err_test` (ABh, FFh in SPI mode) |
| REQ-QSPI-030 | The slave agent's flash model in MEM mode is interchangeable with the RTL flash. | odve | `qspi_id_mem`, `qspi_read_mem`, `qspi_prog_mem`, `qspi_rand_mem_m3` |
| REQ-QSPI-031 | The slave agent in SEQ mode (model in a responding sequence; decode, per-byte and end-of-frame requests) is interchangeable with the RTL flash. | odve | `qspi_read_seq_m3`, `qspi_prog_seq`, `qspi_busy_seq` |
| REQ-QSPI-032 | All random values come from `odve_rand` streams. | odve (comp/agents/README.md) | `script/rand/rand_check.py odve/comp/agents/qspi` exits 0 (static check) |
| REQ-QSPI-033 | Continuous read mode (M5-4 = 10) skips the instruction of the next EBh/BBh. | DS 8.2.10, 8.2.11 | not verified (not modelled: M7-0 is always 00h) |
| REQ-QSPI-034 | Set Read Parameters C0h sets the QPI dummy clocks (2/4/6/8). | DS 8.2.34 | not verified (not modelled; `cfg.bus.qpi_dummy` exists in the agent, the RTL flash is fixed at 2) |

## Traceability

| Test (submit entries) | Requirements |
| --- | --- |
| `id_test` (`qspi_id`, `qspi_id_mem`) | 011-016, 030 |
| `read_test` (`qspi_read`, `qspi_read_m3`, `qspi_read_mem`, `qspi_read_seq_m3`) | 001, 003-010, 016, 030, 031 |
| `prog_test` (`qspi_prog`, `qspi_prog_mem`, `qspi_prog_seq`) | 011, 016-020, 022, 030, 031 |
| `busy_test` (`qspi_busy`, `qspi_busy_seq`) | 012, 020-022, 031 |
| `rand_test` (`qspi_rand`, `qspi_rand_mem_m3`) | 001, 003-009, 017-020, 030 |
| `err_test` (`qspi_err`) | 002, 007, 008, 016, 018, 023-029 |
| `rand_check.py` | 032 |

32 of 34 requirements are verified; REQ-QSPI-033 and REQ-QSPI-034 are not
(features outside the model).
