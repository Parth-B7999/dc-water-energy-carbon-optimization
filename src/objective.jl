# objective.jl

using JuMP
# No module, no relative imports needed for the flat script

"""
    set_objective!(m, data, CRF, vars)

Adds the objective function (minimize total costs).
"""
function set_objective!(m::Model,
                        data::ModelData, 
                        CRF,
                        vars::Dict{Symbol, Any})

    # --- Extract parameters ---
    sets = data.sets
    TD   = data.TD
    gscalar = data.gscalar
    tscalar = data.tscalar
    fscalar = data.fscalar
    
    # Costs
    C_f = data.C_f
    C_g = data.C_g
    C_eol = data.C_eol
    Rev_eol = data.Rev_eol

    # --- Extract Variables ---
    #Capacity
    Exp = vars[:Exp]
    Cap = vars[:Cap]
    Dec = vars[:Dec]
    #Land
    L_tot = vars[:L_tot]
    #Costs
    Co_inv   = vars[:Co_inv]
    Co_fixom = vars[:Co_fixom]
    Co_varom = vars[:Co_varom]
    Co_eol   = vars[:Co_eol]
    # Material flow variables
    Mat_EoL     = vars[:Mat_EoL]

    Pg_sum = m[:Pg_sum]
    G_sum  = m[:G_sum]
    F_sum  = m[:F_sum]

    # --- Economics ---
    
    # Investment
    @constraint(m, Co_inv[gscalar["y_i"]] == 0)
    @constraint(m, [y in sets[:Y1]], Co_inv[y] == (sum( sum( TD[t].C_In * Exp[t,a] * CRF[t] * ( (a <= y && y <= a + TD[t].Li - 1) ? 1.0 : 0.0 ) for a in sets[:Years]) for t in sets[:Tech_all] )))  

    @expression(m, InvYearCost[y in sets[:Years]], sum(TD[t].C_In*Exp[t,y] for t in sets[:Tech_all]))
    
    # Fixed O&M
    @constraint(m, [y in sets[:Years]], Co_fixom[y] == sum(TD[t].C_OM*Cap[t,y] for t in sets[:Tech_all]) + gscalar["C_l"]* L_tot[y])

    # Variable O&M
    @expression(m, Co_grid[y in sets[:Years]], C_g[y]*G_sum[y])
    @expression(m, Co_fuels[y in sets[:Years]], sum(C_f[f,y]*F_sum[f,y] for f in sets[:Fuels]))

    @constraint(m, [y in sets[:Years]], Co_varom[y] == Co_grid[y] + Co_fuels[y])

    # EoL
    # Decommision costs
    @expression(m, Co_dec[y in sets[:Years]], sum(TD[t].C_Dec*Cap[t,y]*CRF[t] for t in sets[:Tech_all]))
    
    # Recovery/recycling/disposal costs
    @expression(m, Co_rec[y in sets[:Years]], 
        sum(sum(C_eol[(t,o)] * Mat_EoL[(t,o,y)] for o in sets[:EoL_options][t]) for t in sets[:Tech_all] if haskey(sets[:EoL_options], t)))

    # Revenues
    @expression(m, Rev[y in sets[:Years]], 
        sum(sum(Rev_eol[(t,o)] * Mat_EoL[(t,o,y)]*CRF[t] for o in sets[:EoL_options][t]) for t in sets[:Tech_all] if haskey(sets[:EoL_options], t)))
    
    # Final EoL Cost Calculation
    @constraint(m, [y in sets[:Years]], Co_eol[y] == Co_dec[y] + Co_rec[y] - Rev[y])
    
    # Annual costs
    @expression(m, Co_ann[y in sets[:Years]], Co_inv[y]+Co_fixom[y]+Co_varom[y]+Co_eol[y])
    
    # Total costs
    @expression(m, Total_costs, sum(Co_ann[y] for y in sets[:Years]))

    @objective(m, Min, Total_costs)
end


# # module Objective

# using JuMP
# import ..Utils: ModelData, TechData

# export set_objective!

# """
#     add_objective!(m, vars, sets)

# Adds the objective function (minimize total costs).
# """
# function set_objective!(m::Model,
#                         data::ModelData, 
#                         CRF,
#                         vars::Dict{Symbol, Any})

#     sets = data.sets
#     TD   = data.TD
#     gscalar = data.gscalar
#     tscalar = data.tscalar
#     fscalar = data.fscalar
#     #Costs
#     C_f = data.C_f
#     C_g = data.C_g
#     C_eol = data.C_eol
#     Rev_eol = data.Rev_eol

#     for (name, var) in vars
#         @eval $(name) = $var
#     end

#     Pg_sum = m[:Pg_sum]
#     G_sum  = m[:G_sum]
#     F_sum = m[:F_sum]

#     #--- Economics ---
#     #Investment
#     @constraint(m, Co_inv[gscalar["y_i"]] == 0)
#     @constraint(m, [y in sets[:Y1]], Co_inv[y] == (sum( sum( TD[t].C_In * Exp[t,a] * CRF[t] * 10^-3 *( (a <= y && y <= a + TD[t].Li - 1) ? 1.0 : 0.0 ) for a in sets[:Years]) for t in sets[:Tech_all] )))  

#     @expression(m, InvYearCost[y in sets[:Years]], sum(TD[t].C_In*Exp[t,y]*10^-3 for t in sets[:Tech_all]))
#     #Fixed O&M
#     @constraint(m, [y in sets[:Years]], Co_fixom[y] == sum(TD[t].C_OM*Cap[t,y]*10^-3 for t in sets[:Tech_all]) + gscalar["C_l"]* L_tot[y]*10^-3)

#     #Variable O&M
#     @expression(m, Co_grid[y in sets[:Years]], C_g[y]*G_sum[y]*10^-3)
#     @expression(m, Co_fuels[y in sets[:Years]], sum(C_f[f,y]*F_sum[f,y]*10^-3 for f in sets[:Fuels]))

#     @constraint(m, [y in sets[:Years]], Co_varom[y] == Co_grid[y] + Co_fuels[y])

#     #EoL
#     #Decommision costs
#     @expression(m, Co_dec[y in sets[:Years]], sum(TD[t].C_Dec*Cap[t,y]*CRF[t]*10^-3 for t in sets[:Tech_all])) #annualized

#     @expression(m, DecYearCost[y in sets[:Years]], sum(TD[t].C_Dec * Dec[t,a] * 10^-3 *((a + TD[t].Li) == y ? 1.0 : 0.0) for t in sets[:Tech_all], a in sets[:Years]
#         if (a + TD[t].Li) in sets[:Years]))
#     # Recovery/recycling/disposal costs
#     @expression(m, Co_rec[y in sets[:Years]], 
#         sum(sum(C_eol[(t,o)] * vars[:Mat_EoL_use][(t,o,y)]*10^-3 for o in sets[:EoL_options][t]) for t in sets[:Tech_all] if haskey(sets[:EoL_options], t)))

#     @expression(m, RecYearCost[y in sets[:Years]], 
#         sum(sum(C_eol[(t,o)] * vars[:Mat_EoL][(t,o,y)]*10^-3 for o in sets[:EoL_options][t]) for t in sets[:Tech_all] if haskey(sets[:EoL_options], t)) )
#     # Revenues
#     @expression(m, Rev[y in sets[:Years]], 
#         sum(sum(Rev_eol[(t,o)] * vars[:Mat_EoL_use][(t,o,y)]*CRF[t]*10^-3 for o in sets[:EoL_options][t]) for t in sets[:Tech_all] if haskey(sets[:EoL_options], t)))
    
#     @expression(m, RevYearCost[y in sets[:Years]], 
#         sum(sum(Rev_eol[(t,o)] * vars[:Mat_EoL][(t,o,y)]*10^-3 for o in sets[:EoL_options][t]) for t in sets[:Tech_all] if haskey(sets[:EoL_options], t)))
    
#     @constraint(m, [y in sets[:Years]], Co_eol[y] == Co_dec[y] + Co_rec[y] - Rev[y])
#     @expression(m, EoLYearCost[y in sets[:Years]], DecYearCost[y] + RecYearCost[y] + RevYearCost[y])
#     #Annual costs
#     @expression(m, Co_ann[y in sets[:Years]], Co_inv[y]+Co_fixom[y]+Co_varom[y]+Co_eol[y])
#     #Total costs
#     @expression(m, Total_costs, sum(Co_ann[y] for y in sets[:Years]))

#     @objective(m, Min, Total_costs)
# end

# # end #module