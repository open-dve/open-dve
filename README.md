# open-dve
Open Design Verification Environment

Project give possibility to unify TB building/running/result gathering. 
- Scripting : 
    - Compilation flow to touch only updated files
    - Recompilation flow
    - Run simulation without recompilation and wide configurable scripting
    - Run many TCs without recompilation 
    - Run few compilation in parallel 
    - Run regression throw regression lists
    - Make a structure of regression running lists
    - Running on Jenkins 
    - Running by optimal schedule
- Source :
    - APB agent
    - AHB agent
    - AXI agent
    - PCIe VIP
    - NVME VIP
    - MPHY VIP 
    - UNIPRO VIP
    - UFS VIP
- Randomization :
    - use simple $urandom 
    - use DPI to call constraint solver from Google Lib 
- Coverage :    
    - Generate DUT coverage (line,cond,tgl,fsm,branch) 
    - Avoid to use Func Covergoups and use instead of this DUT coverage to mimic bins,coverpoint,covergroups simple behavior.
- Log :
    - make a standard for LOG message generation to have possibility recollect statistics of errors and reuse it to predict or give a help understand the error reason


To run TB : 
- install gnu make 
- install python3
- install bash for git
- install tool readlink 