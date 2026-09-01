using PVlib
using Dates
using TimeZones

const coordinates = [
    (lat=32.2, lon=-111.0, name="Tucson", elevation=700, tz=TimeZone("America/Denver")),
    (lat=35.1, lon=-106.6, name="Albuquerque", elevation=1500, tz=TimeZone("America/Denver")),
    (lat=37.8, lon=-122.4, name="San Francisco", elevation=10, tz=TimeZone("America/Los_Angeles")),
    (lat=52.5, lon=13.4, name="Berlin", elevation=34, tz=TimeZone("Europe/Berlin")),
]

const module_filename = "sam-library-sandia-modules-2015-6-30.csv"
const inverter_filename = "sam-library-cec-inverters-2019-03-05.csv"

const module_name = "Canadian Solar CS5P-220M [ 2009]"
const inverter_name = "ABB: MICRO-0.25-I-OUTD-US-208 [208V]"

println(stderr, "Loading module and inverter data...")

const pv_module = read_solar_module(module_name, module_filename)
const pv_inverter = read_solar_inverter(inverter_name, inverter_filename)

println(stderr, "Loading weather data...")

const weather_by_location = [
    get_meteorological_data_pvgis(
        c.lat,
        c.lon,
        Date(1900, 1, 1),
        Date(2026, 1, 1),
        c.tz,
        false,
    )
    for c in coordinates
]

function run_simulation()
    ac_power_totals = Float64[]

    for (c, weather_data) in zip(coordinates, weather_by_location)
        surface_tilt = c.lat
        surface_azimuth = 180
        albedo = 0.25

        solar_position = get_solar_position(
            c.lat,
            c.lon,
            c.elevation,
            weather_data,
        )

        total_irradiance = get_total_irradiance(
            surface_tilt,
            surface_azimuth,
            weather_data,
            solar_position,
            albedo,
        )

        cell_temp = sapm_cell_temperature(
            total_irradiance,
            weather_data,
        )

        effective_irradiance = sapm_effective_irradiance(
            total_irradiance,
            pv_module,
            solar_position,
            surface_tilt,
            surface_azimuth,
            c.elevation,
        )

        dc_components = sapm_dc_components(
            pv_module,
            effective_irradiance,
            cell_temp,
        )

        ac_power = sandia_ac_power(
            pv_inverter,
            dc_components,
        )

        ac_power_total = sum(getfield.(ac_power, :ac_power))
        push!(ac_power_totals, ac_power_total)
    end

    return ac_power_totals
end

println(stderr, "Running first solve...")
GC.gc()

first_results = nothing
t_first = @elapsed begin
    first_results = run_simulation()
end

println(stderr, "Running second solve...")
GC.gc()

second_results = nothing
t_second = @elapsed begin
    second_results = run_simulation()
end

println(stderr, "Second solve results:")
for (c, total) in zip(coordinates, second_results)
    println(stderr, "$(c.name): $total Wh")
end

# Final stdout line parsed by the shell script.
println("$(t_first),$(t_second)")