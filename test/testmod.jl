module TestModule

using Checkpoints
using Checkpoints: register, checkpoint

# We aren't using `@__MODULE__` because that would return TestModule on 0.6 and Main.TestModule on 0.7
const MODULE = "TestModule"

__init__() = register(MODULE, ["foo.x", "foo.y", "bar.a"])

function foo(x::Matrix, y::Matrix)
    checkpoint(MODULE, "foo.x", x)
    checkpoint(MODULE, "foo.y", y)
    return x * y
end


function bar(a::Vector)
    checkpoint(MODULE, "bar.a", a)
    return a * a'
end

end
