#!/usr/bin/env bash
# Self-test of odve_rand_pkg: builds odve_rand_tb on each simulator found,
# runs it under several +SEED values and compares every output line with
# odve_rand_ref.py (Annex N in Python). Exit 0 only if all of them match.
#
#   run_test.sh [-s vlt|qst|all] [-o <dir>] [seed ...]
#
#   -s   simulators: vlt (Verilator: $VERILATOR_ROOT/bin/verilator or the one
#        on PATH), qst (Questa/ModelSim: vlog/vsim on PATH), all (default:
#        every one that is installed; none installed is an error)
#   -o   work directory (default ./odve_rand_test)
#   seed the +SEED values (default: 1 424242 2147483646, plus a run without
#        +SEED, which must behave as SEED=1)
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
sims=all
out=$PWD/odve_rand_test
while getopts "s:o:h" o; do
    case $o in
        s) sims=$OPTARG ;;
        o) out=$OPTARG ;;
        *) sed -n '2,13p' "$0"; exit 2 ;;
    esac
done
shift $((OPTIND - 1))
seeds=${*:-1 424242 2147483646}

vlt=
if [ -n "${VERILATOR_ROOT:-}" ] && [ -x "$VERILATOR_ROOT/bin/verilator" ]; then
    vlt=$VERILATOR_ROOT/bin/verilator
elif command -v verilator > /dev/null; then
    vlt=$(command -v verilator)
fi
have_qst=
command -v vsim > /dev/null && command -v vlog > /dev/null && have_qst=1

run_vlt= run_qst=
case $sims in
    vlt) run_vlt=1 ;;
    qst) run_qst=1 ;;
    all) [ -n "$vlt" ] && run_vlt=1; [ -n "$have_qst" ] && run_qst=1 ;;
    *) echo "run_test.sh: -s takes vlt, qst or all"; exit 2 ;;
esac
if [ -n "$run_vlt" ] && [ -z "$vlt" ]; then echo "run_test.sh: no Verilator found"; exit 2; fi
if [ -n "$run_qst" ] && [ -z "$have_qst" ]; then echo "run_test.sh: no vlog/vsim on PATH"; exit 2; fi
if [ -z "$run_vlt$run_qst" ]; then echo "run_test.sh: no simulator found"; exit 2; fi

src="$here/../odve_rand_pkg.sv $here/odve_rand_tb.sv"
mkdir -p "$out" || exit 2
cd "$out" || exit 2
fail=0

if [ -n "$run_vlt" ]; then
    echo "verilator: building ($vlt)"
    if ! "$vlt" --binary --timing -Wno-fatal -Wno-lint -Wno-style --top-module odve_rand_tb \
            --Mdir obj_vlt -o odve_rand_tb $src > build_vlt.log 2>&1; then
        grep -m5 '%Error' build_vlt.log; echo "verilator: build failed, see $out/build_vlt.log"; exit 1
    fi
fi
if [ -n "$run_qst" ]; then
    echo "questa: building"
    rm -rf work_qst
    vlib work_qst > /dev/null
    if ! vlog -sv -work work_qst $src > build_qst.log 2>&1 || grep -q '^\*\* Error' build_qst.log; then
        grep -m5 '^\*\* Error' build_qst.log; echo "questa: build failed, see $out/build_qst.log"; exit 1
    fi
fi

# check <dir> <seed>: the dir's rand_out.txt against the reference
check() {
    python3 "$here/odve_rand_ref.py" --seed "$2" > "$1/ref.txt" || return 1
    if [ ! -s "$1/rand_out.txt" ]; then echo "  $1: no rand_out.txt (see $1/log.txt)"; return 1; fi
    local n d
    n=$(wc -l < "$1/ref.txt")
    d=$(diff <(sort "$1/rand_out.txt") <(sort "$1/ref.txt") | grep -c '^<')
    if [ "$d" -ne 0 ]; then
        echo "  $1: $d of $n lines differ from the reference:"
        diff <(sort "$1/rand_out.txt") <(sort "$1/ref.txt") | head -6 | sed 's/^/    /'
        return 1
    fi
    if ! grep -q '^sweep_out_of_range 0$' "$1/rand_out.txt"; then echo "  $1: values out of range"; return 1; fi
    echo "  $1: $n lines, all equal to the reference"
}

first=${seeds%% *}
for s in $seeds none; do
    arg="+SEED=$s"; ref=$s
    [ "$s" = none ] && { arg=; ref=1; }
    # the first seed also writes the draw trace (+ODVE_RAND_TRACE)
    [ "$s" = "$first" ] && arg="$arg +ODVE_RAND_TRACE"
    if [ -n "$run_vlt" ]; then
        d=vlt_$s; mkdir -p $d
        (cd $d && ../obj_vlt/odve_rand_tb $arg +verilator+seed+7 > log.txt 2>&1)
        check $d $ref || fail=1
    fi
    if [ -n "$run_qst" ]; then
        d=qst_$s; mkdir -p $d
        (cd $d && vsim -batch -lib ../work_qst odve_rand_tb $arg -sv_seed 13 -do 'run -all; quit -f' > log.txt 2>&1)
        check $d $ref || fail=1
    fi
done
# the traces of the simulators: the same values at the same times
if [ -n "$run_vlt" ] && [ -n "$run_qst" ]; then
    if python3 "$here/../../../../script/rand/rand_trace_diff.py" vlt_$first/odve_rand_trace.txt qst_$first/odve_rand_trace.txt; then
        echo "  draw traces of vlt_$first and qst_$first: equal"
    else
        fail=1
    fi
elif [ ! -s "$( [ -n "$run_vlt" ] && echo vlt_$first || echo qst_$first )/odve_rand_trace.txt" ]; then
    echo "  +ODVE_RAND_TRACE wrote no trace"; fail=1
fi
if [ "$fail" -eq 0 ]; then echo "odve_rand self-test: PASS"; else echo "odve_rand self-test: FAIL"; fi
exit $fail
