from ortools.linear_solver import pywraplp


def main():
    # Data
    jobs = [
        [[10, 80],[20,40],[30,30]],
        [[8, 85]],
        [[22, 95]],
        [[10, 110]],
        [[5, 100]],
        [[30,22]]
    ]
    num_cpu = 100     # num lics/cpu  in parallel
    num_min = 7*24*60 #min in the week 
    # Solver
    # Create the mip solver with the SCIP backend.
    #solver = pywraplp.Solver.CreateSolver("SCIP")
    solver = pywraplp.Solver.CreateSolver("SAT")
    if not solver:
        return

    # Variables
    # x[i, j] is an array of 0-1 variables, which will be 1
    # if come Job configuration is selected.
    # xyss [i,j] is array of pairs (0-num_cpu,0-num_min)
    # xyee [i,j] is array of pairs (0-num_cpu,0-num_min)
    x = {}
    r = {}
    xyss = {}
    xyee = {}
    for i in range(len(jobs)):
        for j in range(len(jobs[i])):
            x   [i, j]    = solver.IntVar(0, 1, "")
            r   [i, j]    = solver.IntVar(0, 1, "")
            xyss[i, j, 0] = solver.IntVar(0, num_cpu-1, "")
            xyss[i, j, 1] = solver.IntVar(0, num_min-1, "")
            xyee[i, j, 0] = solver.IntVar(1, num_cpu-1, "")
            xyee[i, j, 1] = solver.IntVar(1, num_min-1, "")
            print (f"{i}, {j}, {len(jobs)}")

    for i in range(len(jobs)):
        for j in range(len(jobs[i])):           
            solver.Add(xyss[i,j,0]+jobs[i][j][0] == xyee[i,j,0]) # start cpu + num cpu = end cpu 
            solver.Add(xyss[i,j,1]+jobs[i][j][1] == xyee[i,j,1]) # start time + end time = end time
        for ii in range(i,len(jobs)) :
            print (f"{i}, {ii}, {len(jobs)}")
            solver.Add( xyss[i,j,1] >=  xyee [ii,j,1])

 
    # Constraints
    for i in range(len(jobs)):
        solver.Add(solver.Sum([ x[i, j] for j in range(len(jobs[i])) ]) == 1) # only one job configuration should be 
    
    solver.Add( solver.Sum( [ jobs[i][j][0]*x[i,j] for i in range(len(jobs)) for j in range(len(jobs[i])) ]) <= num_cpu ) 
    solver.Add( solver.Sum( [ jobs[i][j][1]*x[i,j] for i in range(len(jobs)) for j in range(len(jobs[i])) ]) <= num_min ) 
        
    # Solve
    status = solver.Solve()

    # Print solution.
    if status == pywraplp.Solver.OPTIMAL or status == pywraplp.Solver.FEASIBLE:
        for i in range(len(jobs)):
            for j in range(len(jobs[i])):
                # Test if x[i,j] is 1 (with tolerance for floating point arithmetic).
                if x[i,j].solution_value() :
                    print(f"Job {i} Started {xyss[i,j,1].solution_value()} on {xyss[i,j,0].solution_value()} CPUs")
                    print(f"Job {i} End     {xyee[i,j,1].solution_value()} on {xyee[i,j,0].solution_value()} CPUs")
    else:
        print("No solution found.")


if __name__ == "__main__":
    main()