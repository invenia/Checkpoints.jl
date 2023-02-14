struct Session{H<:Union{Nothing, AbstractHandler}}
    name::String
    handler::H
    objects::DefaultDict
end

function Session(name::String)
     # Create our objects dictionary which defaults to returning
    # an empty JLSOFile
    handler = CHECKPOINTS[name]
    objects = session_objects(handler)
    Session{typeof(handler)}(name, handler, objects)
end

Session(prefix::Union{Module, String}, name::String) = Session(join([prefix, name], "."))

function Session(f::Function, args...)
    session = Session(args...)
    f(session)
    commit!(session)
end

function Session(f::Function, names::Vector{String})
    sessions = Session.(names)
    f(sessions...)
    commit!.(sessions)
end

function Session(f::Function, prefix::Union{Module, String}, names::Vector{String})
    Session(f, map(n -> "$prefix.$n", names))
end

function session_objects(handler)
    return DefaultDict{AbstractString, Dict}() do
        Dict{Symbol, Any}()
    end
end

function session_objects(handler::JLSOHandler)
    return DefaultDict{AbstractPath, JLSO.JLSOFile}() do
        JLSO.JLSOFile(Dict{Symbol, Vector{UInt8}}(); handler.settings...)
    end
end

"""
    commit!(session)

Write all staged objects to the respective keys.
"""
function commit!(session::Session)
    # No-ops skip when handler is nothing
    session.handler === nothing && return nothing

    for (k, v) in session.objects
        commit!(session.handler, k, v)
    end
end

function checkpoint(session::Session, data::Dict{Symbol}; tags...)
    checkpoint_deprecation(tags...)
    with_checkpoint_tags(tags...) do
        handler = session.handler
        name = session.name
        K = keytype(session.objects)

        # No-ops skip when handler is nothing
        handler === nothing && return nothing

        # Our handler may not always be storing data in filepaths
        k = K <: AbstractPath ? path(handler, name) : getkey(handler, name)
        session.objects[k] = stage!(handler, session.objects[k], data)
    end
end

function checkpoint(s::Session, data::Pair...; tags...)
    checkpoint_deprecation(tags...)
    with_checkpoint_tags(tags...) do
        checkpoint(s, Dict(data...))
    end
end

function checkpoint(s::Session, data; tags...)
    checkpoint_deprecation(tags...)
    with_checkpoint_tags(tags...) do
        checkpoint(s, Dict(:data => data))
    end
end
