# ==============================================================================
# Results.jl - ROBUST VERSION
# ==============================================================================

using JuMP, XLSX, PyPlot
using JLD2, FileIO 

function export_results(m::Model, vars, data; 
                        filename::String = "Results_all.xlsx",
                        plot::Bool = true,
                        savepath::String = pwd(),
                        save_raw::Bool = true) # <--- NEW FLAG

    # --- Ensure save directory exists ---
    isdir(savepath) || mkpath(savepath)
    excel_path = joinpath(savepath, filename)
    raw_path   = joinpath(savepath, replace(filename, ".xlsx" => ".jld2"))

    # --- Extract basic sets from data ---
    sets = data.sets
    TD = data.TD
    Y = sets[:Years]
    Tech_all = sets[:Tech_all]
    Tech_rw  = sets[:Tech_rw]
    Fuels    = get(sets, :Fuels, String[])
    
    println(">>> Starting Export Process...")

    # --------------------------------------------------------------------------
    # 0. THE SAFETY NET: Save Raw Data (JLD2)
    # --------------------------------------------------------------------------
    if save_raw
        println("   -> Saving raw binary backup to $raw_path...")
        # We convert JuMP variables to simple Value Dictionaries to save space/time
        # This ensures you can access ANY variable later without re-optimizing.
        
        # Helper to unpack JuMP dicts to values
        function unpack_var(v)
            return Dict(k => value(v[k]) for k in eachindex(v))
        end

        raw_data = Dict(
            "Cap" => unpack_var(vars[:Cap]),
            "Exp" => unpack_var(vars[:Exp]),
            "Dec" => unpack_var(vars[:Dec]),
            "P_p" => unpack_var(vars[:P_p]),
            "P_g" => unpack_var(vars[:P_g]),
            "Q_p" => unpack_var(vars[:Q_p]),
            "K_p" => unpack_var(vars[:K_p]),
            # Save storage vars if they exist
            "P_ch" => haskey(vars, :P_ch) ? unpack_var(vars[:P_ch]) : nothing,
            "P_dis" => haskey(vars, :P_dis) ? unpack_var(vars[:P_dis]) : nothing,
            "P_le" => haskey(vars, :P_le) ? unpack_var(vars[:P_le]) : nothing,
            "F_c"  => haskey(vars, :F_c) ? unpack_var(vars[:F_c]) : nothing,
            # Metadata
            "Objective" => objective_value(m),
            "Status" => string(termination_status(m)),
            "SolveTime" => solve_time(m)
        )
        save(raw_path, "results", raw_data)
        println("   -> Backup Complete. You are safe!")
    end

    # -------------------------
    # Helper Functions
    # -------------------------
    function write_matrix!(sheet, mat, start_row=1, start_col=1)
        for i in 1:size(mat,1)
            for j in 1:size(mat,2)
                sheet[start_row + i - 1, start_col + j - 1] = mat[i,j]
            end
        end
    end

    function build_tech_matrix(var_values, Tech, Years)
        mat = Matrix{Any}(undef, length(Years)+1, length(Tech)+1)
        mat[1,:] .= ["Year"; Tech]
        for (i,y) in enumerate(Years)
            mat[i+1,1] = y
            for (j,t) in enumerate(Tech)
                mat[i+1,j+1] = var_values[t,y]
            end
        end
        return mat
    end

    function build_lcoe_matrix(TD, Exp, Cap, gen_data, C_f, F_sum, sets, Years, CRF)
        rows = Vector{Vector{Any}}()
        push!(rows, ["Year"; String.(sets[:Tech_all])]) 
        Tech = String.(sets[:Tech_all])
        for y in Years
            row = Any[y]
            for t in Tech
                inv = value(sum( TD[t].C_In * Exp[t,a] * CRF[t] *( (a <= y && y <= a + TD[t].Li - 1) ? 1.0 : 0.0 ) for a in sets[:Years]))
                fixom = value(TD[t].C_OM * Cap[t,y])
                fuel = (t == "NU") ? sum(value(C_f[f,y] * F_sum[f,y]) for f in sets[:Fuels]) : 0.0
                dec = value(TD[t].C_Dec * Cap[t,y] * CRF[t])
                el_prod = haskey(gen_data, t) ? gen_data[t][y] : 0.0
                lcoe_y = el_prod > 0 ? (inv + fixom + fuel + dec)/el_prod : 0.0
                push!(row, lcoe_y)
            end
            push!(rows, row)
        end
        mat = Matrix{Any}(undef, length(rows), length(rows[1]))
        for (i,row) in enumerate(rows)
            mat[i,:] .= row
        end
        return mat
    end

    function build_cost_breakdown_matrix(TD, Exp, Cap, gen_data, G_sum, C_f, F_sum, sets, Years, CRF)
        Tech = String.(sets[:Tech_all])
        header = ["Year"]
        for t in Tech
            push!(header, "$t Inv_cost")
            push!(header, "$t FixOM_cost")
            push!(header, "$t Fuel_cost")
            push!(header, "$t Dec_cost")
            push!(header, "$t Generation_MWh")
        end
        push!(header, "Grid_Energy_MWh")
        mat = Matrix{Any}(undef, length(Years) + 1, length(header))
        mat[1, :] .= header
        for (i, y) in enumerate(Years)
            row = Any[y]
            for t in Tech
                inv = value(sum(TD[t].C_In * Exp[t,a] * CRF[t] * ((a <= y && y <= a + TD[t].Li - 1) ? 1.0 : 0.0) for a in sets[:Years]))
                fixom = value(TD[t].C_OM * Cap[t,y])
                fuel = (t == "NU") ? sum(value(C_f[f,y] * F_sum[f,y]) for f in sets[:Fuels]) : 0.0
                dec = value(TD[t].C_Dec * Cap[t,y] * CRF[t])
                gen = haskey(gen_data, t) ? gen_data[t][y] : 0.0
                append!(row, [inv, fixom, fuel, dec, gen])
            end
            push!(row, G_sum[i])
            mat[i + 1, :] .= row
        end
        return mat
    end

    function build_capexpdec_matrix(cap, exp, dec, Tech, Years)
        header = ["Year"]
        for t in Tech
            push!(header, "$t Cap")
            push!(header, "$t Exp")
            push!(header, "$t Dec")
        end
        mat = Matrix{Any}(undef, length(Years)+1, length(header))
        mat[1,:] .= header
        for (i,y) in enumerate(Years)
            row = Any[y]
            for t in Tech
                push!(row, cap[t,y])
                push!(row, exp[t,y])
                push!(row, dec[t,y])
            end
            mat[i+1,:] .= row
        end
        return mat
    end

    function build_eol_matrix(Mat_EoL, C_eol, E_eol, sets, Years)
        rows = Vector{Vector{Any}}()
        push!(rows, ["Technology", "Option", "Material", "Cost", "Emissions"])
        for t in sets[:Tech_all]
            if !haskey(sets[:EoL_options], t) continue end
            for opt in sets[:EoL_options][t]
                total_mat = sum(value(Mat_EoL[t,opt,y]) for y in Years)
                cost = C_eol[(t,opt)] * total_mat 
                emi  = E_eol[(t,opt)] * total_mat 
                push!(rows, Any[t,opt,total_mat,cost,emi])
            end
        end
        mat = Matrix{Any}(undef, length(rows), length(rows[1]))
        for (i,row) in enumerate(rows)
            mat[i,:] .= row
        end
        return mat
    end

    # --------------------------------------------------------------------------
    # Calculate Water Consumption
    # --------------------------------------------------------------------------
    function calculate_water_consumption(m, vars, data)
        sets = data.sets
        TD = data.TD
        years = sets[:Years]
        gscalar = data.gscalar
        W_g = data.W_g 

        # --- Profiles ---
        PUE_Profile = data.PUE_Profile
        WUE_Profile = data.WUE_Profile
        
        DC_Active = get(gscalar, "DC_Active", 0.0)
        DC_Cap    = get(gscalar, "DC_Cap", 0.0)
        
        water_header = ["Year", "DC_Direct", "Cogen_Direct", "Boiler_Direct", "Nuclear_Direct", "Chillers_Direct", "Grid_Indirect", "Total_Consumption"]
        dm_water = Matrix{Any}(undef, length(years)+1, length(water_header))
        dm_water[1,:] .= water_header
        
        Pg_sum_local = haskey(vars, :Pg_sum) ? vars[:Pg_sum] : m[:Pg_sum]
        Q_p = vars[:Q_p]
        K_p = vars[:K_p]
        G_sum_local = m[:G_sum]
        
        for (i, y) in enumerate(years)
            # 1. DC Direct
            # Units: MWh * MMGal/MWh = MMGal
            w_dc = 0.0
            for h in sets[:Hours]
                load_h = DC_Active * data.DC_Prof[(h,y)] * DC_Cap * PUE_Profile[h]
                w_dc += load_h * WUE_Profile[h]
            end

            # 2. Cogen Direct
            w_cogen = 0.0
            if haskey(TD, "cg_el")
                gen = value(Pg_sum_local["cg_el", y]) # GWh
                # TD W_Cons is MMGal/MWh. 
                # Pg_sum is GWh.
                # Must convert GWh to MWh: GWh * 1000
                w_cogen = (gen * 1000) * TD["cg_el"].W_Cons
            end

            # 3. Boiler Direct
            w_boiler = 0.0
            if haskey(TD, "ng") 
                heat_gen = sum(value(Q_p["ng", h, y]) for h in sets[:Hours]) # MWh
                w_boiler = heat_gen * TD["ng"].W_Cons # MWh * MMGal/MWh
            end

            # 4. Nuclear Direct
            w_nuc = 0.0
            if haskey(TD, "nu")
                gen = value(Pg_sum_local["nu", y]) # GWh
                w_nuc = (gen * 1000) * TD["nu"].W_Cons
            end

            # 5. Chillers Direct
            w_chillers = 0.0
            if haskey(TD, "ec")
                cool_gen = sum(value(K_p["ec", h, y]) for h in sets[:Hours]) # MWh
                w_chillers += cool_gen * TD["ec"].W_Cons
            end
            if haskey(TD, "sc")
                cool_gen = sum(value(K_p["sc", h, y]) for h in sets[:Hours]) # MWh
                w_chillers += cool_gen * TD["sc"].W_Cons
            end

            # 6. Grid Indirect
            grid_gwh = value(G_sum_local[y]) # GWh
            grid_factor = get(W_g, y, 0.0) # MMGal/MWh
            
            # GWh * 1000 = MWh. 
            # MWh * MMGal/MWh = MMGal.
            w_grid = (grid_gwh * 1000) * grid_factor

            total = w_dc + w_cogen + w_boiler + w_nuc + w_chillers + w_grid
            dm_water[i+1, :] .= [y, w_dc, w_cogen, w_boiler, w_nuc, w_chillers, w_grid, total]
        end
        return dm_water
    end

    # -------------------------
    # Extract variables
    # -------------------------
    Cap, Exp, Dec = vars[:Cap], vars[:Exp], vars[:Dec]
    Co_inv, Co_fixom, Co_varom, Co_eol = vars[:Co_inv], vars[:Co_fixom], vars[:Co_varom], vars[:Co_eol]
    Em_man, Em_op, Em_eol, Em_scope = vars[:Em_man], vars[:Em_op], vars[:Em_eol], vars[:Em_scope]
    Mat_EoL, Land = vars[:Mat_EoL], vars[:L]
    
    # NEW: Fetch Storage/Fuel vars safely
    P_ch  = haskey(vars, :P_ch) ? vars[:P_ch] : nothing
    P_dis = haskey(vars, :P_dis) ? vars[:P_dis] : nothing
    F_c   = haskey(vars, :F_c) ? vars[:F_c] : nothing

    F_sum  = haskey(m, :F_sum) ? m[:F_sum] : Dict()

    cap_tech = value.(Cap[Tech_all,Y])
    cap_exp  = value.(Exp[Tech_all,Y])
    cap_decom = value.(Dec[Tech_all,Y])
    Land_vals = value.(Land[Tech_rw,Y])

    Inv_costs = value.(Co_inv[Y])
    OM_fix_costs = value.(Co_fixom[Y])
    OM_var_costs = value.(Co_varom[Y])
    Dec_costs = value.(Co_eol[Y])

    Inv_costs_year = [value(m[:InvYearCost][y]) for y in Y]

    gen_data_dict = Dict{String, Dict{Int, Float64}}()
    for t in sets[:Tech_el_prod]
        gen_data_dict[t] = Dict{Int, Float64}()
        for y in Y
            gen_data_dict[t][y] = value(m[:Pg_sum][t,y])
        end
    end
    G_sum_vec = [value(m[:G_sum][y]) for y in Y]

    Man_emissions = value.(Em_man[Y])
    Op_emissions  = value.(Em_op[Y])
    Dec_emissions = value.(Em_eol[Y])
    Scope_emissions = value.(Em_scope[1:3,Y])

    # -------------------------
    # Build Excel matrices
    # -------------------------
    dm_cap  = build_tech_matrix(cap_tech, Tech_all, Y)
    dm_exp  = build_tech_matrix(cap_exp, Tech_all, Y)
    dm_dec  = build_tech_matrix(cap_decom, Tech_all, Y)
    dm_land = build_tech_matrix(Land_vals, Tech_rw, Y)

    dm_capacity_all = build_capexpdec_matrix(cap_tech, cap_exp, cap_decom, Tech_all, Y)
    dm_eol_summary = build_eol_matrix(Mat_EoL, data.C_eol, data.E_eol, data.sets, Y)
    CRF = Utils.compute_crf(TD, data.gscalar["r"])
    
    dm_LCOE = build_lcoe_matrix(TD, Exp, Cap, gen_data_dict, data.C_f, F_sum, data.sets, Y, CRF)
    dm_LCOE_breakdown = build_cost_breakdown_matrix(TD, Exp, Cap, gen_data_dict, G_sum_vec, data.C_f, F_sum, data.sets, Y, CRF)
    
    dm_water = calculate_water_consumption(m, vars, data)

    # --- NEW: Metadata Matrix ---
    dm_meta = Matrix{Any}(undef, 4, 2)
    dm_meta[1,:] = ["Parameter", "Value"]
    dm_meta[2,:] = ["Termination Status", string(termination_status(m))]
    dm_meta[3,:] = ["Objective Value", objective_value(m)]
    dm_meta[4,:] = ["Solve Time", solve_time(m)]

    # --- NEW: Storage Summary Matrix ---
    st_techs = sets[:Tech_st]
    st_header = ["Year"]
    for t in st_techs 
        push!(st_header, "$(t)_Charged_MWh")
        push!(st_header, "$(t)_Discharged_MWh")
    end
    dm_storage = Matrix{Any}(undef, length(Y)+1, length(st_header))
    dm_storage[1,:] .= st_header
    for (i, y) in enumerate(Y)
        row = Any[y]
        for t in st_techs
            if P_ch !== nothing && P_dis !== nothing
                ch_sum = sum(value(P_ch[t,h,y]) for h in sets[:Hours])
                dis_sum = sum(value(P_dis[t,h,y]) for h in sets[:Hours])
                push!(row, ch_sum)
                push!(row, dis_sum)
            else
                push!(row, 0.0)
                push!(row, 0.0)
            end
        end
        dm_storage[i+1,:] .= row
    end

    # --- NEW: Fuel Consumption Matrix ---
    fuels = sets[:Fuels]
    f_header = ["Year"; fuels]
    dm_fuel = Matrix{Any}(undef, length(Y)+1, length(f_header))
    dm_fuel[1,:] .= f_header
    for (i,y) in enumerate(Y)
        row = Any[y]
        for f in fuels
            val = 0.0
            # F_sum is extracted earlier. We access it directly.
            # We use a try-catch block to handle different container types (Dense vs Dict) safely.
            try
                if F_sum isa Dict
                    if haskey(F_sum, (f,y))
                         val = value(F_sum[f,y])
                    end
                else 
                    # For JuMP DenseAxisArray, we access directly. 
                    # If index is missing, it will throw error, caught by catch.
                    val = value(F_sum[f,y])
                end
            catch
                val = 0.0
            end
            push!(row, val)
        end
        dm_fuel[i+1,:] .= row
    end

    # -------------------------
    # Costs summary table
    # -------------------------
    dm_costs_summary = Matrix{Any}(undef, length(Y)+2, 5) 
    dm_costs_summary[1, :] = ["Year", "Investment", "O&M fix", "O&M variable", "Decommissioning"]
    for (i, year) in enumerate(Y)
        dm_costs_summary[i+1, 1] = year
        dm_costs_summary[i+1, 2] = Inv_costs[year]
        dm_costs_summary[i+1, 3] = OM_fix_costs[year]
        dm_costs_summary[i+1, 4] = OM_var_costs[year]
        dm_costs_summary[i+1, 5] = Dec_costs[year]
    end
    dm_costs_summary[end, :] = ["Total", sum(dm_costs_summary[2:end-1, 2]), sum(dm_costs_summary[2:end-1, 3]), sum(dm_costs_summary[2:end-1, 4]), sum(dm_costs_summary[2:end-1, 5]) ]

    # -------------------------
    # Generation Summary Matrix
    # -------------------------
    gen_header = ["Year"; String.(sets[:Tech_el_prod]); "Grid"]
    dm_gen_summary = Matrix{Any}(undef, length(Y)+1, length(gen_header))
    dm_gen_summary[1, :] .= gen_header
    for (i, y) in enumerate(Y)
        row = Any[y]
        for t in sets[:Tech_el_prod]
            val = haskey(gen_data_dict, t) ? gen_data_dict[t][y] : 0.0
            push!(row, val)
        end
        push!(row, G_sum_vec[i])
        dm_gen_summary[i+1, :] .= row
    end

    # -------------------------
    # Emissions summary table
    # -------------------------
    dm_emi_summary = Matrix{Any}(undef, length(Y)+2, 8)
    dm_emi_summary[1, :] = ["Year", "Manufacturing", "Operation", "Decommissioning", "", "Scope 1", "Scope 2", "Scope 3"]
    for (i, year) in enumerate(Y)
        dm_emi_summary[i+1, 1] = year
        dm_emi_summary[i+1, 2] = Man_emissions[year]
        dm_emi_summary[i+1, 3] = Op_emissions[year]
        dm_emi_summary[i+1, 4] = Dec_emissions[year]
        dm_emi_summary[i+1, 5] = ""
        dm_emi_summary[i+1, 6] = Scope_emissions[1,year]
        dm_emi_summary[i+1, 7] = Scope_emissions[2,year]
        dm_emi_summary[i+1, 8] = Scope_emissions[3,year]
    end
    dm_emi_summary[end, :] = ["Total", sum(dm_emi_summary[2:end-1,2]), sum(dm_emi_summary[2:end-1,3]), sum(dm_emi_summary[2:end-1,4]), "", sum(dm_emi_summary[2:end-1,6]), sum(dm_emi_summary[2:end-1,7]), sum(dm_emi_summary[2:end-1,8])]

    # ----------------------------------------------------------------------
    # Build Consumption Summary
    # ----------------------------------------------------------------------
    el_consumers = haskey(sets, :Tech_el_con) ? sets[:Tech_el_con] : []
    ht_consumers = haskey(sets, :Tech_ht_con) ? sets[:Tech_ht_con] : []
    P_c_var = haskey(vars, :P_c) ? vars[:P_c] : nothing
    Q_c_var = haskey(vars, :Q_c) ? vars[:Q_c] : nothing

    cons_header = ["Year"]
    for t in el_consumers push!(cons_header, "$(t)_Elec_Used_MWh") end
    for t in ht_consumers push!(cons_header, "$(t)_Steam_Used_MWh") end

    dm_consumption = Matrix{Any}(undef, length(Y)+1, length(cons_header))
    dm_consumption[1, :] .= cons_header

    for (i, y) in enumerate(Y)
        row = Any[y]
        for t in el_consumers
            val = (P_c_var !== nothing) ? sum(value(P_c_var[t, h, y]) for h in sets[:Hours]) : 0.0
            push!(row, val)
        end
        for t in ht_consumers
            val = (Q_c_var !== nothing) ? sum(value(Q_c_var[t, h, y]) for h in sets[:Hours]) : 0.0
            push!(row, val)
        end
        dm_consumption[i+1, :] .= row
    end

    # -------------------------
    # Export to Excel
    # -------------------------
    XLSX.openxlsx(excel_path, mode="w") do xf
        write_matrix!(XLSX.addsheet!(xf,"Metadata"), dm_meta) # NEW
        write_matrix!(XLSX.addsheet!(xf,"Capacity_Exp_Dec"), dm_capacity_all)
        write_matrix!(XLSX.addsheet!(xf,"Land_use"), dm_land)
        write_matrix!(XLSX.addsheet!(xf,"EoL_summary"), dm_eol_summary)
        write_matrix!(XLSX.addsheet!(xf,"LCOE_annual"), dm_LCOE)
        write_matrix!(XLSX.addsheet!(xf,"LCOE_breakdown"), dm_LCOE_breakdown)
        write_matrix!(XLSX.addsheet!(xf, "Costs_summary"), dm_costs_summary)
        write_matrix!(XLSX.addsheet!(xf, "Emissions_summary"), dm_emi_summary)
        write_matrix!(XLSX.addsheet!(xf, "Generation_Summary"), dm_gen_summary)
        write_matrix!(XLSX.addsheet!(xf, "Consumption_Summary"), dm_consumption)
        write_matrix!(XLSX.addsheet!(xf, "Water_Consumption"), dm_water)
        write_matrix!(XLSX.addsheet!(xf, "Storage_Summary"), dm_storage) # NEW
        write_matrix!(XLSX.addsheet!(xf, "Fuel_Consumption"), dm_fuel)   # NEW
    end
    println("✅ Excel export complete: $excel_path")

    # -------------------------
    # Plots 
    # -------------------------
    if plot
        function saveplot(fig, name)
            path = joinpath(savepath, name)
            savefig(path, bbox_inches="tight")
            close(fig)
            println("  → saved: $(basename(path))")
        end
 
        # Costs Plot
        years = Y
        inv = [Inv_costs[y] for y in years]
        om_fix  = [OM_fix_costs[y] for y in years]
        om_var  = [OM_var_costs[y] for y in years]
        dec = [Dec_costs[y] for y in years]
        
        fig, ax = subplots(figsize=(6,4), dpi=300)
        ax.bar(years, inv, label="Investment", color="steelblue")
        ax.bar(years, om_fix, bottom=inv, label="O&M Fixed", color="seagreen")
        ax.bar(years, om_var, bottom=inv.+om_fix, label="O&M Variable", color="goldenrod")
        ax.bar(years, dec, bottom=inv.+om_fix.+om_var, label="Decommission", color="indianred")
        ax.set_xlabel("Year", fontsize=10)
        ax.set_ylabel("Cost (M)", fontsize=10)
        ax.set_title("Annualized Costs", fontsize=10)
        ax.legend(fontsize=8)
        tight_layout()
        saveplot(fig, "Costs_annualized.png")

        # LCOE Plot
        Tech_LCOE = dm_LCOE[1, 2:end]
        Years_LCOE = dm_LCOE[2:end, 1]
        LCOE_values = dm_LCOE[2:end, 2:end]

        fig, ax = subplots(figsize=(6,4), dpi=300)
        for (j,t) in enumerate(Tech_LCOE)
            yvals = LCOE_values[:, j]
            if sum(yvals) > 0
                ax.plot(Years_LCOE, yvals, label=string(t))
            end
        end
        ax.set_xlabel("Year", fontsize=10)
        ax.set_ylabel("LCOE (USD/kWh)", fontsize=10)
        ax.set_title("LCOE per Technology", fontsize=11)
        ax.legend(fontsize=8)
        tight_layout()
        saveplot(fig, "LCOE_line.png")

        # Generation Mix Plot
        fig, ax = subplots(figsize=(7,5), dpi=300)
        el_techs = sets[:Tech_el_prod] 
        years_list = Y
        bottom_val = zeros(length(years_list))
        
        for t in el_techs
            if haskey(gen_data_dict, t)
                gen_vals = [gen_data_dict[t][y] for y in years_list]
                if sum(gen_vals) > 1.0
                    ax.bar(years_list, gen_vals, bottom=bottom_val, label=String(t))
                    bottom_val .+= gen_vals
                end
            end
        end
        if sum(G_sum_vec) > 1.0
            ax.bar(years_list, G_sum_vec, bottom=bottom_val, label="Grid", color="gray", hatch="//", alpha=0.7)
        end
        ax.set_xlabel("Year", fontsize=10)
        ax.set_ylabel("Generation (MWh)", fontsize=10)
        ax.set_title("Total Electricity Supply Mix", fontsize=11)
        ax.legend(loc="upper left", bbox_to_anchor=(1, 1), fontsize=8)
        tight_layout()
        saveplot(fig, "Generation_Mix.png")

        println("✅ All plots saved in: $savepath")
    end
end

# # ==============================================================================

# using JuMP, XLSX
# using PyPlot

# function export_results(m::Model, vars, data; 
#                         filename::String = "Results_all.xlsx",
#                         plot::Bool = true,
#                         savepath::String = pwd())

#     # --- Ensure save directory exists ---
#     isdir(savepath) || mkpath(savepath)
#     excel_path = joinpath(savepath, filename)

#     # --- Extract basic sets from data ---
#     sets = data.sets
#     TD = data.TD
#     Y = sets[:Years]  # We will use length(Y) instead of n_years
#     Tech_all = sets[:Tech_all]
#     Tech_rw  = sets[:Tech_rw]
#     Fuels    = get(sets, :Fuels, String[])
    
#     # -------------------------
#     # Helper Functions
#     # -------------------------
#     function write_matrix!(sheet, mat, start_row=1, start_col=1)
#         for i in 1:size(mat,1)
#             for j in 1:size(mat,2)
#                 sheet[start_row + i - 1, start_col + j - 1] = mat[i,j]
#             end
#         end
#     end

#     function build_tech_matrix(var_values, Tech, Years)
#         mat = Matrix{Any}(undef, length(Years)+1, length(Tech)+1)
#         mat[1,:] .= ["Year"; Tech]
#         for (i,y) in enumerate(Years)
#             mat[i+1,1] = y
#             for (j,t) in enumerate(Tech)
#                 mat[i+1,j+1] = var_values[t,y]
#             end
#         end
#         return mat
#     end

#     function build_lcoe_matrix(TD, Exp, Cap, gen_data, C_f, F_sum, sets, Years, CRF)
#         rows = Vector{Vector{Any}}()
#         push!(rows, ["Year"; String.(sets[:Tech_all])]) 
#         Tech = String.(sets[:Tech_all])
#         for y in Years
#             row = Any[y]
#             for t in Tech
#                 inv = value(sum( TD[t].C_In * Exp[t,a] * CRF[t] *( (a <= y && y <= a + TD[t].Li - 1) ? 1.0 : 0.0 ) for a in sets[:Years]))
#                 fixom = value(TD[t].C_OM * Cap[t,y])
#                 fuel = (t == "NU") ? sum(value(C_f[f,y] * F_sum[f,y]) for f in sets[:Fuels]) : 0.0
#                 dec = value(TD[t].C_Dec * Cap[t,y] * CRF[t])
#                 el_prod = haskey(gen_data, t) ? gen_data[t][y] : 0.0
#                 lcoe_y = el_prod > 0 ? (inv + fixom + fuel + dec)/el_prod : 0.0
#                 push!(row, lcoe_y)
#             end
#             push!(rows, row)
#         end
#         mat = Matrix{Any}(undef, length(rows), length(rows[1]))
#         for (i,row) in enumerate(rows)
#             mat[i,:] .= row
#         end
#         return mat
#     end

#     function build_cost_breakdown_matrix(TD, Exp, Cap, gen_data, G_sum, C_f, F_sum, sets, Years, CRF)
#         Tech = String.(sets[:Tech_all])
#         header = ["Year"]
#         for t in Tech
#             push!(header, "$t Inv_cost")
#             push!(header, "$t FixOM_cost")
#             push!(header, "$t Fuel_cost")
#             push!(header, "$t Dec_cost")
#             push!(header, "$t Generation_MWh")
#         end
#         push!(header, "Grid_Energy_MWh")
#         mat = Matrix{Any}(undef, length(Years) + 1, length(header))
#         mat[1, :] .= header
#         for (i, y) in enumerate(Years)
#             row = Any[y]
#             for t in Tech
#                 inv = value(sum(TD[t].C_In * Exp[t,a] * CRF[t] * ((a <= y && y <= a + TD[t].Li - 1) ? 1.0 : 0.0) for a in sets[:Years]))
#                 fixom = value(TD[t].C_OM * Cap[t,y])
#                 fuel = (t == "NU") ? sum(value(C_f[f,y] * F_sum[f,y]) for f in sets[:Fuels]) : 0.0
#                 dec = value(TD[t].C_Dec * Cap[t,y] * CRF[t])
#                 gen = haskey(gen_data, t) ? gen_data[t][y] : 0.0
#                 append!(row, [inv, fixom, fuel, dec, gen])
#             end
#             push!(row, G_sum[i])
#             mat[i + 1, :] .= row
#         end
#         return mat
#     end

#     function build_capexpdec_matrix(cap, exp, dec, Tech, Years)
#         header = ["Year"]
#         for t in Tech
#             push!(header, "$t Cap")
#             push!(header, "$t Exp")
#             push!(header, "$t Dec")
#         end
#         mat = Matrix{Any}(undef, length(Years)+1, length(header))
#         mat[1,:] .= header
#         for (i,y) in enumerate(Years)
#             row = Any[y]
#             for t in Tech
#                 push!(row, cap[t,y])
#                 push!(row, exp[t,y])
#                 push!(row, dec[t,y])
#             end
#             mat[i+1,:] .= row
#         end
#         return mat
#     end

#     function build_eol_matrix(Mat_EoL, C_eol, E_eol, sets, Years)
#         rows = Vector{Vector{Any}}()
#         push!(rows, ["Technology", "Option", "Material", "Cost", "Emissions"])
#         for t in sets[:Tech_all]
#             if !haskey(sets[:EoL_options], t) continue end
#             for opt in sets[:EoL_options][t]
#                 total_mat = sum(value(Mat_EoL[t,opt,y]) for y in Years)
#                 cost = C_eol[(t,opt)] * total_mat / 1e3
#                 emi  = E_eol[(t,opt)] * total_mat / 1e6
#                 push!(rows, Any[t,opt,total_mat,cost,emi])
#             end
#         end
#         mat = Matrix{Any}(undef, length(rows), length(rows[1]))
#         for (i,row) in enumerate(rows)
#             mat[i,:] .= row
#         end
#         return mat
#     end

#     # --------------------------------------------------------------------------
#     # Calculate Water Consumption
#     # --------------------------------------------------------------------------
#     function calculate_water_consumption(m, vars, data)
#         sets = data.sets
#         TD = data.TD
#         years = sets[:Years]
#         gscalar = data.gscalar
#         W_g = data.W_g  #

#         # --- NEW: Extract Profiles ---
#         PUE_Profile = data.PUE_Profile
#         WUE_Profile = data.WUE_Profile
        
#         # --- NEW: Conditional Logic for Parameters ---
#         DC_Active = get(gscalar, "DC_Active", 0.0)
#         DC_Cap    = get(gscalar, "DC_Cap", 0.0)
        
#         # Check flag: 0 = Air, 1 = Water
#         DC_Cooling_Type = get(gscalar, "DC_Cooling_Type", 0)

#         # if DC_Cooling_Type == 1
#         #     # Water Cooled
#         #     PUE    = get(gscalar, "PUE_Water", 1.0)
#         #     DC_WUE = get(gscalar, "WUE_Water", 0.0)
#         #     println("   -> Results: Calculating Water Consumption using WATER-COOLED parameters.")
#         # else
#         #     # Air Cooled (Default)
#         #     PUE    = get(gscalar, "PUE_Air", 1.0)
#         #     DC_WUE = get(gscalar, "WUE_Air", 0.0)
#         #     println("   -> Results: Calculating Water Consumption using AIR-COOLED parameters.")
#         # end 
        
#         water_header = ["Year", "DC_Direct", "Cogen_Direct", "Boiler_Direct", "Nuclear_Direct", "Chillers_Direct", "Grid_Indirect", "Total_Consumption"]
#         dm_water = Matrix{Any}(undef, length(years)+1, length(water_header))
#         dm_water[1,:] .= water_header
        
#         Pg_sum_local = haskey(vars, :Pg_sum) ? vars[:Pg_sum] : m[:Pg_sum]
#         Q_p = vars[:Q_p]
#         K_p = vars[:K_p]
#         G_sum_local = m[:G_sum]
        
#         for (i, y) in enumerate(years)
#             # 1. DC Direct (Updated for Profiles)
#             # Summation of hourly consumption: Load[h] * WUE[h]
#             # Load[h] = Active * Profile[h] * Cap * PUE[h]
#             w_dc = 0.0
#             for h in sets[:Hours]
#                 load_h = DC_Active * data.DC_Prof[(h,y)] * DC_Cap * PUE_Profile[h]
#                 w_dc += load_h * WUE_Profile[h]
#             end

#             # 2. Cogen Direct
#             w_cogen = 0.0
#             if haskey(TD, "cg_el")
#                 gen = value(Pg_sum_local["cg_el", y])
#                 w_cogen = gen * TD["cg_el"].W_Cons
#             end

#             # 3. Boiler Direct
#             w_boiler = 0.0
#             if haskey(TD, "ng") 
#                 heat_gen = sum(value(Q_p["ng", h, y]) for h in sets[:Hours])
#                 w_boiler = heat_gen * TD["ng"].W_Cons
#             end

#             # 4. Nuclear Direct
#             w_nuc = 0.0
#             if haskey(TD, "nu")
#                 gen = value(Pg_sum_local["nu", y])
#                 w_nuc = gen * TD["nu"].W_Cons
#             end

#             # 5. Chillers Direct
#             w_chillers = 0.0
#             if haskey(TD, "ec")
#                 cool_gen = sum(value(K_p["ec", h, y]) for h in sets[:Hours])
#                 w_chillers += cool_gen * TD["ec"].W_Cons
#             end
#             if haskey(TD, "sc")
#                 cool_gen = sum(value(K_p["sc", h, y]) for h in sets[:Hours])
#                 w_chillers += cool_gen * TD["sc"].W_Cons
#             end

#             # 6. Grid Indirect
#             grid_mwh = value(G_sum_local[y])
#             # grid_factor = haskey(TD, "grid") ? TD["grid"].W_Cons : 467.0
#             # w_grid = grid_mwh * grid_factor

#             # total = w_dc + w_cogen + w_boiler + w_nuc + w_chillers + w_grid
#             # dm_water[i+1, :] .= [y, w_dc, w_cogen, w_boiler, w_nuc, w_chillers, w_grid, total]
#             # NEW CODE:
#             grid_factor = get(W_g, y, 0.0) # Gets yearly value from "Annual_emi" sheet
            
#             w_grid = grid_mwh * grid_factor

#             total = w_dc + w_cogen + w_boiler + w_nuc + w_chillers + w_grid
#             dm_water[i+1, :] .= [y, w_dc, w_cogen, w_boiler, w_nuc, w_chillers, w_grid, total]
#         end
#         return dm_water
#     end

#     # -------------------------
#     # Extract variables
#     # -------------------------
    
#     Cap, Exp, Dec = vars[:Cap], vars[:Exp], vars[:Dec]
#     Co_inv, Co_fixom, Co_varom, Co_eol = vars[:Co_inv], vars[:Co_fixom], vars[:Co_varom], vars[:Co_eol]
#     Em_man, Em_op, Em_eol, Em_scope = vars[:Em_man], vars[:Em_op], vars[:Em_eol], vars[:Em_scope]
#     Mat_EoL, Land = vars[:Mat_EoL], vars[:L]
    
#     F_sum  = haskey(m, :F_sum) ? m[:F_sum] : Dict()

#     cap_tech = value.(Cap[Tech_all,Y])
#     cap_exp  = value.(Exp[Tech_all,Y])
#     cap_decom = value.(Dec[Tech_all,Y])
#     Land_vals = value.(Land[Tech_rw,Y])

#     Inv_costs = value.(Co_inv[Y])
#     OM_fix_costs = value.(Co_fixom[Y])
#     OM_var_costs = value.(Co_varom[Y])
#     Dec_costs = value.(Co_eol[Y])

#     Inv_costs_year = [value(m[:InvYearCost][y]) for y in Y]
#     Dec_costs_year = [value(m[:EoLYearCost][y]) for y in Y]

#     gen_data_dict = Dict{String, Dict{Int, Float64}}()
#     for t in sets[:Tech_el_prod]
#         gen_data_dict[t] = Dict{Int, Float64}()
#         for y in Y
#             gen_data_dict[t][y] = value(m[:Pg_sum][t,y])
#         end
#     end
#     G_sum_vec = [value(m[:G_sum][y]) for y in Y]

#     Man_emissions = value.(Em_man[Y])
#     Op_emissions  = value.(Em_op[Y])
#     Dec_emissions = value.(Em_eol[Y])
#     Scope_emissions = value.(Em_scope[1:3,Y])

#     # -------------------------
#     # Build Excel matrices
#     # -------------------------
#     dm_cap  = build_tech_matrix(cap_tech, Tech_all, Y)
#     dm_exp  = build_tech_matrix(cap_exp, Tech_all, Y)
#     dm_dec  = build_tech_matrix(cap_decom, Tech_all, Y)
#     dm_land = build_tech_matrix(Land_vals, Tech_rw, Y)

#     dm_capacity_all = build_capexpdec_matrix(cap_tech, cap_exp, cap_decom, Tech_all, Y)
#     dm_eol_summary = build_eol_matrix(Mat_EoL, data.C_eol, data.E_eol, data.sets, Y)
#     CRF = Utils.compute_crf(TD, data.gscalar["r"])
    
#     dm_LCOE = build_lcoe_matrix(TD, Exp, Cap, gen_data_dict, data.C_f, F_sum, data.sets, Y, CRF)
#     dm_LCOE_breakdown = build_cost_breakdown_matrix(TD, Exp, Cap, gen_data_dict, G_sum_vec, data.C_f, F_sum, data.sets, Y, CRF)
    
#     dm_water = calculate_water_consumption(m, vars, data)

#     # -------------------------
#     # Costs summary table
#     # -------------------------
#     # FIXED: Replaced n_years with length(Y)
#     dm_costs_summary = Matrix{Any}(undef, length(Y)+2, 10) 
#     dm_costs_summary[1, :] = ["Year", "Investment", "O&M fix", "O&M variable", "Decommissioning", "", "Inv_full", "O&M fix", "O&M variable", "Dec_full"]
#     for (i, year) in enumerate(Y)
#         dm_costs_summary[i+1, 1] = year
#         dm_costs_summary[i+1, 2] = Inv_costs[year]
#         dm_costs_summary[i+1, 3] = OM_fix_costs[year]
#         dm_costs_summary[i+1, 4] = OM_var_costs[year]
#         dm_costs_summary[i+1, 5] = Dec_costs[year]
#         dm_costs_summary[i+1, 6] = ""
#         dm_costs_summary[i+1, 7] = Inv_costs_year[i]
#         dm_costs_summary[i+1, 8] = OM_fix_costs[year] 
#         dm_costs_summary[i+1, 9] = OM_var_costs[year]
#         dm_costs_summary[i+1, 10] = Dec_costs_year[i]
#     end
#     dm_costs_summary[end, :] = ["Total", sum(dm_costs_summary[2:end-1, 2]), sum(dm_costs_summary[2:end-1, 3]), sum(dm_costs_summary[2:end-1, 4]), sum(dm_costs_summary[2:end-1, 5]), "", sum(dm_costs_summary[2:end-1, 7]), sum(dm_costs_summary[2:end-1, 8]), sum(dm_costs_summary[2:end-1, 9]), sum(dm_costs_summary[2:end-1, 10])]

#     # -------------------------
#     # Generation Summary Matrix
#     # -------------------------
#     gen_header = ["Year"; String.(sets[:Tech_el_prod]); "Grid"]
#     dm_gen_summary = Matrix{Any}(undef, length(Y)+1, length(gen_header))
#     dm_gen_summary[1, :] .= gen_header

#     for (i, y) in enumerate(Y)
#         row = Any[y]
#         for t in sets[:Tech_el_prod]
#             val = haskey(gen_data_dict, t) ? gen_data_dict[t][y] : 0.0
#             push!(row, val)
#         end
#         push!(row, G_sum_vec[i])
#         dm_gen_summary[i+1, :] .= row
#     end

#     # -------------------------
#     # Emissions summary table
#     # -------------------------
#     # FIXED: Replaced n_years with length(Y)
#     dm_emi_summary = Matrix{Any}(undef, length(Y)+2, 8)
#     dm_emi_summary[1, :] = ["Year", "Manufacturing", "Operation", "Decommissioning", "", "Scope 1", "Scope 2", "Scope 3"]
#     for (i, year) in enumerate(Y)
#         dm_emi_summary[i+1, 1] = year
#         dm_emi_summary[i+1, 2] = Man_emissions[year]
#         dm_emi_summary[i+1, 3] = Op_emissions[year]
#         dm_emi_summary[i+1, 4] = Dec_emissions[year]
#         dm_emi_summary[i+1, 5] = ""
#         dm_emi_summary[i+1, 6] = Scope_emissions[1,year]
#         dm_emi_summary[i+1, 7] = Scope_emissions[2,year]
#         dm_emi_summary[i+1, 8] = Scope_emissions[3,year]
#     end
#     dm_emi_summary[end, :] = ["Total", sum(dm_emi_summary[2:end-1,2]), sum(dm_emi_summary[2:end-1,3]), sum(dm_emi_summary[2:end-1,4]), "", sum(dm_emi_summary[2:end-1,6]), sum(dm_emi_summary[2:end-1,7]), sum(dm_emi_summary[2:end-1,8])]

#     # ----------------------------------------------------------------------
#     # Build Consumption Summary
#     # ----------------------------------------------------------------------
#     el_consumers = haskey(sets, :Tech_el_con) ? sets[:Tech_el_con] : []
#     ht_consumers = haskey(sets, :Tech_ht_con) ? sets[:Tech_ht_con] : []
    
#     P_c_var = haskey(vars, :P_c) ? vars[:P_c] : nothing
#     Q_c_var = haskey(vars, :Q_c) ? vars[:Q_c] : nothing

#     cons_header = ["Year"]
#     for t in el_consumers push!(cons_header, "$(t)_Elec_Used_MWh") end
#     for t in ht_consumers push!(cons_header, "$(t)_Steam_Used_MWh") end

#     dm_consumption = Matrix{Any}(undef, length(Y)+1, length(cons_header))
#     dm_consumption[1, :] .= cons_header

#     for (i, y) in enumerate(Y)
#         row = Any[y]
#         for t in el_consumers
#             val = (P_c_var !== nothing) ? sum(value(P_c_var[t, h, y]) for h in sets[:Hours]) : 0.0
#             push!(row, val)
#         end
#         for t in ht_consumers
#             val = (Q_c_var !== nothing) ? sum(value(Q_c_var[t, h, y]) for h in sets[:Hours]) : 0.0
#             push!(row, val)
#         end
#         dm_consumption[i+1, :] .= row
#     end

#     # -------------------------
#     # Export to Excel
#     # -------------------------
#     XLSX.openxlsx(excel_path, mode="w") do xf
#         write_matrix!(XLSX.addsheet!(xf,"Capacity_Exp_Dec"), dm_capacity_all)
#         write_matrix!(XLSX.addsheet!(xf,"Land_use"), dm_land)
#         write_matrix!(XLSX.addsheet!(xf,"EoL_summary"), dm_eol_summary)
#         write_matrix!(XLSX.addsheet!(xf,"LCOE_annual"), dm_LCOE)
#         write_matrix!(XLSX.addsheet!(xf,"LCOE_breakdown"), dm_LCOE_breakdown)
#         write_matrix!(XLSX.addsheet!(xf, "Costs_summary"), dm_costs_summary)
#         write_matrix!(XLSX.addsheet!(xf, "Emissions_summary"), dm_emi_summary)
#         write_matrix!(XLSX.addsheet!(xf, "Generation_Summary"), dm_gen_summary)
#         write_matrix!(XLSX.addsheet!(xf, "Consumption_Summary"), dm_consumption)
#         write_matrix!(XLSX.addsheet!(xf, "Water_Consumption"), dm_water)
#     end
#     println("✅ Excel export complete: $excel_path")

#     # -------------------------
#     # Plots
#     # -------------------------
#     if plot
#         function saveplot(fig, name)
#             path = joinpath(savepath, name)
#             savefig(path, bbox_inches="tight")
#             close(fig)
#             println("  → saved: $(basename(path))")
#         end
 
#         # Costs Plot
#         years = Y
#         inv = [Inv_costs[y] for y in years]
#         om_fix  = [OM_fix_costs[y] for y in years]
#         om_var  = [OM_var_costs[y] for y in years]
#         dec = [Dec_costs[y] for y in years]
        
#         fig, ax = subplots(figsize=(6,4), dpi=300)
#         ax.bar(years, inv, label="Investment", color="steelblue")
#         ax.bar(years, om_fix, bottom=inv, label="O&M Fixed", color="seagreen")
#         ax.bar(years, om_var, bottom=inv.+om_fix, label="O&M Variable", color="goldenrod")
#         ax.bar(years, dec, bottom=inv.+om_fix.+om_var, label="Decommission", color="indianred")
#         ax.set_xlabel("Year", fontsize=10)
#         ax.set_ylabel("Cost (M)", fontsize=10)
#         ax.set_title("Annualized Costs", fontsize=10)
#         ax.legend(fontsize=8)
#         tight_layout()
#         saveplot(fig, "Costs_annualized.png")

#         # LCOE Plot
#         Tech_LCOE = dm_LCOE[1, 2:end]
#         Years_LCOE = dm_LCOE[2:end, 1]
#         LCOE_values = dm_LCOE[2:end, 2:end]

#         fig, ax = subplots(figsize=(6,4), dpi=300)
#         for (j,t) in enumerate(Tech_LCOE)
#             yvals = LCOE_values[:, j]
#             if sum(yvals) > 0
#                 ax.plot(Years_LCOE, yvals, label=string(t))
#             end
#         end
#         ax.set_xlabel("Year", fontsize=10)
#         ax.set_ylabel("LCOE (USD/kWh)", fontsize=10)
#         ax.set_title("LCOE per Technology", fontsize=11)
#         ax.legend(fontsize=8)
#         tight_layout()
#         saveplot(fig, "LCOE_line.png")

#         # Generation Mix Plot
#         fig, ax = subplots(figsize=(7,5), dpi=300)
#         el_techs = sets[:Tech_el_prod] 
#         years_list = Y
#         bottom_val = zeros(length(years_list))
        
#         for t in el_techs
#             if haskey(gen_data_dict, t)
#                 gen_vals = [gen_data_dict[t][y] for y in years_list]
#                 if sum(gen_vals) > 1.0
#                     ax.bar(years_list, gen_vals, bottom=bottom_val, label=String(t))
#                     bottom_val .+= gen_vals
#                 end
#             end
#         end
#         if sum(G_sum_vec) > 1.0
#             ax.bar(years_list, G_sum_vec, bottom=bottom_val, label="Grid", color="gray", hatch="//", alpha=0.7)
#         end
#         ax.set_xlabel("Year", fontsize=10)
#         ax.set_ylabel("Generation (MWh)", fontsize=10)
#         ax.set_title("Total Electricity Supply Mix", fontsize=11)
#         ax.legend(loc="upper left", bbox_to_anchor=(1, 1), fontsize=8)
#         tight_layout()
#         saveplot(fig, "Generation_Mix.png")

#         println("✅ All plots saved in: $savepath")
#     end
# end


