from ortools.sat.python import cp_model

# Create a CP model
model = cp_model.CpModel()

# Define the time range (adjust as needed)
time_range = 48  # Specify the time range in hours

# Define the tasks with different durations and the range of workers
tasks = []
task_durations = [2, 3, 1, 4, 2, 2, 3, 1, 4, 3]  # Example durations for 10 tasks
min_workers = 3  # Minimum number of workers for a task
max_workers = 10  # Maximum number of workers for a task

# Define the tasks and add constraints
for i, duration in enumerate(task_durations):
    start_var = model.NewIntVar(0, time_range, f'task_{i}_start')  # Adjusted time range
    end_var = model.NewIntVar(0, time_range, f'task_{i}_end')  # Adjusted time range
    workers_var = model.NewIntVar(min_workers, max_workers, f'task_{i}_workers')  # Number of workers variable
    tasks.append((start_var, end_var, workers_var))

    # Add constraint: task end time is task start time + duration
    model.Add(end_var == start_var + duration)

# Add constraint: Tasks do not overlap unless running in parallel
for i in range(len(tasks)):
    for j in range(i + 1, len(tasks)):
        overlap_var = model.NewBoolVar(f'overlap_{i}_{j}')
        model.Add(overlap_var == model.NewBoolVar(f'bool_overlap_{i}_{j}'))
        model.Add(tasks[i][1] <= tasks[j][0] + time_range * (1 - overlap_var))
        model.Add(tasks[j][1] <= tasks[i][0] + time_range * (1 - overlap_var))

# Define the solver
solver = cp_model.CpSolver()

# Solve the problem
status = solver.Solve(model)

if status == cp_model.OPTIMAL:
    print("Optimal Schedule Found:")
    for i, (start, end, workers) in enumerate(tasks):
        print(f"Task {i + 1}: [{solver.Value(start)} - {solver.Value(end)}] hours, Workers: {solver.Value(workers)}")
else:
    print("No optimal solution found.")
