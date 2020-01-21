# We need to provide very specific deprecation methods to avoid ambiguous to the
# Dict(:data => data) fallback.

# 2-arg form
@deprecate(
    checkpoint(name::String, data::Dict{String}; tags...),
    checkpoint(name, Dict(Symbol(k)=>v for (k,v) in pairs(data)); tags...)
)

@deprecate(
    checkpoint(handler::Handler, data::Dict{String}; tags...),
    checkpoint(handler, Dict(Symbol(k)=>v for (k,v) in pairs(data)); tags...)
)

@deprecate(
    checkpoint(session::Session, data::Dict{String}; tags...),
    checkpoint(session, Dict(Symbol(k)=>v for (k,v) in pairs(data)); tags...)
)

# 3-arg form
@deprecate(
    checkpoint(handler::Handler, name::String, data::Dict{String}; tags...),
    checkpoint(handler, name, Dict(Symbol(k)=>v for (k,v) in pairs(data)); tags...)
)
