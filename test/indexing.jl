@testset "indexing" begin
    @testset "normal use case" begin
        mktempdir() do path
            Checkpoints.config("TestPkg.bar", path)
            TestPkg.bar([1,2,3])

            index = index_checkpoint_files(path)
            @test Tables.istable(Tables.columntable(index))
            @test length(index) == 1
            entry = only(index)
            @test tags(entry) == (:date=>"2017-01-01",)
            @test entry.date == "2017-01-01"
            @test prefixes(entry) == ("TestPkg",)
            @test checkpoint_name(entry) == "bar"
            @test ==(
                checkpoint_path(entry),
                Path(joinpath(path, "date=2017-01-01", "TestPkg", "bar.jlso"))
            )
        end
    end

    @testset "files not saved by Checkpoints.jl" begin
        mktempdir(SystemPath) do path
            Checkpoints.config("TestPkg.bar", path)
            TestPkg.bar([1,2,3])
            other_file = joinpath(path, "date=2021-01-01", "other_file.txt")
            mkpath(dirname(other_file))
            write(other_file, 1)
            index = index_files(path)
            @test length(index) == 2
            @test other_file == only(checkpoint_path(entry) for entry in index if entry.date == "2021-01-01")
        end
    end

    @testset "clashing tags" begin
        mktempdir() do path
            Checkpoints.config("TestPkg.bar", path)
            with_checkpoint_tags(:tags=>"clash", :a=>"a1", :b=>"b1", :a=>"a2") do
                TestPkg.bar([1,2,3])
            end

            index = index_checkpoint_files(path)
            @test_throws ErrorException Tables.istable(Tables.columntable(index))
            @test length(index) == 1
            entry = only(index)
            @test ==(
                tags(entry),
                (:tags=>"clash", :a=>"a1", :b=>"b1", :a=>"a2", :date=>"2017-01-01",)
            )
            @test entry.date == "2017-01-01"

            @test_throws ErrorException entry.a
            @test_throws ErrorException entry.tags
        end
    end
end
