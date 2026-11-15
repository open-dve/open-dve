# i2s verification environment

See [../README.md](../README.md) (testbench, plusargs, how to run, tests)
and [../doc/req.md](../doc/req.md) (requirements -> tests).

- `dut/dut.sv` - RTL I2S receiver -> swap/negate -> I2S transmitter
- `tb/` - `top.sv`, `dut_cfg_if.sv`, `env/` (cc, scb, env), `tests/`
- `list/` - `fl_uvm.f`, `fl_dut.f`, `fl_tb.f`, `fl.f` (Verilator)
- `work/` - `run/`, `mini/`, `check/`, `common/`, `rlist/{submit,mini}.list`
