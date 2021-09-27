"""
    IndexEntry(checkpoint_path, [checkpoint_name, prefixes, tags])

This is an index entry describing the output file from a checkpoint.
You can retrieve a list of these from a folder full of such outputs, using
[`index_checkpoint_files`](@ref).

For accessing details of the IndexEntry the following helpers are provided:
[`checkpoint_path`](@ref), [`checkpoint_name`](@ref), [`prefixes`](@ref), [`tags`](@ref).
Further: `getproperty` is overloaded so that you can access the value of the tag `:foo` via
`x.foo`.
"""
struct IndexEntry
    checkpoint_path::AbstractPath
    checkpoint_name::AbstractString
    prefixes::NTuple{<:Any, AbstractString}
    tags::NTuple{<:Any, Pair{Symbol, <:AbstractString}}
end

IndexEntry(file) = IndexEntry(Path(file))
function IndexEntry(filepath::AbstractPath)
    # skip any non-tag directories at the start. Note this will be tricked if those have "="
    # in them but probably not worth handling, unless an issue comes up
    first_tag_ind = something(findfirst(contains("="), filepath.segments), 1)
    segments = filepath.segments[first_tag_ind:end-1]

    prefixes = filter(!contains("="), segments)
    tags = map(filter(contains("="), segments)) do seg
        tag, val = split(seg, "="; limit=2)
        return Symbol(tag)=>val
    end
    checkpoint_name = filename(filepath)
    return IndexEntry(filepath, checkpoint_name, prefixes, tags)
end


"""
    checkpoint_path(x::IndexEntry)

The checkpoint_path to the checkpoint output file.
For example `S3Path("s3::/mybucket/tag1=a/tag2=b/group1/group2/forecasts.jlso)`.
"""
checkpoint_path(x::IndexEntry) = getfield(x, :checkpoint_path)

"""
    checkpoint_name(x::IndexEntry)

The checkpoint_name of the checkpoint output file.
If the checkpoint was saved used `checkpoint(Forecasters, "forecasts", ...)` then it's
`checkpoint_name` is `"forecasts"`.
"""
checkpoint_name(x::IndexEntry) = getfield(x, :checkpoint_name)

"""
    prefixes(x::IndexEntry)

The prefixes of the checkpoint output file. This is a tuple of any prefixes specified.
If the checkpoint was saved used `checkpoint(Forecasters, "forecasts", ...)` then it's
`prefixes` are `("Forecasters",)`. Generally in practice there are either one matching the
module the checkpoint was declared in (as in the previous example), or zero if it wasn't
specified (as in `checkpoint("forecasts",...)`). If it was saved as
`checkpoint("Foo.Bar", "forecasts.jlso")` then prefixed will return `("Foo", "Bar")`.
"""
prefixes(x::IndexEntry) = getfield(x, :prefixes)

"""
    tags(x::IndexEntry)

All tags and there values of the checkpoint. This is a collection of pairs.
For example if the checkpoint was saved using:
```julia
with_tag(:sim_now=>DateTime(2000,1,1,9,00), grid=ERCOT) do
    checkpoint(Forecasters, "forecasts", ...)`
end
```
Then `tags(x)` would return: `(:sim_now="2000-01-01T09:00:00", :grid=>"ERCOT")`.

Note that if the tags are unique, then their values call also be accessed via a
`getproperty` overload, e.g as `x.sim_now` or `x.grid`.
"""
tags(x::IndexEntry) = getfield(x, :tags)

_tag_names(x::IndexEntry) = first.(tags(x))

#Tables.columnnames(x::IndexEntry) = propertynames(x)
function Base.propertynames(x::IndexEntry)
    return [:prefixes, :checkpoint_name, _tag_names(x)..., :checkpoint_path]
end

function Base.getproperty(x::IndexEntry, name::Symbol)
    inds = findall(==(name)∘first, tags(x))
    if length(inds) > 1
        error(
            "The checkpoint was tagged with $name multiple times (positions $inds). " *
            "you thus can not use the getproperty shorthand to check its tag, as we don't" *
            "know which you mean. Use the `tags` function instead."
        )
    elseif length(inds) == 0
        if hasfield(IndexEntry, name)
            return getfield(x, name)
        else
            error(
                "The checkpoint does not have the tag $name. It has tags: $(_tag_names(x))"
            )
        end
    else  # tag found
        if hasfield(IndexEntry, name)  #also is a field, so lets error
            error(
                "$name is both a tag, and a field of the index entry itself. use the " *
                "function $name(x) to get the index entry field, or work with `tags(x)` " *
                "for the field"
            )
        else
            _, val = only(tags(x)[inds])
            return val
        end
    end
end


"""
    index_checkpoint_files(dir)

Constructs a index for all the files output by checkpoints located within  `dir`.
This index tells you their checkpoint_name, checkpoint_path, tags, etc.
See [`IndexEntry`](@ref) for full information on what is recorded.

Handily, a `Vector{IndexEntry}` is a valid [Tables.jl Table][1]. This means you can
do `DataFrame(index_checkpoint_files(dir))` and get a nice easy to work with [DataFrame][2].

You can also work with it directly, say you wanted to get all checkpoints files for
`forecasts` with the tag `model="Stage1"`. This would be something like:
```julia
[checkpoint_path(x) for x in index_checkpoint_files(dir) if x.checkpoint_name=="forecast" && x.model=="Stage1"]
```

1: https://github.com/JuliaData/Tables.jl
2: https://github.com/JuliaData/DataFrames.jl
"""
function index_checkpoint_files(dir::AbstractPath)
    isdir(dir) || throw(ArgumentError(dir, "Need an existing directory."))
    map(Iterators.filter(==("jlso") ∘ extension, walkpath(dir))) do checkpoint_path
        return IndexEntry(checkpoint_path)
    end
end

index_checkpoint_files(dir) = index_checkpoint_files(Path(dir))

"""
    index_files(dir)

Constructs a index for all the files located within  `dir`.
Same as [`index_checkpoint_files`] except not restricted to files created by Checkpoints.jl.
"""
function index_files(dir::AbstractPath)
    map(Iterators.filter(isfile, walkpath(dir))) do path
        return IndexEntry(path)
    end
end

index_files(dir) = index_files(Path(dir))
