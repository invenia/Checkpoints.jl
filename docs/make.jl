using Documenter, Checkpoints

makedocs(
    modules=[Checkpoints],
    format=:html,
    pages=[
        "Home" => "index.md",
    ],
    repo="https://gitlab.invenia.ca/invenia/Checkpoints.jl/blob/{commit}{path}#L{line}",
    sitename="Checkpoints.jl",
    authors="rofinn",
    assets=[
        "assets/invenia.css",
     ],
)
