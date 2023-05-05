
################################
# Coordinates
#################################

"""
    FixedCoord(name::String, _, _) -> name

Deprecated:
    Used to be 'A fixed (state independent) coordinate'
    Now just passes through name of coordinate
"""
FixedCoord(name::String, _, _) = name
# mutable struct FixedCoord
#     name::String
#     values::Vector{Float64}
#     attributes::Dict{Symbol, Any}
# end






# function get_region(fc::FixedCoord, indices::AbstractVector)
#     return FixedCoord(fc.name, fc.values[indices], fc.attributes)
# end

# function get_region(fcv::Vector{FixedCoord}, indices::AbstractVector)
#     return [FixedCoord(fc.name, fc.values[indices], fc.attributes) for fc in fcv]
# end




#################################################
# Dimensions
#####################################################

"""
    NamedDimension

A named dimension, with optional preferred coordinates `coords`

PALEO convention is that where possible `coords` contains three elements, for cell
midpoints, lower edges, upper edges, in that order.
"""
mutable struct NamedDimension
    name::String
    size::Int64    
    coords::Vector{String} # may be empty
end

function Base.show(io::IO, nd::NamedDimension)
    print(io, "NamedDimension(name=", nd.name, ", size=", nd.size, ", coords=", nd.coords, ")")
    return nothing
end

#= "create from size only (no coords)"
function NamedDimension(name, size::Integer, coords=String[])
    return NamedDimension(
        name, 
        size, 
        String[],
    )
end

"create from coord mid-points"
function NamedDimension(name, coord::AbstractVector)
    return NamedDimension(
        name, 
        length(coord), 
        [
            FixedCoord(name, coord, Dict{Symbol, Any}()),
        ]
    )
end

"create from coord mid-points and edges"
function NamedDimension(name, coord::AbstractVector, coord_edges::AbstractVector)
    if coord[end] > coord[1]
        # ascending order
        coord_lower = coord_edges[1:end-1]
        coord_upper = coord_edges[2:end]
    else
        # descending order
        coord_lower = coord_edges[2:end]
        coord_upper = coord_edges[1:end-1]
    end
    return NamedDimension(
        name, 
        length(coord), 
        [
            FixedCoord(name, coord, Dict{Symbol, Any}()),
            FixedCoord(name*"_lower", coord_lower, Dict{Symbol, Any}()),
            FixedCoord(name*"_upper", coord_upper, Dict{Symbol, Any}()),
        ]
    )
end

function get_region(nd::NamedDimension, indices::AbstractVector)
    return NamedDimension(nd.name, length(indices), get_region(nd.coords, indices))
end


 =#


