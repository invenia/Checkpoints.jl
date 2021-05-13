"""
    CheckpointOutput

This is a index entry describing the output file from a checkpoint.
You can retrieve a list of these from a folder full of such outputs, using
[`index_checkpoint_files`](@ref).

For accessing details of the CheckpointOutput the following helpers are provided:
[`path`](@ref), [`name`](@ref), [`groups`](@ref), [`tags`](@ref).
Further: `getproperty` is overloaded so that you can access the value of the tag `:foo` via
`x.foo`.
"""
struct CheckpointOutput{P<:AbstractPath}
    path::P
    name::AbstractString
    groups::NTuple{<:Any, AbstractString}
    tags::NTuple{<:Any, Pair{Symbol, <:AbstractString}}
end

path(x::CheckpointOutput) = getfield(x, :path)
name(x::CheckpointOutput) = getfield(x, :name)
groups(x::CheckpointOutput) = getfield(x, :groups)
tags(x::CheckpointOutput) = getfield(x, :tags)
_tag_names(x::CheckpointOutput) = first.(tags(x))

#Tables.columnnames(x::CheckpointOutput) = propertynames(x)
Base.propertynames(x::CheckpointOutput) =  [:groups, :name, _tag_names(x)..., :path]

function Base.getproperty(x::CheckpointOutput, name::Symbol)
    inds = findall(==(name)∘first, tags(x))
    if length(inds) > 1
        error(
            "The checkpoint was tagged with $name multiple times (positions $inds). " *
            "you thus can not use the getproperty shorthand to check its tag, as we don't" *
            "know which you mean. Use the `tags` function instead."
        )
    elseif length(inds) == 0
        if hasfield(CheckpointOutput, name)
            # as long as we don't have a tag with one of the field names we pass it through
            return getfield(x, name)
        else
            error(
                "The checkpoint does not have the tag $name. It has tags: $(_tag_names(x))"
            )
        end
    else  # tag found
        _, val = only(tags(x)[inds])
        return val
    end
end


"""
    index_checkpoint_files(dir)

Constructs a index for all the files output by checkpoints located within  `dir`.
This index tells you their, name, path, tags, etc.
See [`CheckpointOutput`](@ref) for full information on what is recorded.

Handily, a `Vector{CheckpointOutput}` is a valid [Tables.jl Table][1]. This means you can
do `DataFrame(index_checkpoint_files(dir))` and get a nice easy to work with [DataFrame][2].

You can also work with it directly, say you wanted to get all checkpoints files for
`forecasts` with the tag `model="Stage1"`. This would be something like:
```julia
[path(x) for x in index_checkpoint_files(dir) if x.name=="forecast" && x.model=="Stage1"]
```

1: https://github.com/JuliaData/Tables.jl
2: https://github.com/JuliaData/DataFrames.jl
"""
function index_checkpoint_files(dir::AbstractPath)
    map(Iterators.filter(==("jlso") ∘ extension, walkpath(root))) do path
        name = filename(path)
        relpath = relative(path, dir)
        segments = relpath.segments[1:end-1]
        groups = filter(!contains("="), segments)
        tags = map(filter(contains("="), segments)) do seg
            tag, val = split(seg, "="; limit=2)
            return Symbol(tag)=>val
        end
        return CheckpointOutput(path, name, groups, tags)
    end
end

index_checkpoint_files(dir) = index_checkpoint_files(Path(dir))
