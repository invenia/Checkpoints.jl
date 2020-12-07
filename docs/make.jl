using Documenter, Checkpoints

makedocs(
    modules=[Checkpoints],
    format=Documenter.HTML(
        assets=["assets/invenia.css"],
        prettyurls=(get(ENV, "CI", nothing) == "true")
    ),
    pages=[
        "Home" => "index.md",
        "Usage" => "usage.md",
        "API" => "api.md",
    ],
    repo="https://github.com/invenia/Checkpoints.jl/blob/{commit}{path}#L{line}",
    sitename="Checkpoints.jl",
    authors="Invenia Technical Computing Corporation",
)

deploydocs(;
    repo="github.com/invenia/Checkpoints.jl",
)
