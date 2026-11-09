from ortools.sat.python import cp_model

def solve_packing_problem(rectangles, container_width, container_height):
    model = cp_model.CpModel()

    x_positions = []
    y_positions = []

    for i, (width, height) in enumerate(rectangles):
        x_positions.append(model.NewIntVar(0, container_width - width, f'x_{i}'))
        y_positions.append(model.NewIntVar(0, container_height - height, f'y_{i}'))

    xr={}
    yr={}
    for i in range(len(rectangles)):
        for j in range(i + 1, len(rectangles)):
            # No overlap constraint
            constraint1 = model.NewBoolVar(f'constraint1_{i}_{j}')
            model.Add(x_positions[i] + rectangles[i][0] <= x_positions[j]).OnlyEnforceIf(constraint1)

            constraint2 = model.NewBoolVar(f'constraint2_{i}_{j}')
            model.Add(x_positions[j] + rectangles[j][0] <= x_positions[i]).OnlyEnforceIf(constraint2)

            constraint3 = model.NewBoolVar(f'constraint3_{i}_{j}')
            model.Add(y_positions[i] + rectangles[i][1] <= y_positions[j]).OnlyEnforceIf(constraint3)

            constraint4 = model.NewBoolVar(f'constraint4_{i}_{j}')
            model.Add(y_positions[j] + rectangles[j][1] <= y_positions[i]).OnlyEnforceIf(constraint4)

            # Combine the boolean constraints using "OR"
            model.AddBoolOr([constraint1, constraint2, constraint3,constraint4])
            #model.Add(constraint1 != constraint2)
            #model.Add(constraint3 != constraint4)


    # Objective: minimize the width and height of the container
    model.Minimize(container_width + container_height)

    solver = cp_model.CpSolver()
    status = solver.Solve(model)

    if status == cp_model.OPTIMAL:
        print(f'Optimal Solution Found:')
        for i in range(len(rectangles)):
            print(f'job{i}: (Start-End={solver.Value(x_positions[i])}-{solver.Value(x_positions[i])+rectangles[i][0]}, Num={solver.Value(y_positions[i])}-{solver.Value(y_positions[i])+rectangles[i][1]},)')

    else:
        print('No solution found.')

# Example rectangles (width, height)
rectangles = [(2, 3), (1, 2), (3, 1), (2, 2), (2, 3), (1, 2), (3, 1), (2, 2)]
container_width = 50
container_height = 20

# Solve the packing problem
solve_packing_problem(rectangles, container_width, container_height)