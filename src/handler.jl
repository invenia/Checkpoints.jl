abstract type AbstractHandler end

"""
    getkey(handler, name, separator="/") -> String

Combine the `CONTEXT_TAGS` and `name` into a unique checkpoint key as a string.
If the checkpoint name includes `.`, usually representing nested modules, these are
also replaced with the provided separator.
"""
function getkey(::AbstractHandler, name::String, separator="/")::String
    prefix = ["$key=$val" for (key, val) in CONTEXT_TAGS[]]
    parts = split(name, '.')  # Split up the name by '.'
    return Base.join(vcat(prefix, parts), separator)
end

path(args...) = Path(getkey(args...))

"""
    stage!(handler::AbstractHandler, objects, data::Dict{Symbol})

Update the objects with the new data.
By default all handlers assume objects implements the associative interface.
"""
function stage!(handler::AbstractHandler, objects, data::Dict{Symbol})
    for (k, v) in data
        objects[k] = v
    end

    return objects
end

"""
    commit!(handler, prefix, objects)

Serialize and write objects to a given path/prefix/key as defined by the handler.
"""
commit!

#=
Define our no-op conditions just to be safe
=#
function checkpoint(handler::Nothing, name::String, data::Dict{Symbol}; tags...)
    checkpoint_deprecation(tags...)
    with_checkpoint_tags(tags...) do
        debug(LOGGER, "Checkpoint $name triggered, but no handler has been set.")
        nothing
    end
end


struct JLSOHandler{P<:AbstractPath} <: AbstractHandler
    path::P
    settings        # Could be Vector or Pairs on 0.6 or 1.0 respectively
end

"""
    JLSOHandler(path::Union{String, AbstractPath}; kwargs...)
    JLSOHandler(bucket::String, prefix::String; kwargs...)

Handles iteratively saving JLSO file to the specified path location.
FilePath are used to abstract away differences between paths on S3 or locally.
"""
JLSOHandler(path::AbstractPath; kwargs...) = JLSOHandler(path, kwargs)
JLSOHandler(path::String; kwargs...) = JLSOHandler(Path(path), kwargs)
JLSOHandler(bucket::String, prefix::String; kwargs...) = JLSOHandler(S3Path("s3://$bucket/$prefix"), kwargs)

"""
    path(handler, name)

Determines the path to save to based on the handlers path prefix, name, and context.
Tags are used to dynamically prefix the named file with the handler's path.
Names with a '.' separators will be used to form subdirectories
(e.g., "Foo.bar.x" will be saved to "\$prefix/Foo/bar/x.jlso").
"""
function path(handler::JLSOHandler{P}, name::String) where P
    return join(handler.path, getkey(handler, name) * ".jlso")
end

function commit!(handler::JLSOHandler{P}, path::P, jlso::JLSO.JLSOFile) where P <: AbstractPath
    # NOTE: This is only necessary because FilePathsBase.FileBuffer needs to support
    # write(::FileBuffer, ::UInt8)
    # https://github.com/rofinn/FilePathsBase.jl/issues/45
    io = IOBuffer()
    write(io, jlso)
    bytes = take!(io)
    mkdir(parent(path); recursive=true, exist_ok=true)
    write(path, bytes)
end

function checkpoint(handler::JLSOHandler, name::String, data::Dict{Symbol}; tags...)
    checkpoint_deprecation(tags...)
    with_checkpoint_tags(tags...) do
        debug(LOGGER, "Checkpoint $name triggered, with context: $(join(CONTEXT_TAGS[], ", ")).")
        jlso = JLSO.JLSOFile(Dict{Symbol, Vector{UInt8}}(); handler.settings...)
        p = path(handler, name)
        stage!(handler, jlso, data)
        commit!(handler, p, jlso)
    end
end

"""
    DictHandler(objects)

Saves checkpointed objects into a dictionary where the keys are strings generated from
the checkpoint tags and name.
"""
struct DictHandler <: AbstractHandler
    objects::Dict{String, Dict}
    force::Bool
end

DictHandler(; objects=Dict{String, Dict}(), force=false) = DictHandler(objects, force)

function commit!(handler::DictHandler, k::AbstractString, data)
    if handler.force
        return setindex!(handler.objects, data, k)
    else
        res = get!(handler.objects, k, data)
        isequal(res, data) || throw(ArgumentError("$k has already been stored"))
        return res
    end
end

function checkpoint(handler::DictHandler, name::String, data::Dict{Symbol}; tags...)
    # TODO: Remove duplicate wrapper code
    checkpoint_deprecation(tags...)
    with_checkpoint_tags(tags...) do
        debug(LOGGER, "Checkpoint $name triggered, with context: $(join(CONTEXT_TAGS[], ", ")).")
        commit!(handler, getkey(handler, name), data)
    end
end
