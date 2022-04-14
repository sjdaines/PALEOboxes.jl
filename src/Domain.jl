import Infiltrator
"""
    Domain
    
A model region containing Variables and Reactions that act on them.
"""
Base.@kwdef mutable struct Domain <: AbstractDomain
    name::String
    ID::Int
    data_dims::Vector{NamedDimension}       = Vector{NamedDimension}()
    parameters::Dict{String, Any}
    grid::Union{Nothing, AbstractMesh}      = nothing
    
    reactions::Vector{AbstractReaction}     = Vector{AbstractReaction}()    
    variables::Dict{String, VariableDomain} = Dict{String, VariableDomain}()
end

"""
    set_data_dimension!(domain::Domain, dim::NamedDimension; allow_exists=false)

Define a Domain data dimension.

Variable data dimensions are then defined as Tuples of `dim.name`s using the `:data_dims` Attribute.
"""
function set_data_dimension!(domain::Domain, dim::NamedDimension; allow_exists=false)

    @info "set_data_dimension!:  setting Domain '$(domain.name)' data dimension '$dim'"

    idx = findfirst(d -> d.name==dim.name, domain.data_dims)

    allow_exists || isnothing(idx) || 
        error("set_data_dimensions! Domain '$(domain.name)' already has dimension "*
            " name $(dim.name)")

    if isnothing(idx)
        push!(domain.data_dims, dim)
    else
        domain.data_dims[idx] = dim
    end

    return nothing
end

has_data_dimension(domain::Domain, dimname::AbstractString) =
    !isnothing(findfirst(d -> d.name==dimname, domain.data_dims))

function get_data_dimension(domain::Domain, dimname::AbstractString)
    idx = findfirst(d -> d.name==dimname, domain.data_dims)
    !isnothing(idx) ||
            error("Domain $(domain.name) has no dimension='$dimname' (available dimensions: $(domain.data_dims)")
    return domain.data_dims[idx]
end

function get_length(domain::Domain)
    if isnothing(domain.grid)
        return 1 # scalar Domain
    else
        return domain.grid.ncells::Int
    end
end

"Get number of Domain variables"
function get_num_variables(domain::Domain)
    return length(domain.variables)
end

"""
    get_variables(domain; hostdep=nothing, vfunction=VF_Undefined) -> Vector{VariableDomain}

Get domain variables, optionally filtering for subsets based on `hostdep` and `:vfunction` attribute
"""
function get_variables(
    domain::Domain; 
    hostdep::Union{Bool,Nothing}=nothing,
    vfunction::VariableFunction=VF_Undefined,
)
    # define function to filter variables
    filter(var) = (
        (isnothing(hostdep) || (host_dependent(var) == hostdep))
        && (vfunction == VF_Undefined || get_attribute(var, :vfunction, VF_Undefined) == vfunction)
    )

    return get_variables(domain, filter)
end

"""
    get_variables(domain, filter) -> Vector{VariableDomain}

Get subset of domain variables where `filter(var) == true`.
"""
function get_variables(domain::Domain, filter)
    return VariableDomain[var for (name, var) in domain.variables if filter(var)]
end

"Get variable by name"
function get_variable(domain::Domain, name::AbstractString)
    return get(domain.variables, name, nothing)
end


"""
    get_host_variables(domain, vfunction; [match_deriv_suffix=""] [, operatorID=0] [, exclude_var_nameroots=[]] [, verbose=false]) 
        -> (host_vars, host_deriv_vars)

Get state Variables with [`VariableFunction`](@ref) `vfunction`, and optionally 
corresponding time derivative with [`VariableFunction`](@ref) `VF_Deriv` and name matching
hostvarname*<`match_deriv_suffix``>.

Optionally filter by `operatorID`, omit Variables with name matching `exclude_var_nameroots`.
"""
function get_host_variables(
    domain::Domain, vfunction::VariableFunction;
    match_deriv_suffix="",
    operatorID=0,
    exclude_var_nameroots=[],
)

    # return a function that filters Variables that match requested VariableFunction, 
    # are host dependent, have matching operatorID, and optionally have name match_name
    function filter_func(vf::VariableFunction, match_name)
        function filt_func(var)
            var_opID = get_attribute(var, :operatorID, missing)
            !ismissing(var_opID) ||
                error("Variable $(fullname(var)) has no operatorID attribute")
            return (
                host_dependent(var)
                && (get_attribute(var, :vfunction, VF_Undefined)==vf)
                && (operatorID == 0 || operatorID in var_opID) 
                && !(var.name in exclude_var_nameroots)
                && (isempty(match_name) || match_name == var.name)
            )
        end
        return filt_func
    end

    host_vars = get_variables(domain, filter_func(vfunction, ""))
    
    if !isempty(match_deriv_suffix)
        host_deriv_vars = VariableDomain[get_variables(domain, filter_func(VF_Deriv, var.name*match_deriv_suffix))[] for var in host_vars]
    else
        host_deriv_vars = nothing
    end
    
    return (host_vars, host_deriv_vars) 
end

"""
    get_reactions(domain, filter) -> Vector
    
    Get Reactions where `filter(react) == true`.
"""
function get_reactions(domain::Domain, filter)   
    return AbstractReaction[react for react in domain.reactions if filter(react)]
end

"""
    get_reaction(domain, reactname) -> Reaction or nothing
    
Get a reaction by name.
"""
function get_reaction(domain::Domain, reactname::AbstractString)
    reactions = get_reactions(domain, r -> r.name == reactname)
    if isempty(reactions)
        return nothing
    else
        return first(reactions)        
    end
end

"""
    allocate_variables!(domain, modeldata; [hostdep=false] [, eltypemap::Dict{String, DataType}])

Allocate memory for Domain Variables. 

If `hostdep=false`, only internal Variables are allocated, allowing host-dependent Variables
(usually state Variables and derivatives + any external dependencies) to be set to views on host-managed arrays.

Element type of allocated Arrays is determined by `eltype(modeldata)` (the usual case, allowing use of AD types), 
or Variable `:datatype` attribute if present (allowing Variables to ignore AD types).
`:datatype` may be either a Julia `DataType` (eg Float64), or a string to be looked up in `eltypemap`.
"""
function allocate_variables!(
    domain::Domain, modeldata::AbstractModelData; 
    hostdep::Union{Bool,Nothing}=nothing,
    eltypemap=Dict{String, DataType}()
)
    vars = get_variables(domain, hostdep=hostdep)
   
    @info "Domain $(rpad(domain.name,20)) data dimensions $(rpad(domain.data_dims,20)) "*
        "allocating $(rpad(length(vars),4)) internal variables (hostdep=$(hostdep))"  
 
    for v in vars
        data_dims = Tuple(
            get_data_dimension(domain, dimname) 
            for dimname in get_attribute(v, :data_dims)
        )
    
        # eltype usually is eltype(modeldata), but can be overriden by :datatype attribute 
        # (can be used by a Reaction to define a fixed type eg Float64 for a constant Property)
        mdeltype = get_attribute(v, :datatype, eltype(modeldata))
        if mdeltype isa AbstractString
            mdeltype = get(eltypemap, mdeltype, Float64)
        end
        
        thread_safe = false
        if get_attribute(v, :atomic, false) && modeldata.threadsafe
            @info "  $(fullname(v)) allocating Atomic data"
            thread_safe = true
        end

        field_data = get_attribute(v, :field_data)
        space = get_attribute(v, :space)

        v_field = allocate_field(
            field_data, data_dims, mdeltype, space, domain.grid,
            thread_safe=thread_safe, allocatenans=modeldata.allocatenans
        )        
        
        set_field!(v, modeldata, v_field)
      
    end

    return nothing
end

"""
    get_unallocated_variables(domain, modeldata) -> Vector{VariableDomain}

Return any unallocated variables (host-dependent variables which have no data pointer set)
"""
function get_unallocated_variables(
    domain::Domain, modeldata::AbstractModelData
)
    allvars = get_variables(domain)
    unallocated_variables = [v for v in allvars if !is_allocated(v, modeldata)]
    return unallocated_variables
end

"Check all variable pointers set"
function check_ready(
    domain::Domain, modeldata::AbstractModelData;
    throw_on_error=true
)
    vars_unallocated = get_unallocated_variables(domain, modeldata)
    num_unallocated = length(vars_unallocated)
    if num_unallocated == 0
        return true
    else
        @error "Domain \"$(domain.name)\" unallocated variables:" 
        for var in vars_unallocated
            linknames = [fullname(vl) for vl in get_all_links(var)]
            @error "   \"$(var.name)\" linked by: $linknames"
        end
        if throw_on_error            
            error("Domain $(domain.name)  check_ready failed num_unallocated=", num_unallocated)
        end
        return false
    end
end

"Check configuration"
function check_configuration(domain::Domain, model::Model)
    configok = true
    for react in domain.reactions
        if !check_configuration(react, model)
            configok = false
        end
    end

    return configok
end


###################################
# creation from _cfg.yaml
##################################


function create_domain_from_config(
    name::AbstractString, domainID::Integer, conf_domain::Dict{Any,Any}, external_parameters::Dict{String, Any}
)
 
    for k in keys(conf_domain)
        if !(k in ("data_dims", "reactions"))
            error("Domain $(name) configuration error invalid key '$k'")
        end
    end

    domain = Domain(name=name, ID=domainID, parameters=external_parameters)

    # optional data_dims key
    conf_dimensions = get(conf_domain, "data_dims", Dict{Any,Any}())    
    for (name, len) in conf_dimensions
        set_data_dimension!(domain, NamedDimension(name, len, []))
    end

    # reactions 
    conf_reactions = get(conf_domain, "reactions", Dict{Any,Any}())
    
    if !isnothing(conf_reactions)
        for (reactname, conf_reactionraw) in conf_reactions
            !isnothing(conf_reactionraw) || 
                error("config error: reaction $(domain.name).reactions.$(reactname) has no configuration")
            conf_reaction = copy(conf_reactionraw)
            reactenabledval = pop!(conf_reaction, "enabled", true)
            reactenabled = externalvalue(reactenabledval, external_parameters)
            reactenabled isa Bool || 
                error("config error: reaction $(domain.name).reactions.$(reactname) "*
                    "invalid 'enabled' key $reactenabled (must be a Bool)")
            
            if reactenabled
                classname = pop!(conf_reaction, "class", missing)
                !ismissing(classname) ||
                    error("config error: reaction $(domain.name).reactions.$(reactname) missing 'class' key")
                # create the reaction instance and add it to our list
                @info "  creating reaction $(domain.name).reactions.$reactname classname $classname"
                push!(
                    domain.reactions, 
                    create_reaction_from_config(
                        domain, reactname, conf_reaction, classname, domain.parameters
                    )
                )
            else
                @info "not creating reaction $(domain.name).reactions.$(reactname) (enabled=false)"
            end
        end
    else
        @warn "create_domain_from_config Domain '$(domain.name)' empty 'reactions:' key in .yaml file"
    end

    return domain
end

function _next_variable_ID(domain::Domain)
    return get_num_variables(domain::Domain) + 1
end

#################################
# Variable linking
#################################

function _link_print(domain::Domain, reaction::AbstractReaction, variable::VariableReaction,
                    linkvar_domain::Domain, linkvar_name::AbstractString, dolog)
    @debug "Link requested $(domain.name).reactions.$(reaction.name)  $(variable.localname) --> $(combine_link_name(linkvar_domain.name, variable.linkreq_subdomain, linkvar_name))"
    return nothing
end

function _link_print_not_linked(domain::Domain, reaction::AbstractReaction, variable::VariableReaction,
    linkvar_domain::Domain, linkvar_name::AbstractString, dolog)
    if isnothing(variable.linkvar)
        linkreq_fullname = combine_link_name(variable.linkreq_domain, variable.linkreq_subdomain, linkvar_name)
        rname = domain.name*"."*reaction.name
        if variable.link_optional
            @info "    optional $(rpad(rname, 40)) $(rpad(variable.localname,20)) -| $linkreq_fullname"
        else
            @warn "    required $(rpad(rname, 40)) $(rpad(variable.localname,20)) -| $linkreq_fullname"
        end
    end
    return nothing
end

"Create Domain variables for VariableReaction Property and Target, and create property/target link"
function _link_create(domain::Domain, reaction::AbstractReaction, variable::VariableReaction,
                    linkvar_domain::Domain, linkvar_name::AbstractString, dolog)
   # generic method does nothing for VT_ReactDependency, VT_ReactContributor
   return nothing
end

function _link_create(domain::Domain, reaction::AbstractReaction,
                      variable::VariableReaction{VT_ReactProperty},
                      linkvar_domain::Domain, linkvar_name::AbstractString, dolog)
    dolog && @debug "Creating Property $(reaction.base.domain.name).reactions.$(reaction.name).$(variable.name) "*
        "--> $(linkvar_domain.name).$(linkvar_name)"

    if haskey(linkvar_domain.variables, linkvar_name)
        newvar = linkvar_domain.variables[linkvar_name]
        # Either a single var_property link,
        # or two, one for a setup ReactionMethod and one for a do ReactionMethod
        if (length(newvar.var_property) == 1) && 
            # check one is method setup and the other method do (no other combinations allowed)
            ((is_method_do(newvar.var_property[1].method) && is_method_setup(variable.method))
             || (is_method_setup(newvar.var_property[1].method) && is_method_do(variable.method)))
            @debug "Adding additional method to Property $(fullname(newvar)) "*
                "from $(nameof(typeof(reaction))) $(fullname(reaction)) (now have setup and do methods)"
        else
            io = IOBuffer()
            show_links(io, linkvar_domain.variables[linkvar_name])
            error("Duplicate variable name: Linking VariableReactProperty $(fullname(variable))\n",
                "    Variable $(linkvar_domain.name).$(linkvar_name) exists ! with links:\n",
                String(take!(io)))
        end
    else
        newvar =  create_VariableDomPropDep(linkvar_domain, linkvar_name, variable)
    end
    push!(newvar.var_property, variable)
    variable.linkvar = newvar
    return nothing
end

function _link_create(domain::Domain, reaction::AbstractReaction,
                      variable::VariableReaction{VT_ReactTarget},
                      linkvar_domain::Domain, linkvar_name::AbstractString, dolog)
    dolog && @debug "Creating Target $(reaction.base.domain.name).reactions.$(reaction.name).$(variable.name) "*
        "--> $(linkvar_domain.name).$(linkvar_name)"

    if haskey(linkvar_domain.variables, linkvar_name)
        io = IOBuffer()
        show_links(io, linkvar_domain.variables[linkvar_name])
        error("Duplicate variable name: Linking VariableReactTarget $(fullname(variable))\n",
              "    Variable $(linkvar_domain.name).$(linkvar_name) exists ! with links:\n",
              String(take!(io)))
    end
    newvar =  create_VariableDomContribTarget(linkvar_domain, linkvar_name, variable)
    newvar.var_target = variable
    variable.linkvar = newvar
    return nothing
end

"Create any additional (host-dependent) Domain variables for any non-optional VariableReaction Contrib"
function _link_create_contrib(domain::Domain, reaction::AbstractReaction, variable::VariableReaction,
                    linkvar_domain::Domain, linkvar_name::AbstractString, dolog)
    # generic method does nothing for VT_ReactProperty, VT_ReactTarget, VT_ReactDependency
    return nothing
end

function _link_create_contrib(domain::Domain, reaction::AbstractReaction,
                    variable::VariableReaction{VT_ReactContributor},
                    linkvar_domain::Domain, linkvar_name::AbstractString, dolog)
    if (!haskey(linkvar_domain.variables, linkvar_name)
        && !variable.link_optional)

        dolog && @debug "Creating host Target for Contributor $(reaction.base.domain.name).reactions.$(reaction.name).$(variable.name) "*
            "--> $(linkvar_domain.name).$(linkvar_name)"

        linkvar =  create_VariableDomContribTarget(linkvar_domain, linkvar_name, variable)
        # don't create link - that happens later in _link_link
    end
    return nothing
end

"Create any additional (host-dependent) Domain variables for any non-optional VariableReaction Dependency"
function _link_create_dep(domain::Domain, reaction::AbstractReaction, variable::VariableReaction,
                    linkvar_domain::Domain, linkvar_name::AbstractString, dolog)
    # generic method does nothing for VT_ReactProperty, VT_ReactTarget, VT_ReactContributor
    return nothing
end

function _link_create_dep(domain::Domain, reaction::AbstractReaction,
                    variable::VariableReaction{VT_ReactDependency},
                    linkvar_domain::Domain, linkvar_name::AbstractString, dolog)
    if (!haskey(linkvar_domain.variables, linkvar_name)
        && !variable.link_optional)

        dolog && @debug "Creating host Property for Dependency $(reaction.base.domain.name).reactions.$(reaction.name).$(variable.name) "*
            "--> $(linkvar_domain.name).$(linkvar_name)"

        linkvar =  create_VariableDomPropDep(linkvar_domain,linkvar_name, variable)
        # don't create link - that happens later in _link_link
    end
    return nothing
end

"Link VariableReaction Dependency and Contrib to Domain variables"
function _link_link(domain::Domain, reaction::AbstractReaction, variable::VariableReaction,
                    linkvar_domain::Domain, linkvar_name::AbstractString, dolog)
    # generic method does nothing for VT_ReactProperty, VT_ReactTarget
    return nothing
end


function _link_link(domain::Domain, reaction::AbstractReaction,
                    variable::VariableReaction{VT_ReactDependency},
                    linkvar_domain::Domain, linkvar_name::AbstractString, dolog)
    
    linkvar = get(linkvar_domain.variables, linkvar_name, nothing)
    if !isnothing(linkvar)
        dolog && @debug "Linking Dependency $(fullname(variable)) --> $(linkvar_domain.name).$(linkvar_name)"        
        add_dependency(linkvar, variable)    
    else
        if variable.link_optional
            dolog && @debug "No Property for optional Dependency $(fullname(variable))"
        else
            @warn "Programming error - no property for dependency $(fullname(variable)) with link_optional=false"
        end
    end
   
    variable.linkvar = linkvar
    return nothing
end

function _link_link(domain::Domain, reaction::AbstractReaction,
                    variable::VariableReaction{VT_ReactContributor},
                    linkvar_domain::Domain, linkvar_name::AbstractString, dolog)
    
    linkvar = get(linkvar_domain.variables, linkvar_name, nothing)
    if !isnothing(linkvar)
        dolog && @debug "Linking Contributor $(fullname(variable)) --> $(linkvar_domain.name).$(linkvar_name)"
        add_contributor(linkvar, variable)
    else
        if variable.link_optional
            dolog && @debug "No target for optional Contributor $(fullname(variable))"
        else
            @warn "Programming error - no target for contributor $(fullname(variable)) with link_optional=false"
        end
    end
  
    variable.linkvar = linkvar
    return nothing
end


"Visit all Reaction Variables and call supplied function oper (one of _link_print, _link_create, etc"
function _link_variables!(domain::Domain, model::Model, oper, dolog)
    # create a datastructure
    for react in domain.reactions       
        for var in get_variables(react)

            if isempty(var.linkreq_domain)
                linkvar_domain = domain
            else
                linkvar_domain = get_domain(model, var.linkreq_domain)
                !isnothing(linkvar_domain) || 
                    error("linking VariableReaction $(fullname(var)): linkreq_domain='$(var.linkreq_domain)' not found")
            end
            
            linkvar_name = sub_variablereaction_linkreq_name(var.linkreq_name, react.name*"/")
            oper(domain, react, var, linkvar_domain, linkvar_name, dolog)
        end
    end
    return nothing
end

function _link_clear!(domain::Domain)
    empty!(domain.variables)
    return nothing
end


#############################
# Pretty printing
############################'

"compact form"
function Base.show(io::IO, domain::Domain)
    print(io, "Domain(name='", domain.name, "')")
end
"multiline form"
function Base.show(io::IO, ::MIME"text/plain", domain::Domain)
    println(io, "Domain")
    println(io, "  name='$(domain.name)'")
    println(io, "  ID=$(domain.ID)")
    println(io, "  data_dims=", domain.data_dims)
    println(io, "  grid=", isnothing(domain.grid) ? "<nothing>" : domain.grid)
    println(io, "  reactions:")
    for r in domain.reactions
        println(io, "    ", r)
    end
    println(io, "  variables (VariableDomPropDep):")
    for var in sort(get_variables(domain, v -> v isa VariableDomPropDep), by = v -> v.name)
        println(io, "    ", var)
    end
    println(io, "  variables (VariableDomContribTarget):")
    for var in sort(get_variables(domain, v -> v isa VariableDomContribTarget), by = v -> v.name)
        println(io, "    ", var)
    end
end

"""
    show_variables(domain::Domain; [attributes], [filter], showlinks=false, modeldata=nothing) -> DataFrame

Show table of Domain Variables. Optionally get variable links, data.

# Keywords:
- `attributes=[:units, :vfunction, :space, :field_data, :description]`: Variable attributes to show
- `showlinks=false`: true to show [`VariableReaction`](@ref)s that link to this Domain Variable.
- `modeldata=nothing`: set to also show Variable values.
- `filter=attrb->true`: function to filter by Variable attributes.
  Example: `filter=attrb->attrb[:vfunction]!=PB.VF_Undefined` to show state Variables and derivatives.
"""
function show_variables(
    domain::Domain; 
    attributes=[:units, :vfunction, :space, :field_data, :description],
    filter = attrb->true, 
    showlinks=false,
    modeldata=nothing
)
    
    vars = get_variables(domain, var->filter(var.attributes))

    df = DataFrames.DataFrame()
    df.name = [v.name for v in vars]
    for att in attributes
        DataFrames.insertcols!(df, att=>[get_attribute(v, att) for v in vars])
    end

    # functions to collect links
    get_property(v::VariableDomPropDep)             = 
        isempty(v.var_property) ? missing : [fullname(vp) for vp in v.var_property]
    get_property(v::VariableDomContribTarget)       = missing
    get_target(v::VariableDomPropDep)               = missing
    get_target(v::VariableDomContribTarget)         =
        isnothing(v.var_target) ? missing : fullname(v.var_target)
    get_contributors(v::VariableDomPropDep)         = missing
    get_contributors(v::VariableDomContribTarget)   =
        isempty(v.var_contributors) ? missing : [fullname(vc) for vc in v.var_contributors]
    get_dependencies(v)                             =
        isempty(v.var_dependencies) ? missing : [fullname(vd) for vd in v.var_dependencies]

    if showlinks
        df.property     = [get_property(v) for v in vars]
        df.dependencies = [get_dependencies(v) for v in vars]
        df.target       = [get_target(v) for v in vars]
        df.contributors = [get_contributors(v) for v in vars]  
    end

    if !isnothing(modeldata)
        df.data = [get_data(v, modeldata) for v in vars]
    end
    
    DataFrames.sort!(df, [:name])

    return df
end
