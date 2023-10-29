# Requirement to agents
1. Possibility to run with ModelSim SE
1. Do not use SV construction with randomize(), use only $urandom() or external CPP libs to generate $random() values
1.  Do not use function coverage to keep running with ModelSim SE. USe instead of it Code coverage. We can handle code coverage toggling by condition with the same manner like Functional covergroups. 
1. Agent should use SV construction what can be compiled with Verilator (optional).
1. Agents should have 2 part synthesable and non synthesable, 2 filelists and has possibility to run with HW accselerators. 
1. It should have separate package 
1. it should have special filelist with dependency to make compilation process incremental 
1. Documentation of agent tip and trick should located in doc folder
1. intf - contains interfaces only 
1. src - contains source of files




