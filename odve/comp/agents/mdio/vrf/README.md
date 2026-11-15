# MDIO agent - standalone verification environment

See [../README.md](../README.md) for the testbench, plusargs (`+mdio_slave=`),
tests and how to run them, and [../doc/req.md](../doc/req.md) for what each
test verifies.

- `dut/`  RTL PHY management block (Clause 22 + Clause 45)
- `tb/`   top, env (cc, scoreboard), tests
- `list/` fl_tb.f, fl_dut.f, fl_uvm.f, fl.f (Verilator)
- `work/` run/mini/check work dirs and rlist/*.list
