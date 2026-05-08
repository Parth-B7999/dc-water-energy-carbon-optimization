# ==============================================================================
# Baseline Cases: Case 1 (Evaporative Cooling) and Case 6 (Air Chillers)
#
# Set DC_Cooling_Type in Model_Data.xlsx > Model_Data sheet:
#   DC_Cooling_Type = 0  → Case 1: ASE + Evaporative Cooling
#   DC_Cooling_Type = 1  → Case 6: ASE + Air Chillers
# ==============================================================================

using JuMP
using Gurobi
using XLSX
using DataFrames

# Load shared source files
SRC = joinpath(@__DIR__, "..", "..", "src")
include(joinpath(SRC, "utils.jl"))
using .Utils
include(joinpath(SRC, "variables.jl"))
include(joinpath(SRC, "constraints.jl"))
include(joinpath(SRC, "objective.jl"))
include(joinpath(SRC, "results.jl"))

# Data file path (local to this case folder)
path = joinpath(@__DIR__, "Model_Data.xlsx")

println("--- Loading Parameters ---")
data = Utils.load_parameters(path)
CRF  = Utils.compute_crf(data.TD, data.gscalar["r"])

println("--- Building Model ---")
m = Model(Gurobi.Optimizer)

println("... Adding Variables")
vars = add_variables!(m, data)

println("... Adding Constraints")
add_constraints!(m, data, vars)

println("... Setting Objective")
set_objective!(m, data, CRF, vars)

println("--- Starting Solver ---")
optimize!(m)

if termination_status(m) == MOI.OPTIMAL
    println("\n✅ Optimal Solution Found!")
    println("Objective Value (NPV): ", objective_value(m))

    dc_type = get(data.gscalar, "DC_Cooling_Type", 0.0)
    result_name = dc_type == 1 ? "Results_DC_Case_6.xlsx" : "Results_DC_Case_1.xlsx"

    println("--- Exporting Results ---")
    export_results(m, vars, data;
                   filename = result_name,
                   plot = false,
                   savepath = @__DIR__,
                   save_raw = true)
    println("✅ Results saved to: ", joinpath(@__DIR__, result_name))
else
    println("\n⚠️  Model did not solve to optimality.")
    println("Status: ", termination_status(m))
end
