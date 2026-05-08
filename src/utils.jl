module Utils

using XLSX, DataFrames

export TechData, load_parameters, compute_crf

# --- Struct technology data ---
struct TechData
    C_In::Float64
    C_OM::Float64
    C_Dec::Float64
    Li::Int
    Li_p::Int
    Li_c::Int
    Cap_i::Float64
    Cap_max::Float64
    E_lca::Float64
    E_man::Float64
    We::Float64
    CF::Float64
    W_Cons::Float64 # Water Consumption ONLY (MMGal/MWh) <--- UPDATED UNIT
end

struct ModelData
    gscalar::Dict
    tscalar::Dict
    fscalar::Dict
    TD::Dict
    sets::Dict
    HL::Any
    WP::Any
    El::Any
    Ht:: Any
    Co:: Any
    DC_Prof::Any # new addition for data center load profile
    C_f::Dict
    C_g::Dict
    C_eol::Dict
    Rev_eol::Dict 
    E_g::Dict
    E_eol::Dict
    W_g::Dict
    PUE_Profile::Dict{Int, Float64} # Hourly PUE
    WUE_Profile::Dict{Int, Float64} # Hourly WUE (MMGal/MWh) <--- UPDATED UNIT
end


# --- Load parameters from Excel ---
function load_parameters(path::String)
    xf = XLSX.readxlsx(path)

    # --- Sets ---
    df_sets = DataFrame(XLSX.gettable(xf["Sets"]))
    sets = Dict{Symbol, Any}()
    for row in eachrow(df_sets)
        key = Symbol(strip(string(row[:set])))
        element = strip(string(row[:element]))
        if haskey(sets, key)
            push!(sets[key], element)
        else
            sets[key] = [element]
        end
    end
    sets[:Tech_all] = union(sets[:Tech_st_el], sets[:Tech_st_ht], sets[:Tech_rw], sets[:Tech_el_prod], sets[:Tech_ht_prod], sets[:Tech_co_prod])
    sets[:Tech_st] = union(sets[:Tech_st_el], sets[:Tech_st_ht])

    # --- Read scalars ---
    df_scalars = DataFrame(XLSX.gettable(xf["Model_Data"]))
    gscalar = Dict{String, Float64}()
    tscalar = Dict{String, Dict{String, Float64}}()
    fscalar = Dict{String, Dict{String, Float64}}()

    for row in eachrow(df_scalars)
        param = String(row.Parameter)
        tech  = String(row.Technology)
        val   = Float64(row.Value)

        if tech == "model"
            gscalar[param] = val
        elseif tech in sets[:Fuels]
            if !haskey(fscalar, param)
                fscalar[param] = Dict{String, Float64}()
            end
            fscalar[param][tech] = val
        else
            if !haskey(tscalar, param)
                tscalar[param] = Dict{String, Float64}()
            end
            tscalar[param][tech] = val
        end
    end

    hours = Int(gscalar["hours"])
    y_i   = Int(gscalar["y_i"])
    y_f   = Int(gscalar["y_f"])
    num_sets = Dict(
        :Hours  => collect(1:hours),
        :Years  => collect(y_i:y_f),
        :Y1 => collect((y_i+1):y_f)
    )
    sets = merge(sets, num_sets)

    # --- EoL options ---
    df_eol = DataFrame(XLSX.gettable(xf["EoL_Data"]))

    # Dictionary for parameters: (tech, option) => (C_eol, Rev_eol, E_eol)
    C_eol = Dict{Tuple{String,String}, Float64}()
    Rev_eol = Dict{Tuple{String,String}, Float64}()
    E_eol = Dict{Tuple{String,String}, Float64}()

    # Dictionary for options: tech => [options]
    EoL_options = Dict{String, Vector{String}}()

    for row in eachrow(df_eol)
        tech = String(row.Technology)
        opt  = String(row.Option)

        C_eol[(tech,opt)] = row.C_eol
        Rev_eol[(tech,opt)] = row.Rev_eol
        E_eol[(tech,opt)] = row.E_eol

        if haskey(EoL_options, tech)
            push!(EoL_options[tech], opt)
        else
            EoL_options[tech] = [opt]
        end
    end

    sets[:EoL_options] = EoL_options

    # --- Technology data ---
    df_tech = DataFrame(XLSX.gettable(xf["Tech_Data"]))
    TD = Dict(row[:Technology] => TechData(
        row[:C_In], row[:C_OM], row[:C_Dec], row[:Li],
        row[:Li_p], row[:Li_c], row[:Cap_i], row[:Cap_max],
        row[:E_lca], row[:E_man], row[:We], row[:CF], row[:W_Cons] * 1e-6 # <--- SCALED HERE
    ) for row in eachrow(df_tech))

    # --- Load HL, WP, El ---
    function load_preprocess_data(sheetname)
        df = DataFrame(XLSX.gettable(xf[sheetname]))
        result = Dict{Tuple{Int, Int}, Float64}()
        for row in eachrow(df)
            h = row[:hours]
            for col in names(df)[2:end]
                y = parse(Int, string(col))
                result[(h,y)] = row[col]
            end
        end
        return result
    end
    HL = load_preprocess_data("HL")
    WP = load_preprocess_data("WP")
    El = load_preprocess_data("Electricity")
    DC_Prof = load_preprocess_data("DC_Profile_MV") # new addition for data center load profile
    Ht = load_preprocess_data("Heating")
    Co = load_preprocess_data("Cooling")

    # --- Variable O&M costs ---
    df_costs = DataFrame(XLSX.gettable(xf["Annual_costs"]))
    C_f = Dict{Tuple{String, Int}, Float64}()
    C_g = Dict{Int, Float64}()
    for row in eachrow(df_costs)
        y = row.Year
        for f in sets[:Fuels]
            C_f[(f,y)] = row[Symbol(f*"_cost")]
        end
        C_g[y] = row[:grid_cost]
    end

    # --- Emissions & Grid Water ---
    df_emi = DataFrame(XLSX.gettable(xf["Annual_emi"]))
    E_g = Dict{Int, Float64}()
    W_g = Dict{Int, Float64}() # <--- NEW: Initialize dictionary

    for row in eachrow(df_emi)
        y = row.Year
        E_g[y] = row[:grid_emi]
        W_g[y] = row[:W_con_grid] * 1e-6 # <--- SCALED HERE
    end

    # ==========================================================================
    # NEW: Load HOURLY PUE/WUE from "WUE_PUE_hourly" Sheet
    # ==========================================================================
    # Sheet Headers expected: 
    # [Hour_Sequence, PUE_Case1, WUE_Case1, PUE_Case6, WUE_Case6]
    
    df_hourly_pue = DataFrame(XLSX.gettable(xf["WUE_PUE_hourly"]))
    
    # 0 = Case 1 (Air), 1 = Case 6 (Water)
    dc_type = get(gscalar, "DC_Cooling_Type", 0.0)

    PUE_Profile = Dict{Int, Float64}()
    WUE_Profile = Dict{Int, Float64}()

    # Conversion: 1 L/kWh -> 264.172 Gallons/MWh
    unit_conv = 264.172 * 1e-6 # <--- SCALED HERE

    # We assume the sheet has exactly 8760 rows (or covers all hours needed)
    for row in eachrow(df_hourly_pue)
        h = Int(row[:Hour_Sequence])

        if dc_type == 1
            # Water Cooled (Case 6) -> Cols D & E
            p_val = Float64(row[:PUE_Case6])
            w_val_raw = Float64(row[:WUE_Case6])
        else
            # Air Cooled (Case 1) -> Cols B & C
            p_val = Float64(row[:PUE_Case1])
            w_val_raw = Float64(row[:WUE_Case1])
        end

        PUE_Profile[h] = p_val
        WUE_Profile[h] = w_val_raw * unit_conv
    end

    data = ModelData(gscalar, tscalar, fscalar, TD, sets, HL, WP, El, Ht, Co, 
                     DC_Prof, C_f, C_g, C_eol, Rev_eol, E_g, E_eol, W_g, 
                     PUE_Profile, WUE_Profile)

    return data
end

function compute_crf(TD::Dict{String,TechData}, r::Float64)
    # ... [Keep existing function] ...
    CRF = Dict{String,Float64}()
    for (t, td) in TD
        n = td.Li
        if n <= 0
            CRF[t] = 0.0
        elseif r == 0
            CRF[t] = 1/n
        else
            CRF[t] = r*(1+r)^n / ((1+r)^n - 1)
        end
    end
    return CRF
end

end #module