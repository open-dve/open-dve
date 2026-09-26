"""Verdict of one regression run, read from its own run.log rather than from
make's exit code: `vsim -batch` exits 0 even when the test hit UVM_ERROR /
UVM_FATAL, so the UVM report summary at the end of the log is the only
trustworthy signal. Questa prefixes every logged line with "# ", Verilator
does not -- both shapes are accepted."""
import os
import re
from dataclasses import dataclass

# "UVM_ERROR :    3" -- a line of the report summary (note the colon).
_SUMMARY_RE = re.compile(r"^[#\s]*UVM_(ERROR|FATAL)\s*:\s*(\d+)\s*$", re.M)
# "UVM_ERROR file.sv(42) @ 100: path [ID] text" -- an actual message line.
_MESSAGE_RE = re.compile(r"^[#\s]*(UVM_(?:ERROR|FATAL)\s+(?!:).*?)\s*$", re.M)
# The marker the Makefiles append when `timeout` killed the simulator: such a
# log stops mid-run, or is empty when the kill landed during startup, so it
# has no summary of its own to explain the failure.
_TIMEOUT_RE = re.compile(r"^[#\s]*\*\*\* ODVE_TIMEOUT:\s*(.*?)\s*$", re.M)
# Tool-level failures, for logs with no UVM message at all: Questa's
# "** Error: ..." / "** Fatal: ..." and Verilator's "%Error: ...".
_TOOL_ERR_RE = re.compile(r"^[#\s]*(?:\*\*\s*(?:Error|Fatal)\b.*|%Error.*?)$", re.M)


@dataclass
class RunStatus:
    passed: bool
    reason: str                 # one-line explanation, printed next to PASS/FAIL
    errors: int = None          # UVM_ERROR count from the summary, None if no summary
    fatals: int = None
    last_error: str = None      # text of the last UVM_ERROR/UVM_FATAL message seen
    timed_out: bool = False

    @property
    def verdict(self):
        return "PASS" if self.passed else "FAIL"


def _read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return None


def extract_error(path, fallback=None):
    """Best one-line explanation of why the run in `path`'s log failed, for the
    -exer report: the timeout marker if the simulator was killed, else the last
    UVM_ERROR/UVM_FATAL message, else the last tool-level error line, else
    `fallback` (what the verdict itself said)."""
    text = _read(path)
    if text is None:
        return fallback or f"no run.log at {path}"
    m = _TIMEOUT_RE.search(text)
    if m:
        return "ODVE_TIMEOUT: " + m.group(1)
    messages = _MESSAGE_RE.findall(text)
    if messages:
        return messages[-1]
    tool = _TOOL_ERR_RE.findall(text)
    if tool:
        return tool[-1].strip()
    if not text.strip():
        return fallback or "run.log is empty (simulation produced no output)"
    return fallback or "no error message found in run.log"


def parse_run_log(path, returncode=0):
    """Judge a run: make must have exited 0, the log must exist and end with a
    UVM report summary, and that summary must count zero errors and fatals.
    A log carrying the ODVE_TIMEOUT marker failed on the clock, which is
    reported instead of the missing summary it also has. The last error message
    in the log is kept for the status line (with +UVM_MAX_QUIT_COUNT=1 it is
    the one that stopped the simulation)."""
    if not os.path.isfile(path):
        return RunStatus(False, f"no run.log at {path}" if returncode == 0
                         else f"make exited {returncode}, no run.log at {path}")

    text = _read(path)
    if text is None:
        return RunStatus(False, f"cannot read {path}")

    messages = _MESSAGE_RE.findall(text)
    last_error = messages[-1] if messages else None

    # The clock wins over every other reading: the log is truncated by
    # construction, so a missing summary here is a symptom, not the cause.
    m = _TIMEOUT_RE.search(text)
    if m:
        return RunStatus(False, m.group(1) or "killed by TIMEOUT",
                         last_error=last_error, timed_out=True)

    if returncode != 0:
        return RunStatus(False, f"make exited {returncode}", last_error=last_error)

    counts = {}
    for sev, n in _SUMMARY_RE.findall(text):
        counts[sev] = int(n)        # last summary wins if there are several
    errors = counts.get("ERROR")
    fatals = counts.get("FATAL")

    if errors is None and fatals is None:
        return RunStatus(False, "no UVM report summary in log (simulation did not finish)",
                         last_error=last_error)
    errors = errors or 0
    fatals = fatals or 0
    if errors or fatals:
        return RunStatus(False, f"UVM_ERROR={errors} UVM_FATAL={fatals}",
                         errors, fatals, last_error)
    return RunStatus(True, f"UVM_ERROR=0 UVM_FATAL=0", errors, fatals, last_error)
