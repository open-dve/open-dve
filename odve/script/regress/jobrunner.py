import concurrent.futures
import subprocess

class JobRunner :
    def __init__(self, max_threads):
        self.max_threads = max_threads

    def run_command(self, command):
        try:
            result = subprocess.run(command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
            output = result.stdout
            error = result.stderr
            return_code = result.returncode
            return f"Command: {command}\nOutput:\n{output}\nError:\n{error}\nReturn code: {return_code}"
        except subprocess.CalledProcessError as e:
            return f"Error running the command: {e}"
        except Exception as e:
            return f"An error occurred: {e}"

    def run_jobs(self, commands):
        with concurrent.futures.ThreadPoolExecutor(self.max_threads) as executor:
            futures = [executor.submit(self.run_command, cmd) for cmd in commands]
            results = []
            for future in concurrent.futures.as_completed(futures):
                results.append(future.result())
            return results