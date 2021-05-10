"""
    Checkpoints

A very minimal module for defining checkpoints or save location in large codebase with
the ability to configure how those checkpoints save data externally
(similar to how Memento.jl works for logging).
"""
module Checkpoints

using AWSS3
using ContextVariablesX
using DataStructures: DefaultDict
using FilePathsBase
using FilePathsBase: /, join
using JLSO
using Memento
using OrderedCollections

export checkpoint, with_checkpoint_tags

const LOGGER = getlogger(@__MODULE__)

__init__() = Memento.register(LOGGER)

include("handler.jl")

const CHECKPOINTS = Dict{String, Union{Nothing, Handler}}()
@contextvar CONTEXT_TAGS::Tuple{Vararg{Pair{Symbol, Any}}} = Tuple{}()

include("session.jl")
include("deprecated.jl")

"""
    with_checkpoint_tags(f::Function, context_tags::Pair...)

Runs the function `f`, tagging any [`checkpoint`](@ref)s created by `f` with the `context_tags`.
This is normally used via the do-block form:
For example

```julia
with_checkpoint_tags(:foo=>1, :bar=>2) do
    q_out = qux()
    checkpoint("foobar"; :output=q_out)
end
```
This snippet will result in `"foobar"` checkpoint having the `foo=1` and `bar=2` tags, as will any checkpoints created by `qux`().
The context tags are [dynamically scoped](https://en.wikipedia.org/wiki/Scope_(computer_science)#Lexical_scope_vs._dynamic_scope_2) and so are retained through function calls.

Nested contexts (nested `with_checkpoint_tags` calls) are allowed. Duplicate tag names and values are
allowed, including the tags provided directly in the [`checkpoint`](@ref) call.
Duplicate tags are repeated, not overwritten.
"""
function with_checkpoint_tags(f::Function, context_tags::Pair...)
    with_context(f, CONTEXT_TAGS => (CONTEXT_TAGS[]..., context_tags...))
end

"""
    available() -> Vector{String}

Returns a vector of all available (registered) checkpoints.
"""
available() = collect(keys(CHECKPOINTS))

"""
    checkpoint([prefix], name, data)
    checkpoint([prefix], name, data::Pair...)
    checkpoint([prefix], name, data::Dict)

Defines a data checkpoint with a specified `label` and values `data`.
By default checkpoints are no-ops and need to be explicitly configured.

    checkpoint(session, data)
    checkpoint(handler, name, data::Dict)

Alternatively, you can also checkpoint with to a session which stages the data to be
commited later by `commit!(session)`.
Explicitly calling checkpoint on a handler is generally not advised, but is an option.
"""
function checkpoint(name::String, data::Dict{Symbol}; tags...)
    isempty(tags) || checkpoint_deprecation()
    with_checkpoint_tags(tags...) do
        checkpoint(CHECKPOINTS[name], name, data)
    end
end

function checkpoint(name::String, data::Pair...; tags...)
    isempty(tags) || checkpoint_deprecation()
    with_checkpoint_tags(tags...) do
        checkpoint(name, Dict(data...))
    end
end

function checkpoint(name::String, data; tags...)
    isempty(tags) || checkpoint_deprecation()
    with_checkpoint_tags(tags...) do
        checkpoint(name, Dict(:data => data))
    end
end

function checkpoint(prefix::Union{Module, String}, name::String, args...; tags...)
    isempty(tags) || checkpoint_deprecation()
    with_checkpoint_tags(tags...) do
        checkpoint("$prefix.$name", args...)
    end
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
