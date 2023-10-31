from ortools.sat.python import cp_model

# Create a CP model
model = cp_model.CpModel()

# Define your tasks, workers, and constraints
# You need to add your specific constraints and variables here.

# Example: Defining a task with a start time and duration
task1_start = model.NewIntVar(0, 24, 'task1_start')  # Task 1 start time between 0 and 24 hours
task1_duration = 2  # Task 1 has a duration of 2 hours
task1_end = model.NewIntVar(0, 24, 'task1_end')  # Task 1 end time

# Example: Ensure that Task 1 starts and ends correctly
model.Add(task1_start + task1_duration == task1_end)

# Define the solver
solver = cp_model.CpSolver()

# Solve the problem
status = solver.Solve(model)

if status == cp_model.OPTIMAL:
    # Extract and print the solution
    for task in [task1_start, task1_end]:  # Replace with your task variables
        print(f"Task {task.Name()}: Start at {solver.Value(task)} hours")

    print("Optimal Schedule Found")
else:
    print("No optimal solution found.")