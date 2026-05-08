# ==============================================================================
# Plot From Excel Script
# Run this anytime to regenerate plots without optimizing!
# ==============================================================================

using XLSX, DataFrames, PyPlot

# 1. Define the file to load
# (Use @__DIR__ to look in the same folder as this script)
excel_file = joinpath(@__DIR__, "Results_DC_Baseline_Water.xlsx")

# Check if file exists
if !isfile(excel_file)
    error("❌ File not found: $excel_file. \nPlease run the optimization 'run_analysis.jl' first to generate the Excel file.")
end

println("--- Loading Results from Excel ---")
xf = XLSX.readxlsx(excel_file)

# ------------------------------------------------------------------------------
# PLOT: Water Consumption (2 Subplots: Direct vs Indirect)
# ------------------------------------------------------------------------------
println("... Plotting Water Consumption (Split View)")

if "Water_Consumption" in XLSX.sheetnames(xf)
    df_water = DataFrame(XLSX.gettable(xf["Water_Consumption"]))
    years = df_water[!, :Year]

    # Create 1 row, 2 columns of subplots
    fig, (ax1, ax2) = subplots(1, 2, figsize=(12, 5), dpi=300)

    # --- SUBPLOT 1: DIRECT WATER (On-site) ---
    cats_direct = ["DC_Direct", "Cogen_Direct", "Boiler_Direct", "Nuclear_Direct", "Chillers_Direct"]
    labels_direct = ["Data Center", "Cogen", "Boiler", "Nuclear", "Chillers"]
    colors_direct = ["navy", "brown", "indianred", "orange", "cyan"]

    bottom_val1 = zeros(length(years))

    for (i, cat) in enumerate(cats_direct)
        # Convert to Million Gallons
        vals = Float64.(df_water[!, cat]) ./ 1_000_000 
        
        if sum(vals) > 0.01
            ax1.bar(years, vals, bottom=bottom_val1, label=labels_direct[i], color=colors_direct[i], edgecolor="white", linewidth=0.5)
            bottom_val1 .+= vals
        end
    end

    ax1.set_xlabel("Year")
    ax1.set_ylabel("Water Consumption (Million Gallons)")
    ax1.set_title("Direct (On-site) Water Consumption")
    ax1.legend(loc="upper left", fontsize=8)
    ax1.grid(axis="y", linestyle="--", alpha=0.5)

    # --- SUBPLOT 2: INDIRECT WATER (Grid) ---
    cats_indirect = ["Grid_Indirect"]
    labels_indirect = ["Grid (Off-site)"]
    colors_indirect = ["gray"]

    bottom_val2 = zeros(length(years))

    for (i, cat) in enumerate(cats_indirect)
        vals = Float64.(df_water[!, cat]) ./ 1_000_000 
        
        if sum(vals) > 0.01
            # Using hatch pattern to distinguish indirect
            ax2.bar(years, vals, bottom=bottom_val2, label=labels_indirect[i], color=colors_indirect[i], hatch="//", edgecolor="black", linewidth=0.5, alpha=0.7)
            bottom_val2 .+= vals
        end
    end

    ax2.set_xlabel("Year")
    ax2.set_ylabel("Water Consumption (Million Gallons)")
    ax2.set_title("Indirect (Grid) Water Consumption")
    ax2.legend(loc="upper right", fontsize=8)
    ax2.grid(axis="y", linestyle="--", alpha=0.5)

    # Adjust layout to prevent overlap
    tight_layout()
    
    # Save Plot
    save_path = joinpath(@__DIR__, "Water_Consumption_Split.png")
    savefig(save_path)
    close(fig)
    println("✅ Saved plot: $save_path")
else
    println("⚠️ 'Water_Consumption' sheet not found in Excel.")
end

# ------------------------------------------------------------------------------
# PLOT 1: Electricity Generation Mix (Stacked Bar)
# ------------------------------------------------------------------------------
println("... Plotting Generation Mix")

# Read the "Generation_Summary" sheet we just created
df_gen = DataFrame(XLSX.gettable(xf["Generation_Summary"]))

# Prepare Data
years = df_gen[!, :Year]
# Get all column names except "Year"
tech_cols = names(df_gen)[2:end] 

# Initialize Plot
fig, ax = subplots(figsize=(8, 5), dpi=300)
bottom_val = zeros(length(years))

# Define colors (optional, for aesthetics)
colors = Dict(
    "Solar" => "gold", "pv" => "gold", "PV" => "gold",
    "Wind" => "skyblue", "wt" => "skyblue",
    "Nuclear" => "orange", "nu" => "orange",
    "Grid" => "gray", "grid" => "gray",
    "Gas" => "brown", "ng" => "brown",
    "Batteries" => "purple"
)

# Loop through columns (PV, Wind, Grid...) and stack them
for col_name in tech_cols
    # Get the data column (convert to Float for plotting)
    vals = Float64.(df_gen[!, col_name])
    
    # Only plot if it has significant generation
    if sum(vals) > 1.0
        # Determine color
        clr = get(colors, col_name, nothing) # default auto color if not found
        hatch_pattern = (col_name == "Grid") ? "//" : nothing
        
        ax.bar(years, vals, bottom=bottom_val, label=col_name, color=clr, hatch=hatch_pattern, edgecolor="white", linewidth=0.5)
        
        # Stack up
        bottom_val .+= vals
    end
end

ax.set_xlabel("Year")
ax.set_ylabel("Electricity (MWh)")
ax.set_title("Electricity Generation Mix (From Excel)", fontsize=12)
ax.legend(loc="upper left", bbox_to_anchor=(1, 1), fontsize=9)
tight_layout()

savefig(joinpath(@__DIR__, "Plot_Generation_Mix_Excel.png"))
close(fig)

# ------------------------------------------------------------------------------
# PLOT 2: Costs (Optional Example)
# ------------------------------------------------------------------------------
println("... Plotting Costs")

df_costs = DataFrame(XLSX.gettable(xf["Costs_summary"]))
# Filter out the "Total" row (last row usually)
df_costs = df_costs[1:end-1, :] 

years = df_costs[!, :Year]
inv = Float64.(df_costs[!, "Investment"])
om  = Float64.(df_costs[!, "O&M fix"]) + Float64.(df_costs[!, "O&M variable"])
dec = Float64.(df_costs[!, "Decommissioning"])

fig2, ax2 = subplots(figsize=(8, 5), dpi=300)
ax2.bar(years, inv, label="Investment", color="steelblue")
ax2.bar(years, om, bottom=inv, label="O&M", color="seagreen")
ax2.bar(years, dec, bottom=inv.+om, label="Decommissioning", color="indianred")

ax2.set_title("Annual Costs (From Excel)")
ax2.legend()
tight_layout()
savefig(joinpath(@__DIR__, "Plot_Costs_Excel.png"))
close(fig2)

println("✅ All plots generated from Excel successfully!")
