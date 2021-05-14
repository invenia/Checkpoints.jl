using Checkpoints
using Compat # for only
using Distributed
using Test
using AWSCore
using FilePathsBase
using JLSO
using Random
using Tables: Tables

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

    @testset "deprecated tags syntax" begin
        mktempdir() do path
            Checkpoints.config("TestPkg.deprecated", path)
            TestPkg.deprecated_checkpoint_syntax()
            @test isfile(joinpath(path, "date=2017-01-01", "TestPkg", "deprecated.jlso"))
        end
    end

    @testset "Context tags" begin
        mktempdir() do path
            @everywhere begin
                path=$path
                Checkpoints.config("TestPkg.bar", path)
            end

            @testset "single context tags" begin
                with_checkpoint_tags(:tag => "a") do
                    TestPkg.bar(a)
                end
                @test isfile(joinpath(path, "tag=a", "date=2017-01-01", "TestPkg", "bar.jlso"))
            end

            @testset "nested tags" begin
                @testset "different tags" begin
                    with_checkpoint_tags(:first => "first") do
                        with_checkpoint_tags(:second => "second") do
                            TestPkg.bar(a) # both first and second
                        end
                        TestPkg.bar(a) # only first
                    end
                    @test isfile(joinpath(path, "first=first", "second=second", "date=2017-01-01", "TestPkg", "bar.jlso"))
                    @test isfile(joinpath(path, "first=first", "date=2017-01-01", "TestPkg", "bar.jlso"))
                end

                @testset "duplicate context tags" begin
                    with_checkpoint_tags(:same => "outer") do
                        with_checkpoint_tags(:same => "inner") do
                            TestPkg.bar(a)
                        end
                        TestPkg.bar(a)
                    end
                    @test isfile(joinpath(path, "same=outer", "same=inner", "date=2017-01-01", "TestPkg", "bar.jlso"))
                    @test isfile(joinpath(path, "same=outer", "date=2017-01-01", "TestPkg", "bar.jlso"))
                end

                @testset "same context and package tags" begin
                    with_checkpoint_tags(:date=>"context") do
                        TestPkg.bar(a)
                    end
                    @test isfile(joinpath(path, "date=context", "date=2017-01-01", "TestPkg", "bar.jlso"))
                end
            end

            @testset "multi-process context tags" begin
                @test Distributed.nworkers() > 1
                pmap(["a", "b", "c", "d", "e", "f"]) do tag
                    with_checkpoint_tags(:context_tag => tag) do
                        sleep(rand()) # to make sure not overwritten in the meantime
                        @test Dict(Checkpoints.CONTEXT_TAGS[]...)[:context_tag] == tag
                        TestPkg.bar(a)
                    end
                end
                @test isfile(joinpath(path, "context_tag=e", "date=2017-01-01", "TestPkg", "bar.jlso"))
            end

            @testset "multithreaded" begin
                if Threads.nthreads() > 1
                    Threads.@threads for t = 1:10
                        with_checkpoint_tags(:thread => t) do
                            sleep(rand())
                            @test Dict(Checkpoints.CONTEXT_TAGS[]...)[:thread] == t
                            TestPkg.bar(a)
                        end
                    end
                    @test isfile(joinpath(path, "thread=8", "date=2017-01-01", "TestPkg", "bar.jlso"))
                else
                    @warn("Skipping multi-threading tests. Start with `julia -t n` for n threads.")
                end
            end
        end
    end

    include("indexing.jl")

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
