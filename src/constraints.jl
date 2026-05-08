# ==============================================================================
# constraints.jl
# ==============================================================================

using JuMP

function add_constraints!(m::Model,
                          data::ModelData,
                          vars::Dict{Symbol, Any})
    # --- Extract parameters ---
    sets = data.sets
    TD   = data.TD
    gscalar = data.gscalar
    tscalar = data.tscalar
    fscalar = data.fscalar
    HL = data.HL
    WP = data.WP
    El = data.El
    Ht = data.Ht
    Co = data.Co
    E_g = data.E_g
    E_eol = data.E_eol
    W_g = data.W_g

    # --- NEW: Extract Profiles ---
    PUE_Profile = data.PUE_Profile
    WUE_Profile = data.WUE_Profile

    # --- NEW: Water Parameters ---
    # We use get() with a default of infinity (1e20) so the model doesn't crash 
    # if you forget to add "Water_Limit" to Excel.
    Water_Limit = gscalar["Water_Limit"] * 1e-6 # <--- SCALED HERE
    
    # DC Parameters
    DC_Prof = data.DC_Prof 
    DC_Cap = gscalar["DC_Cap"]        
    DC_Active = gscalar["DC_Active"] 


    # --- Extract variables ---
    Cap = vars[:Cap]
    Exp = vars[:Exp]
    Dec = vars[:Dec]
    n   = vars[:n]
    
    P_p = vars[:P_p]
    P_g = vars[:P_g]
    Q_p = vars[:Q_p]
    F_c = vars[:F_c]
    P_c = vars[:P_c]
    Q_c = vars[:Q_c]
    K_p = vars[:K_p]
    
    P_le  = vars[:P_le]
    P_ch  = vars[:P_ch]
    P_dis = vars[:P_dis]
    
    L     = vars[:L]
    L_tot = vars[:L_tot]
    
    Mat_tot     = vars[:Mat_tot]
    Mat_EoL     = vars[:Mat_EoL]
    
    Em_scope = vars[:Em_scope]
    Em_man   = vars[:Em_man]
    Em_op    = vars[:Em_op]
    Em_eol   = vars[:Em_eol]

    # --- Capacity/Installation ---
    @constraint(m, [t in sets[:Tech_all]], Cap[t, gscalar["y_i"]] == TD[t].Cap_i)
    @constraint(m, [t in sets[:Tech_all], y in sets[:Y1]], Cap[t,y] == Cap[t,y-1] + Exp[t,y] - Dec[t,y])
    @constraint(m, [t in sets[:Tech_all], y in sets[:Years]], Cap[t,y] <= TD[t].Cap_max)

    @constraint(m, [t in sets[:Tech_all]], Exp[t, gscalar["y_i"]] == 0)
    @constraint(m, [t in sets[:Tech_all]], Dec[t, gscalar["y_i"]] == 0)

    # --- Decommission ---
    for t in sets[:Tech_all]
        y_target = TD[t].Li - TD[t].Li_p + gscalar["y_i"]
        if y_target in sets[:Years] 
            @constraint(m, Dec[t, y_target] == TD[t].Cap_i)
        end
        y_start = TD[t].Li + gscalar["y_i"] + 1
        y_end   = gscalar["y_f"]
        for y in y_start:y_end
            @constraint(m, Dec[t, y] == Exp[t, y-TD[t].Li])
        end
        for y in sets[:Years]
            y_preinstall = TD[t].Li - TD[t].Li_p + gscalar["y_i"]
            y_new_decom = TD[t].Li + gscalar["y_i"] + 1 : gscalar["y_f"]
            if y != y_preinstall && !(y in y_new_decom)
                @constraint(m, Dec[t, y] == 0)
            end
        end
    end

    # --- Generation ---
    if haskey(sets, :Tech_solar) && !isempty(sets[:Tech_solar])
        @constraint(m, [t in sets[:Tech_solar], h in sets[:Hours], y in sets[:Years]], P_p[t,h,y] <= Cap[t,y]*HL[(h,y)]*(1-tscalar["PT"][t]))
        @constraint(m, [t in sets[:Tech_solar], y in sets[:Years]], Cap[t,y] == n[t,y]*tscalar["cap_pan"][t])
    end
    if "wt" in sets[:Tech_all]
        @constraint(m, [h in sets[:Hours], y in sets[:Years]], P_p["wt",h,y] <= n["wt",y]*WP[(h,y)])
        @constraint(m, [y in sets[:Years]], Cap["wt",y] == n["wt",y]*tscalar["cap_t"]["wt"])
    end
    if "nu" in sets[:Tech_all]
        @constraint(m, [h in sets[:Hours], y in sets[:Years]], P_p["nu",h,y] <= Cap["nu",y])
        @constraint(m, [h in sets[:Hours], y in sets[:Years]], P_p["nu",h,y] >= Cap["nu",y]*0.6)
        @constraint(m, [y in sets[:Years]], sum(P_p["nu",h,y] for h in sets[:Hours]) <= Cap["nu",y]*TD["nu"].CF*8760)
        @constraint(m, [y in sets[:Years]], Cap["nu",y] == n["nu",y]*tscalar["cap_r"]["nu"])
    end
    if "cg_el" in sets[:Tech_all]
        @constraint(m, [h in sets[:Hours], y in sets[:Years]], P_p["cg_el",h,y] <= Cap["cg_el",y])
        @constraint(m, [h in sets[:Hours], y in sets[:Years]], P_p["cg_el",h,y] <= sum(F_c[f,"cg_ht",h,y] for f in sets[:BFuels])*tscalar["eff"]["cg_el"])
    end


    # --- Grid ---
    @expression(m, P_DC[h in sets[:Hours], y in sets[:Years]], DC_Active * DC_Prof[(h,y)] * DC_Cap * PUE_Profile[h])
    @constraint(m, [h in sets[:Hours], y in sets[:Years]], P_g[h,y] <= El[(h,y)] + P_DC[h,y])

    if "cg_ht" in sets[:Tech_all]
        @constraint(m, [h in sets[:Hours], y in sets[:Years]], Q_p["cg_ht",h,y] <= Cap["cg_ht",y]*tscalar["eff"]["cg_ht"])
        @constraint(m, [h in sets[:Hours], y in sets[:Years]], Q_p["cg_ht",h,y] == sum(F_c[f,"cg_ht",h,y] for f in sets[:BFuels])*tscalar["eff"]["cg_ht"])
    end
    if "hp" in sets[:Tech_all]
        @constraint(m, [h in sets[:Hours], y in sets[:Years]], Q_p["hp",h,y] <= Cap["hp",y])
        @constraint(m, [h in sets[:Hours], y in sets[:Years]], Q_p["hp",h,y] == P_c["hp",h,y]*tscalar["COP"]["hp"])
    end
    if "ab" in sets[:Tech_all]
        @constraint(m, [h in sets[:Hours], y in sets[:Years]], Q_p["ab",h,y]  <= Cap["ab",y]*tscalar["eff"]["ab"])
        @constraint(m, [h in sets[:Hours], y in sets[:Years]], Q_p["ab",h,y] == sum(F_c[f,"ab",h,y] for f in sets[:BFuels])*tscalar["eff"]["ab"])
    end
    if "ac" in sets[:Tech_all]
        @constraint(m, [h in sets[:Hours], y in sets[:Years]], K_p["ac",h,y] <= Cap["ac",y])
        @constraint(m, [h in sets[:Hours], y in sets[:Years]], K_p["ac",h,y] == Q_c["ac",h,y]*tscalar["COP"]["ac"])
    end
    if "ec" in sets[:Tech_all]
        @constraint(m, [h in sets[:Hours], y in sets[:Years]], K_p["ec",h,y] <= Cap["ec",y])
        @constraint(m, [h in sets[:Hours], y in sets[:Years]], K_p["ec",h,y] == P_c["ec",h,y]*tscalar["COP"]["ec"])
    end

    # --- Storage ---
    @constraint(m, [t in sets[:Tech_st], h in sets[:Hours], y in sets[:Years]], P_le[t,h,y] >= tscalar["SoC_min"][t]*Cap[t,y])
    @constraint(m, [t in sets[:Tech_st], h in sets[:Hours], y in sets[:Years]], P_le[t,h,y] <= tscalar["SoC_max"][t]*Cap[t,y])
    @constraint(m, [t in sets[:Tech_st], h in sets[:Hours], y in sets[:Years]], P_ch[t,h,y] <= Cap[t,y]/tscalar["h_bb"]["bb"])
    @constraint(m, [t in sets[:Tech_st], h in sets[:Hours], y in sets[:Years]], P_dis[t,h,y] <= Cap[t,y]/tscalar["h_bb"]["bb"])

    #Dynamics
    # First hour of the year
    for t in sets[:Tech_st], y in sets[:Y1]
        @constraint(m,
            P_le[t,1,y] == P_le[t,8760,y-1]*(1 - tscalar["eff_aut"][t]) + P_ch[t,1,y]*tscalar["eff_ch"][t] - P_dis[t,1,y]/tscalar["eff_dis"][t])
    end

    # All other hours
    for t in sets[:Tech_st], y in sets[:Years], h in sets[:Hours][2:end]
        @constraint(m,
            P_le[t,h,y] == P_le[t,h-1,y]*(1 - tscalar["eff_aut"][t]) + P_ch[t,h,y]*tscalar["eff_ch"][t] - P_dis[t,h,y]/tscalar["eff_dis"][t])
    end

    # --- Energy Balance ---
    @expression(m, P_prod[h in sets[:Hours], y in sets[:Years]], sum(P_p[t,h,y] for t in sets[:Tech_el_prod]) + P_g[h,y])
    @expression(m, P_cons[h in sets[:Hours], y in sets[:Years]], sum(P_c[t,h,y] for t in sets[:Tech_el_con]))
    @expression(m, P_stored[h in sets[:Hours], y in sets[:Years]], sum(P_ch[t,h,y] for t in sets[:Tech_st_el]))
    @expression(m, P_discharge[h in sets[:Hours], y in sets[:Years]], sum(P_dis[t,h,y] for t in sets[:Tech_st_el]))
    @constraint(m, [h in sets[:Hours], y in sets[:Years]], P_prod[h,y] - P_cons[h,y] + P_discharge[h,y] - P_stored[h,y] == El[(h,y)] + P_DC[h,y])

    @expression(m, Q_prod[h in sets[:Hours], y in sets[:Years]], sum(Q_p[t,h,y] for t in sets[:Tech_ht_prod]))
    @expression(m, Q_cons[h in sets[:Hours], y in sets[:Years]], sum(Q_c[t,h,y] for t in sets[:Tech_ht_con]))
    @expression(m, Q_stored[h in sets[:Hours], y in sets[:Years]], sum(P_ch[t,h,y] for t in sets[:Tech_st_ht]))
    @expression(m, Q_discharge[h in sets[:Hours], y in sets[:Years]], sum(P_dis[t,h,y] for t in sets[:Tech_st_ht]))
    @constraint(m, [h in sets[:Hours], y in sets[:Years]], Q_prod[h,y]-Q_cons[h,y]+Q_discharge[h,y]-Q_stored[h,y] == Ht[(h,y)])

    @expression(m, K_prod[h in sets[:Hours], y in sets[:Years]], sum(K_p[t,h,y] for t in sets[:Tech_co_prod]))
    @constraint(m, [h in sets[:Hours], y in sets[:Years]], K_prod[h,y] == Co[(h,y)])

    # --- Land use ---
    @constraint(m, [t in sets[:Tech_rw], y in sets[:Years]], L[t, y] == n[t,y]*tscalar["A"][t])
    @constraint(m, [y in sets[:Years]], L_tot[y] == sum(L[t,y] for t in sets[:Tech_rw]))

    # --- Material flow ---
    @constraint(m, [t in sets[:Tech_all], y in sets[:Years]], Mat_tot[t,y] == TD[t].We*Exp[t,y])
    @constraint(m, [t in sets[:Tech_all], y in sets[:Years]], Mat_tot[t,y] == sum(Mat_EoL[t,opt,y] for opt in sets[:EoL_options][t]))
   
    # --- Intermediate Expressions ---
    @expression(m, Pg_sum[t in sets[:Tech_el_prod], y in sets[:Years]], sum(P_p[t, h, y] for h in sets[:Hours])/1000)
    @expression(m, G_sum[y in sets[:Years]], sum(P_g[h, y] for h in sets[:Hours])/1000)
    @expression(m, F_sum[f in sets[:Fuels], y in sets[:Years]],
    f == "nf" ? Pg_sum["nu", y] :
    f == "ng" ? sum(F_c["ng",t,h,y] for t in sets[:Tech_ht_prod], h in sets[:Hours])/1000 :
    f == "rng" ? sum(F_c["rng",t,h,y] for t in sets[:Tech_ht_prod], h in sets[:Hours])/1000 : 0)

    # --- Emissions ---
    @expression(m, Em_grid[y in sets[:Years]], E_g[y]*G_sum[y]) #kton CO2
    @expression(m, Em_fuel[y in sets[:Years]], sum(fscalar["E_f"][f]*F_sum[f,y] for f in sets[:Fuels])) #kton CO2

    @constraint(m, [y in sets[:Years]], Em_scope[1,y] == Em_fuel[y])
    @constraint(m, [y in sets[:Years]], Em_scope[2,y] == Em_grid[y]) #kton CO2
    @constraint(m, [y in sets[:Years]], Em_scope[3,y] == Em_man[y]+Em_eol[y]) #kton CO2 

    @constraint(m, [y in sets[:Years]], Em_man[y] == sum(TD[t].E_man*Exp[t,y] for t in sets[:Tech_all])) #kton CO2 
    @constraint(m, [y in sets[:Years]], Em_op[y] == Em_grid[y] + Em_fuel[y]) #kton CO2 
    @constraint(m, [y in sets[:Years]], Em_eol[y] == sum(sum(Mat_EoL[t,opt,y]*E_eol[(t,opt)] for opt in sets[:EoL_options][t]) for t in sets[:Tech_all] if haskey(sets[:EoL_options], t))) #kton CO2 
    @expression(m, E_tot_scope[y in sets[:Years]], sum(Em_scope[s,y] for s in 1:3)) #kton CO2 
    
    @constraint(m, sum(E_tot_scope[y] for y in sets[:Years]) <= gscalar["E_target"])

    # --- Water Consumption ---
    
    # Variable Water (Techs only, EXCLUDES Grid)
    @expression(m, Water_Var_Total[y in sets[:Years]],
        sum( sum(P_p[t, h, y] for h in sets[:Hours]) * TD[t].W_Cons for t in sets[:Tech_el_prod] if haskey(TD, t) ) + # Electricity
        sum( sum(Q_p[t, h, y] for h in sets[:Hours]) * TD[t].W_Cons for t in sets[:Tech_ht_prod] if haskey(TD, t) ) + # Heating 
        sum( sum(K_p[t, h, y] for h in sets[:Hours]) * TD[t].W_Cons for t in sets[:Tech_co_prod] if haskey(TD, t) ) # Cooling 
    )
    # Fixed DC Water Consumption (Direct)
    @expression(m, Water_DC_Fixed[y in sets[:Years]],
        sum( (DC_Active * DC_Prof[(h,y)] * DC_Cap * PUE_Profile[h]) * WUE_Profile[h] for h in sets[:Hours] ))

    # Limit Constraint 
    @constraint(m, sum(Water_Var_Total[y] + Water_DC_Fixed[y] for y in sets[:Years]) <= Water_Limit)

    return nothing
end

