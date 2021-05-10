function checkpoint_deprecation()
    Base.depwarn(
        "checkpoint(args...; tag=1) is deprecated, use\n" *
        "with_checkpoint_tags(:tag=>1) do\n" *
        "    checkpoint(args...)\n" *
        "end\n" *
        "instead. Note the use of `Pair`s instead of keyword arguments.",
        :checkpoint
    )
end
