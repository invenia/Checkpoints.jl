module TestPkg

using Checkpoints: register, checkpoint

# We aren't using `@__MODULE__` because that would return TestPkg on 0.6 and Main.TestPkg on 0.7
const MODULE = "TestPkg"

__init__() = register(MODULE, ["foo", "bar"])

function foo(x::Matrix, y::Matrix)
    # Save multiple variables to 1 foo.jlso file by passing in pairs of variables
    checkpoint(MODULE, "foo", "x" => x, "y" => y)
    return x * y
end


function bar(a::Vector)
    # Save a single value for bar.jlso. The object name in that file defaults to "data".
    checkpoint(MODULE, "bar", a)
    return a * a'
end

end
