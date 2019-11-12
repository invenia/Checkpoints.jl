# Usage

Let's begin by creating a module (or package) that contains data we may want to save
(or checkpoint).

```julia
julia> module TestPkg

       using Checkpoints: register, checkpoint, Session

       # We aren't using `@__MODULE__` because that would return TestPkg on 0.6 and Main.TestPkg on 0.7
       const MODULE = "TestPkg"

       __init__() = register(MODULE, ["foo", "bar", "baz"])

       function foo(x::Matrix, y::Matrix)
           # Save multiple variables to 1 foo.jlso file by passing in pairs of variables
           checkpoint(MODULE, "foo", "x" => x, "y" => y)
           return x * y
       end

       function bar(a::Vector)
           # Save a single value for bar.jlso. The object name in that file defaults to "date".
           # Any kwargs passed to checkpoint will be appended to the handler path passed to config.
           # In this case the path would be `<prefix>/date=2017-01-01/TestPkg/bar.jlso`
           checkpoint(MODULE, "bar", a; date="2017-01-01")
           return a * a'
       end

       function baz(data::Dict)
            # Check that saving multiple values to a Session works.
            Session(MODULE, "baz") do s
                for (k, v) in data
                    checkpoint(s, k => v)
                end
            end
        end
    end

TestPkg
```

## Basic Checkpointing

Now we get a list of all available checkpoints outside our module.
```julia
julia> using Checkpoints

julia> Checkpoints.available()
2-element Array{String,1}:
 "TestPkg.bar"
 "TestPkg.foo"
 "TestPkg.baz"
```

Let's start by looking at `TestPkg.foo`

#### Package

As a reference, here is the sample code for `TestPkg.foo` that we'll be calling.

```julia
...
function foo(x::Matrix, y::Matrix)
    # Save multiple variables to 1 foo.jlso file by passing in pairs of variables
    checkpoint(MODULE, "foo", "x" => x, "y" => y)
    return x * y
end
...
```

#### Application

We can run our function `TestPkg.foo` normally without saving any data.
```julia
julia> TestPkg.foo(rand(5, 5), rand(5, 5))
5×5 Array{Float64,2}:
 0.968095  1.18687  1.55126  0.393847  0.854391
 0.839788  1.1527   1.36785  0.361546  0.818136
 1.44853   1.5996   2.17535  0.567696  1.31739
 1.08267   1.74522  2.28862  0.673888  1.35935
 0.755876  1.62275  2.24326  0.727734  1.13352
```

Now we just need to assign a backend handler for our checkpoints. In our case,
all checkpoints with the prefix `"TestPkg.foo"`.
```julia
julia> Checkpoints.config("TestPkg.foo", "./checkpoints")
```

To confirm that our checkpoints work let's assign our expected `x` and `y values to local
variables.
```julia
julia> x = rand(5, 5)
5×5 Array{Float64,2}:
 0.605955  0.314332  0.666603   0.997074  0.106063
 0.691509  0.438608  0.121533   0.931504  0.127145
 0.704745  0.640941  0.237085   0.333055  0.648672
 0.911475  0.410938  0.0143505  0.257862  0.0238969
 0.956029  0.593267  0.0334345  0.374615  0.0301007

julia> y = rand(5, 5)
5×5 Array{Float64,2}:
 0.245635  0.211488  0.122208   0.917927  0.736712
 0.556079  0.837774  0.0845954  0.812386  0.478323
 0.661403  0.307322  0.015631   0.150063  0.765874
 0.949725  0.332881  0.667242   0.468574  0.223302
 0.723806  0.682948  0.511228   0.635479  0.879735
```

Finally, rerun `TestPkg.foo` and inspect the generated file
```julia
julia> TestPkg.foo(x, y)
5×5 Array{Float64,2}:
 1.78824   1.0007    0.830574  1.44622  1.42326
 1.47084   0.947963  0.81005   1.52659  1.13218
 1.47216   1.31275   0.697899  1.77145  1.65238
 0.724089  0.643606  0.33065   1.30867  0.95765
 0.964419  0.854747  0.432891  1.55921  1.12383

julia> isfile("checkpoints/TestPkg/foo.jlso")
true

julia> using JLSO

julia> d = JLSO.load("checkpoints/TestPkg/foo.jlso")
Dict{String,Any} with 2 entries:
  "x" => [0.605955 0.314332 … 0.997074 0.106063; 0.691509 0.438608 … 0.931504 0.127145; … ; 0.911475 0.410938 … 0.257862 0.0238969; 0.956029…
  "y" => [0.245635 0.211488 … 0.917927 0.736712; 0.556079 0.837774 … 0.812386 0.478323; … ; 0.949725 0.332881 … 0.468574 0.223302; 0.723806 …

julia> d["x"]
5×5 Array{Float64,2}:
 0.605955  0.314332  0.666603   0.997074  0.106063
 0.691509  0.438608  0.121533   0.931504  0.127145
 0.704745  0.640941  0.237085   0.333055  0.648672
 0.911475  0.410938  0.0143505  0.257862  0.0238969
 0.956029  0.593267  0.0334345  0.374615  0.0301007

```

As we can see, the value of `x` was successfully saved to `checkpoints/MyPkg/foo.jlso`.

## Tags

Tags can be used to append the handler path at runtime.

#### Package

As a reference, here is the sample code for `TestPkg.bar` that we'll be calling.

```julia
...
function bar(a::Vector)
    # Save a single value for bar.jlso. The object name in that file defaults to "date".
    # Any kwargs passed to checkpoint will be appended to the handler path passed to config.
    # In this case the path would be `<prefix>/date=2017-01-01/TestPkg/bar.jlso`
    checkpoint(MODULE, "bar", a; date="2017-01-01")
    return a * a'
end
...
```

#### Application

```julia

julia> a = rand(10)
10-element Array{Float64,1}:
 0.166881
 0.817174
 0.413097
 0.955415
 0.139473
 0.49518
 0.416731
 0.431096
 0.126912
 0.600469

julia> Checkpoints.config("TestPkg.bar", "./checkpoints")

julia> JLSO.load("./checkpoints/date=2017-01-01/TestPkg/bar.jlso")
Dict{String,Any} with 1 entry:
  :data => [0.166881, 0.817174, 0.413097, 0.955415, 0.139473, 0.49518, 0.416731, 0.431096, 0.126912, 0.600469]
```

## Sessions

If you'd like to iteratively checkpoint data (e.g., in a loop) then we recommend using a session.

#### Package

As a reference, here is the sample code for `TestPkg.baz` that we'll be calling.

```julia
...
function baz(data::Dict)
    # Check that saving multiple values to a Session works.
    Session(MODULE, "baz") do s
        for (k, v) in data
            checkpoint(s, k => v)
        end
    end
end
...
```

#### Application

```julia
julia> d = Dict("x" => rand(10), "y" => rand(10))
Dict{String,Array{Float64,1}} with 2 entries:
  "x" => [0.517666, 0.976474, 0.961658, 0.0933946, 0.877478, 0.428836, 0.0623459, 0.548001, 0.437111, 0.0783503]
  "y" => [0.0623591, 0.0441436, 0.28578, 0.289995, 0.999642, 0.26299, 0.965148, 0.899285, 0.292166, 0.595886]

julia> TestPkg.baz(d)

julia> JLSO.load("./checkpoints/TestPkg/baz.jlso")
Dict{String,Any} with 2 entries:
  "x" => [0.517666, 0.976474, 0.961658, 0.0933946, 0.877478, 0.428836, 0.0623459, 0.548001, 0.437111, 0.0783503]
  "y" => [0.0623591, 0.0441436, 0.28578, 0.289995, 0.999642, 0.26299, 0.965148, 0.899285, 0.292166, 0.595886]
```

## Load Failures

What if I can't `load` my .jlso files?

If you're julia environment doesn't match the one used to save .jlso file
(e.g., different julia version or missing packages) then you may get errors.

```julia
julia> using Checkpoints, JLSO
[ Info: Recompiling stale cache file /Users/rory/.playground/share/checkpoints/depot/compiled/v1.0/Checkpoints/E2USV.ji for Checkpoints [08085054-0ffc-5852-afcc-fc6ba29efde0]

julia> d = JLSO.load("checkpoints/TestPkg/foo.jlso")
[warn | JLSO]: EOFError: read end of file
[warn | JLSO]: EOFError: read end of file
Dict{String,Any} with 2 entries:
  "x" => UInt8[0x15, 0x00, 0x0e, 0x14, 0x02, 0xca, 0xca, 0x32, 0x20, 0x7b  …  0x98, 0x3f, 0xc6, 0xc9, 0x58, 0xc8, 0xb7, 0xd2, 0x9e, 0x3f]
  "y" => UInt8[0x15, 0x00, 0x0e, 0x14, 0x02, 0xca, 0xca, 0xfe, 0x60, 0xe0  …  0xcc, 0x3f, 0x9f, 0xb0, 0xc4, 0x03, 0xca, 0x26, 0xec, 0x3f]
```

In this case, we should try manually loading the `JLSO.JLSOFile` and inspect the metadata
saved with the file.

```julia
julia> jlso = open("checkpoints/TestPkg/foo.jlso") do io
           read(io, JLSO.JLSOFile)
       end
JLSOFile([x, y]; version=v"1.0.0", julia=v"0.6.4", format=:serialize, image="")

julia> VERSION
v"1.0.0"
```

As we can see, our .jlso file was saved in julia v0.6.4 and we're trying to load in on julia v1.0.
If you still have difficulty loading the file when the julia versions match then you may want to inspect
the package versions installed when saving the file.

```julia
julia> jlso.pkgs
Dict{String,VersionNumber} with 60 entries:
  "Coverage"            => v"0.6.0"
  "HTTP"                => v"0.6.15"
  "LegacyStrings"       => v"0.4.0"
  "Nullables"           => v"0.0.8"
  "AxisArrays"          => v"0.2.1"
  "Compat"              => v"1.2.0"
  "DataStructures"      => v"0.8.4"
  "CategoricalArrays"   => v"0.3.14"
  "Calculus"            => v"0.4.1"
  "DeepDiffs"           => v"1.1.0"
  "StatsFuns"           => v"0.6.1"
  "JLD2"                => v"0.0.6"
  "DataFrames"          => v"0.11.7"
  "SpecialFunctions"    => v"0.6.0"
  "TranscodingStreams"  => v"0.5.4"
  "Blosc"               => v"0.5.1"
  "Distributions"       => v"0.15.0"
  "SHA"                 => v"0.5.7"
  "Missings"            => v"0.2.10"
  "SymDict"             => v"0.2.1"
  "CodecZlib"           => v"0.4.4"
  "HDF5"                => v"0.9.5"
  "AWSCore"             => v"0.3.9"
  "Retry"               => v"0.2.0"
  "MbedTLS"             => v"0.5.13"
  "FileIO"              => v"0.9.1"
  "Mocking"             => v"0.5.7"
  "TimeZones"           => v"0.8.0"
  "BSON"                => v"0.1.4"
  "PDMats"              => v"0.8.0"
  "BenchmarkTools"      => v"0.3.2"
  "SortingAlgorithms"   => v"0.2.1"
  "WeakRefStrings"      => v"0.4.7"
  "Memento"             => v"0.10.0"
  "Syslogs"             => v"0.2.0"
  "JSON"                => v"0.17.2"
  "StatsBase"           => v"0.23.1"
  "DocStringExtensions" => v"0.4.6"
  "Checkpoints"         => v"0.0.0-"
  "QuadGK"              => v"0.3.0"
  "BinDeps"             => v"0.8.10"
  "RangeArrays"         => v"0.3.1"
  "Parameters"          => v"0.9.2"
  "Reexport"            => v"0.1.0"
  "CMakeWrapper"        => v"0.1.0"
  "URIParser"           => v"0.3.1"
  "XMLDict"             => v"0.1.3"
  "Documenter"          => v"0.19.6"
  "IntervalSets"        => v"0.3.0"
  "DataStreams"         => v"0.3.6"
  "JLD"                 => v"0.8.3"
  "Rmath"               => v"0.4.0"
  "BinaryProvider"      => v"0.3.3"
  "IterTools"           => v"0.2.1"
  "IniFile"             => v"0.4.0"
  "AWSSDK"              => v"0.3.1"
  "NamedTuples"         => v"4.0.2"
  "AWSS3"               => v"0.3.7"
  "Homebrew"            => v"0.6.4"
  "LightXML"            => v"0.7.0"
```
