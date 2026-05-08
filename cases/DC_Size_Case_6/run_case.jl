# ==============================================================================
# DC Size Sensitivity — Case 6: ASE + Air Chillers
# Varies DC_Cap in Model_Data.xlsx: 100, 150, 200, 250, 300, 400, 500 MW
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
    dc_cap = Int(round(data.gscalar["DC_Cap"]))
    result_name = "Results_DCSize_$(dc_cap)MW.xlsx"
    export_results(m, vars, data; filename=result_name, plot=false, savepath=@__DIR__, save_raw=true)
    println("✅ Saved: ", result_name)
else
    println("⚠️  Status: ", termination_status(m))
end
