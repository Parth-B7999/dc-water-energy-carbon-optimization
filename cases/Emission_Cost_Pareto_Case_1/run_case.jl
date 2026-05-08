# ==============================================================================
# Emission-Cost Pareto Sweep — Case 1: ASE + Evaporative Cooling
#
# Runs the model at multiple emission targets to trace the Pareto front.
# The emission target E_target is set by modifying Model_Data.xlsx before
# each run, or by overriding it programmatically as shown below.
#
# Pareto points in the paper (emission reduction from baseline):
#   100% (no constraint), 90%, 80%, 70%, 65%, 50%
# ==============================================================================

using JuMP
using Gurobi
using XLSX
using DataFrames

SRC = joinpath(@__DIR__, "..", "..", "src")
include(joinpath(SRC, "utils.jl"))
using .Utils
include(joinpath(SRC, "variables.jl"))
include(joinpath(SRC, "constraints.jl"))
include(joinpath(SRC, "objective.jl"))
include(joinpath(SRC, "results.jl"))

path = joinpath(@__DIR__, "Model_Data.xlsx")

# --- Single run at default E_target (set in Model_Data.xlsx) ---
println("--- Loading Parameters ---")
data = Utils.load_parameters(path)
CRF  = Utils.compute_crf(data.TD, data.gscalar["r"])

println("--- Building Model ---")
m = Model(Gurobi.Optimizer)

vars = add_variables!(m, data)
add_constraints!(m, data, vars)
set_objective!(m, data, CRF, vars)

println("--- Solving ---")
optimize!(m)

if termination_status(m) == MOI.OPTIMAL
    e_pct = Int(round(data.gscalar["E_target_pct"] * 100))
    result_name = "Results_Pareto_$(e_pct)pct.xlsx"

    export_results(m, vars, data;
                   filename = result_name,
                   plot = false,
                   savepath = @__DIR__,
                   save_raw = true)
    println("✅ Saved: ", result_name)
else
    println("⚠️  Status: ", termination_status(m))
end
