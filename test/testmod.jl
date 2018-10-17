module TestModule

using Checkpoints
using Checkpoints: register, checkpoint
using Compat: @__MODULE__

const MODULE = @__MODULE__()

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
