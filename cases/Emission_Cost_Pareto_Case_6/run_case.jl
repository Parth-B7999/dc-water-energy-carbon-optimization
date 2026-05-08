# ==============================================================================
# Emission-Cost Pareto Sweep — Case 6: ASE + Air Chillers
# (Same structure as Case 1 but uses DC_Cooling_Type = 1 in Model_Data.xlsx)
# ==============================================================================

using JuMP, Gurobi, XLSX, DataFrames

SRC = joinpath(@__DIR__, "..", "..", "src")
include(joinpath(SRC, "utils.jl")); using .Utils
include(joinpath(SRC, "variables.jl"))
include(joinpath(SRC, "constraints.jl"))
include(joinpath(SRC, "objective.jl"))
include(joinpath(SRC, "results.jl"))

path = joinpath(@__DIR__, "Model_Data.xlsx")
data = Utils.load_parameters(path)
CRF  = Utils.compute_crf(data.TD, data.gscalar["r"])

m = Model(Gurobi.Optimizer)
vars = add_variables!(m, data)
add_constraints!(m, data, vars)
set_objective!(m, data, CRF, vars)
optimize!(m)

if termination_status(m) == MOI.OPTIMAL
    # Set E_target in Model_Data.xlsx Model_Data sheet, then rename output accordingly
    result_name = "Results_Pareto_run.xlsx"
    export_results(m, vars, data; filename=result_name, plot=false, savepath=@__DIR__, save_raw=true)
    println("✅ Saved: ", result_name)
else
    println("⚠️  Status: ", termination_status(m))
end
