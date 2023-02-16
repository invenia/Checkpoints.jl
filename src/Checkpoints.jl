"""
    Checkpoints

A very minimal module for defining checkpoints or save location in large codebase with
the ability to configure how those checkpoints save data externally
(similar to how Memento.jl works for logging).
"""
module Checkpoints

using AWSS3
using Compat # for contains (julia v1.5)
using ContextVariablesX
using DataStructures: DefaultDict
using FilePathsBase
using FilePathsBase: /, join
using JLSO
using Memento
using OrderedCollections

export checkpoint, with_checkpoint_tags  # creating stuff
export enabled_checkpoints, deprecated_checkpoints
# indexing stuff
export IndexEntry, index_checkpoint_files, index_files
export checkpoint_fullname, checkpoint_name, checkpoint_path, prefixes, tags

const LOGGER = getlogger(@__MODULE__)

__init__() = Memento.register(LOGGER)

include("handler.jl")

const CHECKPOINTS = Dict{String, Union{Nothing, String, AbstractHandler}}()
@contextvar CONTEXT_TAGS::Tuple{Vararg{Pair{Symbol, Any}}} = Tuple{}()

include("session.jl")
include("indexing.jl")
include("deprecated.jl")

"""
    with_checkpoint_tags(f::Function, context_tags::Pair...)
    with_checkpoint_tags(f::Function, context_tags::NamedTuple)

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
with_checkpoint_tags(f::Function, context_tags::NamedTuple) = with_checkpoint_tags(f, pairs(context_tags)...)

"""
    available() -> Vector{String}

Returns a vector of all available (registered) checkpoints.
"""
available() = collect(keys(CHECKPOINTS))

"""
    enabled_checkpoints() -> Vector{String}

Returns a vector of all enabled ([`config`](@ref)ured) and not [`deprecate`](@ref)d checkpoints.
Use [`deprecated_checkpoints`](@ref) to retrieve a mapping of old / deprecated checkpoints.
"""
enabled_checkpoints() = filter(k -> CHECKPOINTS[k] isa AbstractHandler, available())

"""
    deprecated_checkpoints() -> Dict{String, String}

Returns a Dict mapping deprecated checkpoints to the corresponding new names.
"""
function deprecated_checkpoints()
    return Dict{String, String}(filter(p -> last(p) isa String, CHECKPOINTS))
end

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
    checkpoint_deprecation(tags...)
    with_checkpoint_tags(tags...) do
        checkpoint(CHECKPOINTS[name], name, data)
    end
end

function checkpoint(name::String, data::Pair...; tags...)
    checkpoint_deprecation(tags...)
    with_checkpoint_tags(tags...) do
        checkpoint(name, Dict(data...))
    end
end

function checkpoint(name::String, data; tags...)
    checkpoint_deprecation(tags...)
    with_checkpoint_tags(tags...) do
        checkpoint(name, Dict(:data => data))
    end
end

function checkpoint(prefix::Union{Module, String}, name::String, args...; tags...)
    checkpoint_deprecation(tags...)
    with_checkpoint_tags(tags...) do
        checkpoint("$prefix.$name", args...)
    end
end

"""
    config(handler::AbstractHandler, labels::Vector{String})
    config(handler::AbstractHandler, prefix::String)
    config(labels::Vector{String}, args...; kwargs...)
    config(prefix::String, args...; kwargs...)

Configures the specified checkpoints with a `AbstractHandler`.
If the first argument is not an `AbstractHandler` then all `args` and `kwargs` are
passed to a `JLSOHandler` constructor for you.
"""
function config(handler::AbstractHandler, names::Vector{String})
    for n in names
        _config(handler, n)
    end
end

function config(handler::AbstractHandler, prefix::Union{Module, String})
    config(handler, filter(l -> startswith(l, prefix), available()))
end

function config(names::Vector{String}, args...; kwargs...)
    config(JLSOHandler(args...; kwargs...), names)
end

function config(prefix::Union{Module, String}, args...; kwargs...)
    config(JLSOHandler(args...; kwargs...), prefix)
end

# To avoid collisions with `prefix` method above, which should probably use
# a regex / glob syntax
function _config(handler, name::String)
    haskey(CHECKPOINTS, name) || warn(LOGGER, "$name is not a registered checkpoint")

    # Warn about deprecated checkpoints and recurse if necessary
    if CHECKPOINTS[name] isa String
        Base.depwarn("$name has been deprecated to $(CHECKPOINTS[name])", :config)
        return _config(handler, CHECKPOINTS[name])
    else
        debug(LOGGER, "Checkpoint $name set to use $(handler)")
        return setindex!(CHECKPOINTS, handler, name)
    end
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


"""
    deprecate([prefix], prev, curr)

Deprecate a checkpoint that has been renamed.
"""
function deprecate end

deprecate(prev, curr) = setindex!(CHECKPOINTS, curr, prev)

function deprecate(prefix::Union{Module, String}, prev, curr)
    deprecate(join([prefix, prev], "."), join([prefix, curr], "."))
end

end  # module
