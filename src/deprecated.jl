function checkpoint_deprecation(tags...)
    kwargs = join(["$(first(tag))=\"$(last(tag))\"" for tag in tags], ", ")
    pairs = join([":$(first(tag)) => \"$(last(tag))\"" for tag in tags], ", ")

    isempty(tags) || Base.depwarn(
        "checkpoint(args...; $(kwargs)) is deprecated, use\n" *
        "with_checkpoint_tags($(pairs)) do\n" *
        "    checkpoint(args...)\n" *
        "end\n" *
        "instead. Note the use of `Pair`s instead of keyword arguments.",
        :checkpoint
    )
end

Base.@deprecate_binding Handler JLSOHandler
