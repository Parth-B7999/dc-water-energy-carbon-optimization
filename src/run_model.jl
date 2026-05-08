using JuMP, Gurobi, XLSX, DataFrames
"""
    run_model(path::String)

Builds and solves the optimization model using input parameters
from the Excel file at `path`.
"""
function run_model(path::String)
    # Load parameters
    data = Utils.load_parameters(path)
    CRF = Utils.compute_crf(data.TD, data.gscalar["r"]) 

    # Create optimization model
    m = Model(Gurobi.Optimizer)
    #set_silent(m)   # comment this out if you want solver logs

    # Add variables
    vars = Variables.add_variables!(m, data)

    # Add constraints
    Constraints.add_constraints!(m, data, vars)

    # Add objective
    Objective.set_objective!(m, data, CRF, vars)

    # Solve
    optimize!(m)

    return m, vars
end


