"""
    Checkpoints

A very minimal module for defining checkpoints or save location in large codebase with
the ability to configure how those checkpoints save data externally
(similar to how Memento.jl works for logging).
"""
module Checkpoints

using AWSS3
using Memento
using FilePathsBase
using FilePathsBase: /, join
using JLSO

using DataStructures: DefaultDict

export checkpoint

const LOGGER = getlogger(@__MODULE__)

__init__() = Memento.register(LOGGER)

include("handler.jl")

const CHECKPOINTS = Dict{String, Union{Nothing, Handler}}()
const TAGS = Dict{Symbol, Any}()

include("session.jl")

"""
    application_tags()

TODO: add docstring
"""
application_tags() = TAGS
application_tags(::Nothing) = empty!(TAGS)
function application_tags(tags::Pair...)
    for (k, v) in tags
        TAGS[k] = v
    end
end


"""
    available() -> Vector{String}

Returns a vector of all available (registered) checkpoints.
"""
available() = collect(keys(CHECKPOINTS))

"""
    checkpoint([prefix], name, data)
    checkpoint([prefix], name, data::Pair...; tags...)
    checkpoint([prefix], name, data::Dict; tags...)

Defines a data checkpoint with a specified `label` and values `data`.
By default checkpoints are no-ops and need to be explicitly configured.

    checkpoint(session, data; tags...)
    checkpoint(handler, name, data::Dict; tags...)

Alternatively, you can also checkpoint with to a session which stages the data to be
commited later by `commit!(session)`.
Explicitly calling checkpoint on a handler is generally not advised, but is an option.
"""
function checkpoint(name::String, data::Dict{Symbol}; tags...)
    checkpoint(CHECKPOINTS[name], name, data; tags...)
end

checkpoint(name::String, data::Pair...; tags...) = checkpoint(name, Dict(data...); tags...)

checkpoint(name::String, data; tags...) = checkpoint(name, Dict(:data => data); tags...)

function checkpoint(prefix::Union{Module, String}, name::String, args...; kwargs...)
    checkpoint("$prefix.$name", args...; kwargs...)
end

"""
    config(handler::Handler, labels::Vector{String})
    config(handler::Handler, prefix::String)
    config(labels::Vector{String}, args...; kwargs...)
    config(prefix::String, args...; kwargs...)

Configures the specified checkpoints with a `Handler`.
If the first argument is not a `Handler` then all `args` and `kwargs` are passed to a
`Handler` constructor for you.
"""
function config(handler::Handler, names::Vector{String})
    for n in names
        haskey(CHECKPOINTS, n) || warn(LOGGER, "$n is not a registered checkpoint")
        debug(LOGGER, "Checkpoint $n set to use $(handler)")
        CHECKPOINTS[n] = handler
    end
end

function config(handler::Handler, prefix::Union{Module, String})
    config(handler, filter(l -> startswith(l, prefix), available()))
end

function config(names::Vector{String}, args...; kwargs...)
    config(Handler(args...; kwargs...), names)
end

function config(prefix::Union{Module, String}, args...; kwargs...)
    config(Handler(args...; kwargs...), prefix)
end


"""
    register([prefix], labels)

Registers a checkpoint that may be configured at a later time.
"""
function register end

function register(labels::Vector{String})
    for l in labels
        if haskey(CHECKPOINTS, l)
            warn(LOGGER, "$l has already registered")
        else
            CHECKPOINTS[l] = nothing
        end
    end
end

function register(prefix::Union{Module, String}, labels::Vector{String})
    register(map(l -> join([prefix, l], "."), labels))
end

end  # module
