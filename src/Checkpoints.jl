"""
    Checkpoints

A very minimal module for defining checkpoints or save location in large codebase with
the ability to configure how those checkpoints save data externally
(similar to how Memento.jl works for logging).
"""
module Checkpoints

using AWSCore
using AWSS3
using Memento
using Mocking

using AWSCore: AWSConfig
using AWSS3: s3_put
using Compat: @__MODULE__

export JLSO

const CHECKPOINTS = Dict{String, Function}()
const LOGGER = getlogger(@__MODULE__)

__init__() = Memento.register(LOGGER)

include("JLSO.jl")

"""
    saver(prefix::String; kwargs...) -> Function
    saver(config::AWSConfig, bucket::String, prefix::String; kwargs...) -> Function

Generates a function that will dynamically saving variables to organized JLSO files locally
or on S3. Labels with '.' separators will be used to form subdirectories
(e.g., "Foo.bar.x" will be saved to "\$prefix/Foo/bar/x.jlso")
"""
function saver(prefix::String; kwargs...)
    function f(label, data)
        parts = split(label, '.')
        parts[end] = string(parts[end], ".jlso")
        parent = joinpath(prefix, parts[1:end-1]...)

        # Make the parent path if doesn't already exist
        mkpath(parent)

        # Save the file to disk
        path = joinpath(parent, parts[end])
        JLSO.save(path, data; kwargs...)
    end

    return f
end

function saver(config::AWSConfig, bucket::String, prefix::String; kwargs...)
    function f(label, data)
        parts = split(label, ".")
        parts[end] = string(parts[end], ".jlso")
        key = join(vcat([prefix], parts), "/")

        # Serialize the data to an IOBuffer
        io = IOBuffer()
        JLSO.save(io, data; kwargs...)

        # Upload the serialized object (Vector{UInt8})
        @mock s3_put(config, bucket, key, take!(io))
    end

    return f
end

# TODO: Migrate the `saver` into a Saver/Loader API to allow the same settings to be used
# for both saving and loading objects.

"""
    register([prefix], labels)

Registers a checkpoint that may be configured at a later time.
"""
function register(labels::Vector{String})
    for l in labels
        if haskey(CHECKPOINTS, l)
            warn(LOGGER, "$l has already registered")
        else
            CHECKPOINTS[l] = (k, v) -> nothing
        end
    end
end

function register(prefix::Union{Module, String}, labels::Vector{String})
    register(map(l -> join([prefix, l], "."), labels))
end

"""
    config(backend::Function, labels::Vector{String})
    config(backend::Function, prefix::String)

Configures the specified checkpoints with the backend saving function.
The backend function is expected to take the checkpoint label and data to be saved.
The data is a `Dict` mapping variable names and values.
"""
function config(backend::Function, labels::Vector{String})
    for l in labels
        haskey(CHECKPOINTS, l) || warn(LOGGER, "$l is not a registered checkpoint label")
        CHECKPOINTS[l] = backend
    end
end

function config(backend::Function, prefix::Union{Module, String})
    config(backend, filter(l -> startswith(l, prefix), available()))
end

"""
    checkpoint([prefix], label, data)
    checkpoint([prefix], label, data::Pair...)
    checkpoint([prefix], label, data::Dict)

Defines a data checkpoint with a specified `label` and values `data`.
By default checkpoints are no-ops and need to be configured with a backend funciton.
"""
checkpoint(label::String, data::Dict) = CHECKPOINTS[label](label, data)
checkpoint(label::String, data::Pair...) = checkpoint(label, Dict(data...))
checkpoint(label::String, data) = checkpoint(label, Dict("data" => data))
function checkpoint(prefix::Union{Module, String}, label::String, args...)
    checkpoint(join([prefix, label], "."), args...)
end

"""
    available() -> Vector{String}

Returns a vector of all available (registered) checkpoints.
"""
available() = collect(keys(CHECKPOINTS))

end  # module
