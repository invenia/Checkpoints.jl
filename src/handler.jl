struct Handler{P<:AbstractPath}
    path::P
    settings        # Could be Vector or Pairs on 0.6 or 1.0 respectively
end

"""
    Handler(path::Union{String, AbstractPath}; kwargs...)
    Handler(bucket::String, prefix::String; kwargs...)

Handles iteratively saving JLSO file to the specified path location.
FilePath are used to abstract away differences between paths on S3 or locally.
"""
Handler(path::AbstractPath; kwargs...) = Handler(path, kwargs)
Handler(path::String; kwargs...) = Handler(Path(path), kwargs)
Handler(bucket::String, prefix::String; kwargs...) = Handler(S3Path(bucket, prefix), kwargs)

"""
    path(handler, name; tags...)

Determines the path to save to based on the handlers path prefix, name and tags.
Tags are used to dynamically prefix the named file with the handler's path.
Names with a '.' separators will be used to form subdirectories
(e.g., "Foo.bar.x" will be saved to "\$prefix/Foo/bar/x.jlso").
"""
function path(handler::Handler{P}, name::String; tags...) where P
    # Build up a path prefix based on the tags passed in.
    prefix = Vector{String}(undef, length(tags))
    for (i, t) in enumerate(tags)
        prefix[i] = string(first(t), "=", last(t))
    end

    # Split up the name by '.' and add the jlso extension
    parts = split(name, '.')
    parts[end] = string(parts[end], ".jlso")

    return join(handler.path, prefix..., parts...)
end

"""
    stage!(handler::Handler, jlso::JLSOFIle, data::Dict)

Update the JLSOFile with the new data.
"""
function stage!(handler::Handler, jlso::JLSO.JLSOFile, data::Dict)
    for (k, v) in data
        jlso[k] = v
    end

    return jlso
end

"""
    commit!(handler, path, jlso)

Write the JLSOFile to the path as bytes.
"""
function commit!(handler::Handler{P}, path::P, jlso::JLSO.JLSOFile) where P <: AbstractPath
    io = IOBuffer()
    write(io, jlso)
    bytes = take!(io)

    # FilePathsBase should probably default to a no-op?
    if P <: Union{PosixPath, WindowsPath} && hasparent(path)
        mkdir(parent(path); recursive=true, exist_ok=true)
    end

    write(path, bytes)
end

function checkpoint(handler::Handler, name::String, data::Dict; tags...)
    debug(LOGGER, "Checkpoint $name triggerred, with tags: $(join(tags, ", ")).")
    jlso = JLSO.JLSOFile(Dict{String, Vector{UInt8}}(); handler.settings...)
    p = path(handler, name; tags...)
    stage!(handler, jlso, data)
    commit!(handler, p, jlso)
end

#=
Define our no-op conditions just to be safe
=#
function checkpoint(handler::Nothing, name::String, data::Dict; tags...)
    debug(LOGGER, "Checkpoint $name triggerred, but no handler has been set.")
    nothing
end
