# Requirement to agents
1. Possibility to run with ModelSim SE
1. Do not use SV construction with randomize(), $urandom() or $random(): take every random value from an odve_rand stream (comp/common/rand/odve_rand_pkg.sv), which gives the same values for the same +SEED on every simulator. script/rand/rand_check.py lists the calls that bypass it.
1.  Do not use function coverage to keep running with ModelSim SE. USe instead of it Code coverage. We can handle code coverage toggling by condition with the same manner like Functional covergroups. 
1. Agent should use SV construction what can be compiled with Verilator (optional).
1. Agents should have 2 part synthesable and non synthesable, 2 filelists and has possibility to run with HW accselerators. 
1. It should have separate package 
1. it should have special filelist with dependency to make compilation process incremental 
1. Documentation of agent tip and trick should located in doc folder
1. intf - contains interfaces only 
1. src - contains source of files





# Agents

Each complete agent has `README.md` (layout, cfg knobs, plusargs, how to run), `doc/spec.md` (protocol summary, the sources used and their access level, modelled / not modelled) and `doc/req.md` (`REQ-<P>-NNN` with a traceability table to the `submit` runs). Run any of them with `cd <agent>/vrf/work/run && source sourceme && ./regress.py submit [-ropts="VERILATOR=1"] [-cov]`.

| Agent | Protocol | Governing spec (access) | Roles / DUT | `submit` runs |
| --- | --- | --- | --- | --- |
| `apb` | AMBA APB3 | Arm AMBA APB (public) | master, slave mem/seq, cov-emu; RTL register-file slave | 6 |
| `i2c` | I2C | NXP UM10204 Rev. 7.0 (public) | controller, target mem/seq; RTL target, 7/10-bit, stretching | 16 |
| `smbus` | SMBus | SMBus 3.3 (public) | host, device mem/seq, all 11 protocols, PEC, timeouts, SMBALERT#; RTL device. Layered on `i2c` | 16 |
| `pmbus` | PMBus | PMBus 1.3.1 Part I/II (public archive) | host, device mem/seq, paging, LINEAR11/16, CML faults; RTL device. Layered on `smbus` | 13 |
| `i3c` | MIPI I3C (SDR) | I3C Basic v1.2 (public after a form; not read - see its spec.md) | controller, target mem/seq; ENTDAA, CCCs, IBI, Hot-Join; RTL target | 14 |
| `spi` | SPI | Motorola SPI Block Guide V02.07 (public) | master, slave mem/seq, 4 modes, MSB/LSB, 8/16/32-bit; RTL slave x2 | 13 |
| `qspi` | Quad SPI NOR | Winbond W25Q32FV datasheet (public); JESD216 not read | controller, flash mem/seq, 1-1-1 ... 4-4-4/QPI; RTL 8 KiB NOR flash | 14 |
| `jtag` | JTAG TAP | IEEE 1149.1 (paid, not read; public summaries) | host, TAP mem/seq; RTL TAP and a 2-TAP chain | 26 |
| `uart` | UART | TI PC16550D datasheet (public) | TX/RX, echo mem/seq, all 16550 formats, RTS/CTS; RTL echo UART | 15 |
| `mdio` | MDIO (802.3 C22/C45) | IEEE 802.3 (not reachable; public presentations/datasheets) | STA, PHY/MMD mem/seq, multi-PHY; RTL PHY management block | 16 |
| `i2s` | I2S / LJ / RJ / TDM | NXP UM11732 Rev. 3.0 (public) | TX/RX x clock controller/target; RTL RX -> swap/negate -> TX | 36 |
| `spmi` | MIPI SPMI | members-only, not read (public overviews, Linux driver) | master, slave mem/seq, PM commands, ACK/NACK; RTL slave | 16 |
| `rffe` | MIPI RFFE | members-only, not read (public papers, patents) | master, slave mem/seq, ext/long, half-speed read; RTL slave | 17 |
| `axi`, `ahb` | AMBA | - | stubs (no `vrf/work`) | - |
