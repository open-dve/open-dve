# UART agent verification environment

See [../README.md](../README.md) (testbench, tests, plusargs, how to run).

```bash
source sourceme
make aclean all run TESTNAME=basic_test                # ModelSim/Questa
make aclean all run TESTNAME=basic_test VERILATOR=1    # Verilator
./regress.py submit -j 2 -exer
```
