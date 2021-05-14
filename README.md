# Checkpoints
[![stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://invenia.github.io/Checkpoints.jl/stable)
[![build status](https://github.com/invenia/Checkpoints.jl/workflows/CI/badge.svg)](https://github.com/invenia/Checkpoints.jl/actions)
[![coverage](https://codecov.io/gh/invenia/Checkpoints.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/invenia/Checkpoints.jl)

Checkpoints.jl allows packages to `register` checkpoints which can serialize objects to disk
during the execution of an application program, if the application program `config`ures them.

A minimal working example consists of the package:

```julia
module MyPackage

using Checkpoints

MODULE = "MyPackage"

__init__() = Checkpoints.register(MODULE, ["foo", ])

function foo(x)
    with_checkpoint_tags(:foo1 => 1, :foo2 => 2) do
        checkpoint(MODULE, "foo", :data => 2x)
    end
    return 2x
end

end
```

and the application program:

```julia
using Checkpoints

Checkpoints.config("MyPackage.foo", "./path/to/checkpoints")

for i in 1:2
    with_checkpoint_tags(:iteration => i) do
        MyPackage.foo(1.0)
    end
end
```

which results in recorded checkpoints at
```
./path/to/checkpoints/iteration=1/foo1=1/foo2=2/MyPackage/foo.jlso
./path/to/checkpoints/iteration=2/foo1=1/foo2=2/MyPackage/foo.jlso
```
