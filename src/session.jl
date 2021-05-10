struct Session{H<:Union{Nothing, Handler}}
    name::String
    handler::H
    objects::DefaultDict
end

function Session(name::String)
     # Create our objects dictionary which defaults to returning
    # an empty JLSOFile
    handler = CHECKPOINTS[name]

    objects = DefaultDict{AbstractPath, JLSO.JLSOFile}() do
        JLSO.JLSOFile(Dict{Symbol, Vector{UInt8}}(); handler.settings...)
    end

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

"""
    commit!(session)

Write all staged JLSOFiles to the respective paths.
"""
function commit!(session::Session)
    # No-ops skip when handler is nothing
    session.handler === nothing && return nothing

    for (p, jlso) in session.objects
        commit!(session.handler, p, jlso)
    end
end

function checkpoint(session::Session, data::Dict{Symbol}; tags...)
    checkpoint_deprecation(tags...)
    with_checkpoint_tags(tags...) do
        # No-ops skip when handler is nothing
        session.handler === nothing && return nothing

        p = path(session.handler, session.name)
        jlso = session.objects[p]
        session.objects[p] = stage!(session.handler, jlso, data)
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
