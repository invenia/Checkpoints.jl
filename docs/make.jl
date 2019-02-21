using Documenter, Checkpoints

makedocs(
    modules=[Checkpoints],
    format=Documenter.HTML(prettyurls=(get(ENV, "CI", nothing) == "true")),
    pages=[
        "Home" => "index.md",
        "Usage" => "usage.md",
        "API" => "api.md",
    ],
    repo="https://gitlab.invenia.ca/invenia/Checkpoints.jl/blob/{commit}{path}#L{line}",
    sitename="Checkpoints.jl",
    authors="Rory Finnegan",
    assets=[
        "assets/invenia.css",
    ],
    strict = true,
    checkdocs = :none,
)
