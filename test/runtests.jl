using Checkpoints
using Test
using AWSCore
using FilePathsBase
using JLSO
using Random

using AWSCore: AWSConfig
using AWSS3: S3Path, s3_put, s3_list_buckets, s3_create_bucket

@testset "Checkpoints" begin
    include("testpkg.jl")

    x = reshape(collect(1:100), 10, 10)
    y = reshape(collect(101:200), 10, 10)
    a = collect(1:10)

    @testset "Local handler" begin
        mktempdir() do path
            Checkpoints.config("TestPkg.foo", path)

            TestPkg.foo(x, y)
            TestPkg.bar(a)

            mod_path = joinpath(path, "TestPkg")
            @test isdir(mod_path)

            foo_path = joinpath(path, "TestPkg", "foo.jlso")
            bar_path = joinpath(path, "TestPkg", "bar.jlso")
            @test isfile(foo_path)
            @test !isfile(bar_path)

            data = JLSO.load(foo_path)
            @test data["x"] == x
            @test data["y"] == y
        end
    end

    if get(ENV, "LIVE", "false") == "true"
        @testset "S3 handler" begin
            config = AWSCore.aws_config()
            prefix = "Checkpoints.jl/"
            bucket = get(
                ENV,
                "TestBucketAndPrefix",
                string(aws_account_number(config), "-tests")
            )
            bucket in s3_list_buckets(config) || s3_create_bucket(config, bucket)

            mkdir(Path("s3://$bucket/$prefix"); recursive=true, exist_ok=true)

            mktmpdir(Path("s3://$bucket/Checkpoints.jl/")) do fp
                Checkpoints.config("TestPkg.bar", fp)

                TestPkg.bar(a)
                expected_path = fp / "date=2017-01-01" / "TestPkg/bar.jlso"
                @test JLSO.load(IOBuffer(read(expected_path)))["data"] == a
            end
        end
    end

    @testset "Sessions" begin
        @testset "No-op" begin
            mktempdir() do path
                d = Dict(zip(map(x -> Symbol(randstring(4)), 1:10), map(x -> rand(10), 1:10)))

                TestPkg.baz(d)

                mod_path = joinpath(path, "TestPkg")
                baz_path = joinpath(path, "TestPkg", "baz.jlso")
                @test !isfile(baz_path)
            end
        end
        @testset "Single" begin
            mktempdir() do path
                d = Dict(zip(
                    map(x -> Symbol(randstring(4)), 1:10),
                    map(x -> rand(10), 1:10)
                ))
                Checkpoints.config("TestPkg.baz", path)

                TestPkg.baz(d)

                mod_path = joinpath(path, "TestPkg")
                @test isdir(mod_path)

                baz_path = joinpath(path, "TestPkg", "baz.jlso")
                @test isfile(baz_path)

                data = JLSO.load(baz_path)
                for (k, v) in data
                    @test v == d[Symbol(k)]
                end
            end
        end
        @testset "Multi" begin
            mktempdir() do path
                a = Dict(zip(
                    map(x -> Symbol(randstring(4)), 1:10),
                    map(x -> rand(10), 1:10)
                ))
                b = rand(10)
                Checkpoints.config("TestPkg.qux" , path)

                TestPkg.qux(a, b)

                mod_path = joinpath(path, "TestPkg")
                @test isdir(mod_path)

                qux_a_path = joinpath(path, "TestPkg", "qux_a.jlso")
                @test isfile(qux_a_path)

                qux_b_path = joinpath(path, "TestPkg", "qux_b.jlso")
                @test isfile(qux_b_path)

                data = JLSO.load(qux_a_path)
                for (k, v) in data
                    @test v == a[Symbol(k)]
                end

                data = JLSO.load(qux_b_path)
                @test data["data"] == b
            end
        end
    end
    include("deprecated.jl")
end
