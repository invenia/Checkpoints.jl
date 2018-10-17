using Documenter, Checkpoints

makedocs(
    modules=[Checkpoints],
    format=:html,
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
)
