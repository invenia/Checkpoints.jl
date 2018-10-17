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

function config(backend::Function, labels::Vector{String})
    for l in labels
        if haskey(CHECKPOINTS, l)
            CHECKPOINTS[l] = backend
        else
            warn(LOGGER, "$l is not a registered checkpoint label")
        end
    end
end

function config(backend::Function, prefix::Union{Module, String})
    config(backend, filter(l -> startswith(l, prefix), labels()))
end

checkpoint(label::String, x) = CHECKPOINTS[label](label, x)
function checkpoint(prefix::Union{Module, String}, label::String, x)
    checkpoint(join([prefix, label], "."), x)
end

labels() = collect(keys(CHECKPOINTS))

end  # module
