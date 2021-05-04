using Checkpoints
using Distributed
using Test
using AWSCore
using FilePathsBase
using JLSO
using Random

using AWSCore: AWSConfig
using AWSS3: S3Path, s3_put, s3_list_buckets, s3_create_bucket

Distributed.addprocs(5)
@everywhere using Checkpoints

@testset "Checkpoints" begin
    @everywhere include("testpkg.jl")

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
            @test data[:x] == x
            @test data[:y] == y
        end
    end

    @testset "Application-level tags" begin
        @everywhere begin
            path = "testpath"
            Checkpoints.config("TestPkg.tagscheck", path)
        end

        # run without the application-level checkpoints
        TestPkg.tagscheck(x)
        @test isfile(joinpath(path, "package_tag=1", "TestPkg", "tagscheck.jlso"))

        # run with the application-level checkpoints
        for app_tag in ["a", "b"]
            Checkpoints.application_tags(:app_tag => app_tag)
            TestPkg.tagscheck(x)
        end
        @test isfile(joinpath(path, "app_tag=a", "package_tag=1", "TestPkg", "tagscheck.jlso"))

        # run concurrently with the application-level checkpoints
        @test Distributed.nworkers() > 1
        pmap(["a", "b", "c", "d", "e", "f"]) do app_tag
            Checkpoints.application_tags(:app_tag => app_tag)
            sleep(rand()) # make sure not overwritten in the meantime
            @test Checkpoints.application_tags()[:app_tag] == app_tag
            TestPkg.tagscheck(x)
        end
        @test isfile(joinpath(path, "app_tag=d", "package_tag=1", "TestPkg", "tagscheck.jlso"))

        Checkpoints.application_tags(nothing)
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
                @test JLSO.load(IOBuffer(read(expected_path)))[:data] == a
            end
        end
    else
        @warn("Skipping AWS S3 tests. Set `ENV[\"LIVE\"] = true` to run.")
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
                @test data[:data] == b
            end
        end
    end
end
