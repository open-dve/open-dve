# i3c - verification requirements

Each requirement: statement, reference (section of `doc/spec.md`, which
names the public source it comes from - the I3C Basic PDF itself was not
read, see spec.md section 1), and how it is verified. "Monitor" checks run
in every test; "scb" = the scoreboard's target model (`vrf/tb/env/scb.sv`);
coverpoints are in `odve_i3c_cg` (`src/agent/odve_i3c_agent_pkg.sv`). Test
names are the `submit.list` entries.

| ID | Requirement | Ref | Verified by |
| --- | --- | --- | --- |
| REQ-I3C-001 | The controller generates START, repeated START and STOP as SDA edges while SCL is high; SDA otherwise changes only while SCL is low. | spec 3 | Monitor decodes every transfer from these conditions; a transfer ending inside a byte is a UVM_ERROR. All tests. |
| REQ-I3C-002 | SCL is driven push-pull by the controller only; SCL low and high last at least 2 clks inside a transfer. | spec 2, 3 | Interface: `scl = m_scl_o` (no other driver exists). Monitor timing check, all tests. |
| REQ-I3C-003 | In the address header after START and in every ACK bit, SDA is open-drain: nobody drives it high. | spec 2, 4.1 | Monitor `check_od` on header + ACK of every START segment and on IBI headers. All tests. Not negatively tested (no test injects a push-pull header). |
| REQ-I3C-004 | No two SDA drivers fight (push-pull high against a low). | spec 2 | Monitor contention check every clk, all tests (0 errors). Not negatively tested. |
| REQ-I3C-005 | Every target ACKs the broadcast header 7'h7E/W, with or without a dynamic address. | spec 4.2 | scb: ACK of every CCC_BC / ENTDAA == targets online. i3c_ccc, i3c_daa*, all tests (RSTDAA first). |
| REQ-I3C-006 | Private write: first byte = register pointer, later bytes written with auto-increment; each byte followed by an odd-parity T-bit. | spec 4.1 | scb register model + every read compared; monitor parity check. i3c_priv*, i3c_daa*, cp_kind.priv_wr, cp_len. |
| REQ-I3C-007 | Private read: bytes from the pointer, auto-increment; T=1 while more data, T=0 on the last register (the target ends the read). | spec 4.1 | scb checks data and each T-bit against the model; priv_test full-file read (16 bytes, t_end) and last-two-registers read. i3c_priv*, cp_tend.target_end. |
| REQ-I3C-008 | The controller may end a read after a T=1 with a repeated START (abort); the target releases SDA on SCL rising after T=1. | spec 4.1 | priv_test one-byte read (`t_end` = 0 checked), random reads shorter than the data; scb; monitor (no contention, Sr+P decode). cp_tend.ctrl_abort. |
| REQ-I3C-009 | A private transfer may start with S <DA> directly (no 7E header, arbitrated header). | spec 4.1 | priv_test `use_7e = 0` write + read, scb. i3c_priv*. |
| REQ-I3C-010 | A header to an address no target owns is NACKed and the controller ends with P. | spec 5 | priv_test (0x5A), daa_test (old addresses after RSTDAA), ccc_test (direct CCCs to 0x5B), scb ACK checks. x_kind_ack nack bins. |
| REQ-I3C-011 | ENTDAA: every target without a dynamic address arbitrates with {PID, BCR, DCR} on open-drain SDA; the lowest wins the round, receives the address and ACKs it. | spec 4.3 | scb checks the winner's ID per round against the lowest online unassigned ID and that all targets end up assigned; monitor checks the round is open-drain. i3c_daa (2 targets), i3c_daa_dut, all tests via `assign_all`. cp_kind.entdaa. |
| REQ-I3C-012 | ENTDAA ends when no target ACKs `Sr 7E/R`; with every target assigned, no round is answered. | spec 4.3 | daa_test second ENTDAA (0 rounds), setdasa_test ENTDAA after SETDASA. |
| REQ-I3C-013 | The ENTDAA address carries odd parity; on a wrong one the winner NACKs and takes part in the next round. | spec 4.3, 5 | parity_test (round 0 bad parity: NACK, then N+1 rounds), scb `daa_ack == daa_par_ok`, monitor flags an ACK with bad parity. i3c_parity, i3c_parity_mem. |
| REQ-I3C-014 | RSTDAA makes every target forget its dynamic address. | spec 4.2 | daa_test: after RSTDAA + ENTDAA with a new pool the old addresses NACK; scb. cp_ccc.rstdaa. |
| REQ-I3C-015 | SETDASA (direct, to the static address) gives a target without a dynamic address one; a target that has one, or an unknown static address, NACKs. | spec 4.2 | setdasa_test (RTL 0x50 -> 0x40, agent 0x51 -> 0x41, 0x52 NACK, second SETDASA NACK), scb. cp_ccc.setdasa. |
| REQ-I3C-016 | ENEC/DISEC (broadcast and direct) set/clear the target's interrupt (bit 0) and Hot-Join (bit 3) enables. | spec 4.2 | ccc_test (both forms), ibi_test (DISEC stops IBIs, ENEC re-enables; scb errors on any IBI from a disabled target). cp_ccc enec/disec bins. |
| REQ-I3C-017 | SETMWL (broadcast, direct) stores a 16-bit value that GETMWL returns MSB first. | spec 4.2 | ccc_test, scb GETMWL compare. |
| REQ-I3C-018 | GETPID (6 bytes, MSB first), GETBCR, GETDCR return the target's identity; the target ends each with T=0. | spec 4.2 | daa_test, ccc_test, setdasa_test; scb compares payload and length/T. |
| REQ-I3C-019 | GETSTATUS returns bit 5 = protocol error (cleared by the read) and bit 0 = IBI pending. | spec 4.2 | parity_test (set, then clear), ccc_test (clear), ibi_test (pending after DISEC, clear after delivery); scb checks bit 5, the test bit 0. |
| REQ-I3C-020 | A write byte with a wrong T-bit is ignored by the target together with the rest of the transfer, and sets the protocol-error status. | spec 4.1, 5 | parity_test: bad T on byte 2 and on the pointer byte, read-back compared with the scb model (which drops the same bytes), GETSTATUS[5]. i3c_parity (RTL), i3c_parity_mem (agent). cp_perr.err. |
| REQ-I3C-021 | The monitor detects every write T-bit parity error. | spec 5 | parity_test: `mon.n_perr_seen` == number injected (write and ENTDAA). |
| REQ-I3C-022 | IBI: a target with an address, events enabled and BCR[1] requests a START on an idle bus, arbitrates {DA, R}; on the controller's ACK it sends its Mandatory Data Byte (T=0) when BCR[2], nothing otherwise. | spec 4.4 | ibi_test step 1: RTL target (MDB checked by scb), agent target (no payload). i3c_ibi, i3c_ibi_dut. cp_kind.ibi. |
| REQ-I3C-023 | Simultaneous IBIs: the lower dynamic address wins the arbitration, the other is served next. | spec 4.4 | ibi_test step 2 (order checked). i3c_ibi. |
| REQ-I3C-024 | A pending IBI also arbitrates in the header after any controller START (not after Sr); the controller serves it and retries its own transfer. | spec 4.4 | ibi_test step 3 (raised during back-to-back traffic, idle gaps < t_aval). i3c_ibi, i3c_ibi_dut. |
| REQ-I3C-025 | A NACKed IBI stays pending and is retried; the controller can disable it with DISEC sent after the Sr following its NACK; ENEC lets it through. | spec 4.4 | ibi_test step 4: NACK seen, DISEC accepted, no further requests for 2000 clks, GETSTATUS pending, ENEC, delivered, pending cleared. |
| REQ-I3C-026 | Hot-Join: a target without an address (ENHJ set) requests 7'h02/W; the controller ACKs or NACKs; after an ACK an ENTDAA assigns the target. | spec 4.4 | hotjoin_test (NACK then ACK, ENTDAA with 1 round, private transfers to the new address); scb (Hot-Join only from an unassigned target). i3c_hotjoin. cp_kind.hotjoin. |
| REQ-I3C-027 | The agent's target role behaves like the RTL target: autonomous (registers in the driver) and reactive (registers in a responding sequence). | spec 4.1 | i3c_priv_mem, i3c_priv_seq, i3c_ccc_seq, i3c_parity_mem, i3c_daa / i3c_ibi / i3c_setdasa / i3c_hotjoin (both targets on one bus): the same scoreboard model holds. |
| REQ-I3C-028 | The monitor publishes one item per private transfer, CCC (per target for direct CCCs), ENTDAA (all rounds), IBI and Hot-Join, and samples the coverage group. | spec 4 | scb consumes every item (its counters are in each log); `-cov` regression: cp_kind all 8 bins. |
| REQ-I3C-029 | Every random value comes from an `odve_rand` stream (same values on every simulator for the same SEED). | comp/common/rand/README | `script/rand/rand_check.py comp/agents/i3c` exit 0. |
| REQ-I3C-030 | HDR modes, multi-lane, controller handoff and the other features listed in spec 6 as not modelled. | spec 6 | not verified (out of scope of the model). |

## Traceability: requirement -> tests

| Requirement | i3c_daa | i3c_daa_dut | i3c_priv | i3c_priv_mem | i3c_priv_seq | i3c_priv_both | i3c_ccc | i3c_ccc_seq | i3c_parity | i3c_parity_mem | i3c_ibi | i3c_ibi_dut | i3c_setdasa | i3c_hotjoin |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 001-005 | x | x | x | x | x | x | x | x | x | x | x | x | x | x |
| 006 | x | x | x | x | x | x |  |  | x | x | x | x | x | x |
| 007 |  |  | x | x | x | x |  |  |  |  |  |  |  |  |
| 008 | x | x | x | x | x | x |  |  | x | x | x | x | x | x |
| 009 |  |  | x | x | x | x |  |  |  |  |  |  |  |  |
| 010 | x | x | x | x | x | x | x | x |  |  |  |  |  |  |
| 011 | x | x | x | x | x | x | x | x | x | x | x | x |  | x |
| 012 | x | x |  |  |  |  |  |  |  |  |  |  | x |  |
| 013 |  |  |  |  |  |  |  |  | x | x |  |  |  |  |
| 014 | x | x |  |  |  |  | x | x | x | x |  |  | x |  |
| 015 |  |  |  |  |  |  |  |  |  |  |  |  | x |  |
| 016 |  |  |  |  |  |  | x | x |  |  | x | x |  |  |
| 017 |  |  |  |  |  |  | x | x |  |  |  |  |  |  |
| 018 | x | x |  |  |  |  | x | x |  |  |  |  | x |  |
| 019 |  |  |  |  |  |  | x | x | x | x | x | x |  |  |
| 020 |  |  |  |  |  |  |  |  | x | x |  |  |  |  |
| 021 |  |  |  |  |  |  |  |  | x | x |  |  |  |  |
| 022 |  |  |  |  |  |  |  |  |  |  | x | x |  |  |
| 023 |  |  |  |  |  |  |  |  |  |  | x |  |  |  |
| 024 |  |  |  |  |  |  |  |  |  |  | x | x |  |  |
| 025 |  |  |  |  |  |  |  |  |  |  | x | x |  |  |
| 026 |  |  |  |  |  |  |  |  |  |  |  |  |  | x |
| 027 | x |  |  | x | x | x | x | x |  | x | x |  | x | x |
| 028 | x | x | x | x | x | x | x | x | x | x | x | x | x | x |
| 029 | (rand_check.py, not a simulation) |
| 030 | not verified |

30 requirements: 28 verified by tests in `submit` (003 and 004 only
positively: the checks run everywhere but no test injects the fault), 029
by `rand_check.py`, 030 not verified (out of scope).
