module TestPkg

using Checkpoints: register, checkpoint, Session

# We aren't using `@__MODULE__` because that would return TestPkg on 0.6 and Main.TestPkg on 0.7
const MODULE = "TestPkg"

__init__() = register(MODULE, ["foo", "bar", "baz", "qux_a", "qux_b", "tagscheck"])

function foo(x::Matrix, y::Matrix)
    # Save multiple variables to 1 foo.jlso file by passing in pairs of variables
    checkpoint(MODULE, "foo", :x => x, :y => y)
    return x * y
end

function bar(a::Vector)
    # Save a single value for bar.jlso. The object name in that file defaults to :data.
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

function qux(a::Dict, b::Vector)
    # Check that saving multiple values to multiple Sessions also works.
    Session(MODULE, ["qux_a", "qux_b"]) do sa, sb
        for (k, v) in a
            checkpoint(sa, k => v)
        end

        checkpoint(sb, b)
    end
end

end
