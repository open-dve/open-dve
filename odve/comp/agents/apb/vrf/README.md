# How to run compilation

```bash
source sourceme 
make clean
make all 
make run
#or 
make clean all run 

``` 

# Precondition
## sourceme
* Please provide path to you local installed ModelSim or add ModelSim/bin to PATH :
* TODO: provide example 
## Make
* install Git Bash ( https://git-scm.com/downloads )
* configure you VSCode terminal to use GitBash by default (https://code.visualstudio.com/docs/terminal/basics)
* Please install make tool to your Git Bash (https://gist.github.com/evanwill/0207876c3243bbb6863e65ec5dc3f058 )


## TB Folder structure 
- dut - save example of dut to test compilation 
- tb  - save example of Tb with agent instantiation and DUT connection
- work - folder to save and run simulation and regression 
- list - folder with TB filelist
    - filelist_tb.f
        - filelist_tb - should be separated to separate compilation per each package
    - filelist_dut.f
    - filelist_uvm.f