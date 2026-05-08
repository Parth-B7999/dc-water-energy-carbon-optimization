# module Variables

using JuMP
import ..Utils: ModelData, TechData

export add_variables!

function add_variables!(m::Model, data::ModelData)

    sets = data.sets
    TD   = data.TD

    vars = Dict{Symbol, Any}()

    #Capacity
    vars[:Cap]   = @variable(m, [t in sets[:Tech_all], y in sets[:Years]], lower_bound=0, upper_bound=TD[t].Cap_max, base_name="Cap")
    vars[:Exp]   = @variable(m, [t in sets[:Tech_all], y in sets[:Years]], lower_bound=0, base_name="Exp")
    vars[:Dec]   = @variable(m, [t in sets[:Tech_all], y in sets[:Years]], lower_bound=0, base_name="Dec")
    vars[:n] = @variable(m, [t in sets[:Tech_el_prod], y in sets[:Years]], lower_bound=0, base_name="n", integer = true)
    
    #Energy
    vars[:P_p]   = @variable(m, [t in sets[:Tech_el_prod], h in sets[:Hours], y in sets[:Years]], lower_bound=0, base_name="P_p")
    vars[:P_c]   = @variable(m, [t in sets[:Tech_el_con], h in sets[:Hours], y in sets[:Years]], lower_bound=0, base_name="P_c")
    vars[:P_g]   = @variable(m, [h in sets[:Hours], y in sets[:Years]], lower_bound=0, base_name="P_g")
    vars[:Q_p]   = @variable(m, [t in sets[:Tech_ht_prod], h in sets[:Hours], y in sets[:Years]], lower_bound=0, base_name="Q_p")
    vars[:Q_c]   = @variable(m, [t in sets[:Tech_ht_con], h in sets[:Hours], y in sets[:Years]], lower_bound=0, base_name="Q_c")
    vars[:K_p]   = @variable(m, [t in sets[:Tech_co_prod], h in sets[:Hours], y in sets[:Years]], lower_bound=0, base_name="K_t")

    #Storage
    vars[:P_ch]  = @variable(m, [t in sets[:Tech_st], h in sets[:Hours], y in sets[:Years]], lower_bound=0, base_name="P_ch")
    vars[:P_dis] = @variable(m, [t in sets[:Tech_st], h in sets[:Hours], y in sets[:Years]], lower_bound=0, base_name="P_dis")
    vars[:P_le]  = @variable(m, [t in sets[:Tech_st], h in sets[:Hours], y in sets[:Years]], lower_bound=0, base_name="P_le")

    #Costs
    vars[:Co_inv] = @variable(m, [y in sets[:Years]], lower_bound=0, base_name="Co_inv")
    vars[:Co_fixom] = @variable(m, [y in sets[:Years]], lower_bound=0, base_name="Co_fixom")
    vars[:Co_varom] = @variable(m, [y in sets[:Years]], lower_bound=0, base_name="Co_varom")
    vars[:Co_eol] = @variable(m, [y in sets[:Years]], lower_bound=0, base_name="Co_eol")

    #Emmisions
    vars[:Em_man] = @variable(m, [y in sets[:Years]], base_name="Em_man")
    vars[:Em_op] = @variable(m, [y in sets[:Years]], base_name="Em_op")
    vars[:Em_eol] = @variable(m, [y in sets[:Years]], base_name="Em_eol")
    vars[:Em_scope] = @variable(m, [s in 1:3, y in sets[:Years]], base_name="Em_scope")

    #Land
    vars[:L] = @variable(m, [t in sets[:Tech_rw], y in sets[:Years]], lower_bound=0, base_name="L")
    vars[:L_tot] = @variable(m, [y in sets[:Years]], lower_bound=0, base_name="L_tot")

    #Fuel
    vars[:F_c] = @variable(m, [f in sets[:BFuels], t in sets[:Tech_ht_prod], h in sets[:Hours], y in sets[:Years]], lower_bound=0, base_name="F_c")

    # --- Material flow ---
    vars[:Mat_EoL] = @variable(m, [t in sets[:Tech_all], o in sets[:EoL_options][t], y in sets[:Years]], lower_bound=0, base_name = "Mat_EoL")
    vars[:Mat_tot] = @variable(m, [t in sets[:Tech_all], y in sets[:Years]], lower_bound=0, base_name="Mat_tot")
  
    return vars
end

# end # module

