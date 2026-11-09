import concurrent.futures
import subprocess
import time
from dataclasses import dataclass


@dataclass
class JobResult:
    name: str
    command: str
    returncode: int
    stdout: str
    stderr: str
    seconds: float


class JobRunner:
    """Run shell commands with at most `max_jobs` in flight. Results come back
    in completion order, and `on_done` (if given) is called for each job as
    soon as it finishes -- from the caller's thread, so printing in it needs
    no locking -- while the remaining jobs keep running."""

    def __init__(self, max_jobs):
        self.max_jobs = max(1, int(max_jobs))

    def run_command(self, name, command):
        start = time.monotonic()
        try:
            result = subprocess.run(command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                    universal_newlines=True, encoding="utf-8", errors="replace")
            rc, out, err = result.returncode, result.stdout, result.stderr
        except Exception as e:
            rc, out, err = -1, "", f"An error occurred: {e}"
        return JobResult(name, command, rc, out, err, time.monotonic() - start)

    def run_jobs(self, jobs, on_done=None):
        """`jobs` is a list of (name, command). Blocks until every job has
        finished and returns their JobResults in the order they completed."""
        results = []
        with concurrent.futures.ThreadPoolExecutor(self.max_jobs) as executor:
            futures = [executor.submit(self.run_command, name, cmd) for name, cmd in jobs]
            for future in concurrent.futures.as_completed(futures):
                result = future.result()
                results.append(result)
                if on_done:
                    on_done(result, len(results), len(jobs))
        return results
