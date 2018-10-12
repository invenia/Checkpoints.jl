using Compat
using Compat.Test
using Compat.Dates
using Checkpoints
using Checkpoints.JSO: JSOFile, LOGGER, InvalidFileError
using Memento
using Memento.Test

# To test different types from common external packages
using DataFrames
using Distributions
using TimeZones

@testset "JSO" begin
    # Serialize "Hello World!" on julia 0.5.2 (not supported)
    img = JSO._image()
    sysinfo = JSO._versioninfo()
    hw_5 = UInt8[0x26, 0x15, 0x87, 0x48, 0x65, 0x6c, 0x6c, 0x6f, 0x20, 0x57, 0x6f, 0x72, 0x6c, 0x64, 0x21]

    datas = Dict(
        "String" => "Hello World!",
        "Vector" => [0.867244, 0.711437, 0.512452, 0.863122, 0.907903],
        "Matrix" => [0.400348 0.892196 0.848164; 0.0183529 0.755449 0.397538; 0.870458 0.0441878 0.170899],
        "DateTime" => DateTime(2018, 1, 28),
        "ZonedDateTime" => ZonedDateTime(2018, 1, 28, tz"America/Chicago"),
        "DataFrame" => DataFrame(
            :a => collect(1:5),
            :b => [0.867244, 0.711437, 0.512452, 0.863122, 0.907903],
            :c => ["a", "b", "c", "d", "e"],
            :d => [true, true, false, false, true],
        ),
        "Distribution" => Normal(50.2, 4.3),
    )

    @testset "JSOFile" begin
        @testset "$k" for (k, v) in datas
            jso = JSOFile(v)
            io = IOBuffer()
            bytes = serialize(io, v)
            expected = take!(io)

            @test jso.objects["data"] == expected
        end
    end

    @testset "reading and writing" begin
        @testset "$k" for (k, v) in datas
            io = IOBuffer()
            orig = JSOFile(v)
            write(io, orig)

            seekstart(io)

            result = read(io, JSOFile)
            @test result == orig
        end


        @testset "empty io" begin
            @test_throws(LOGGER, InvalidFileError, read(IOBuffer(), JSOFile))
        end

        @testset "corrupted start" begin
            @test_throws(
                LOGGER,
                InvalidFileError,
                read(IOBuffer("blah\nversion=1.0"), JSOFile)
            )
        end

        @testset "empty version" begin
            @test_throws(
                LOGGER,
                InvalidFileError,
                read(IOBuffer("version=\nimage="), JSOFile)
            )
        end

        @testset "invalid version" begin
            jso = JSOFile("Hello World!")
            io = IOBuffer()
            header = "version=0.0\nimage=\nsysteminfo=$(jso.systeminfo)\n---"
            write(io, header)

            for (name, data) in jso.objects
                nb = length(data)
                write(io, "\n$name|$nb=")
                write(io, data)
            end

            seekstart(io)

            # read(io, JSOFile)
            @test_throws(
                LOGGER,
                ArgumentError,
                read(io, JSOFile)
            )
        end

        @testset "missing image" begin
            @test_throws(
                LOGGER,
                InvalidFileError,
                read(IOBuffer("version=1.0\nsysteminfo="), JSOFile)
            )
        end

        @testset "empty image" begin
            jso = JSOFile("Hello World!")
            io = IOBuffer()
            write(io, jso)

            seekstart(io)

            setlevel!(LOGGER, "debug")
            @test_log(
                LOGGER,
                "debug",
                "No docker image specified",
                read(io, JSOFile)
            )
        end

        @testset "invalid nb" begin
            jso = JSOFile("Hello World!")
            io = IOBuffer()
            header = "version=$(jso.version)\nimage=$(jso.image)\nsysteminfo=$(jso.systeminfo)\n---"
            write(io, header)
            nb = length(jso.objects["data"]) - 1
            write(io, "\ndata|$nb=")
            write(io, jso.objects["data"])

            seekstart(io)

            # This will cause the parsing our variable names to fail
            result = @test_throws(
                LOGGER,
                InvalidFileError,
                read(io, JSOFile)
            )

            io = IOBuffer()
            write(io, header)
            nb = length(jso.objects["data"]) + 1
            write(io, "\ndata|$nb=")
            write(io, jso.objects["data"])

            seekstart(io)

            result = read(io, JSOFile)

            @test haskey(result.objects, "data")
            result["data"]
        end
    end

    @testset "deserialization" begin
        # Test deserialization works
        @testset "data - $k" for (k, v) in datas
            jso = JSOFile(v)
            @test jso["data"] == v
        end

        @testset "unsupported julia version" begin
            jso = JSOFile(v"1.0", img, sysinfo, Dict("data" => hw_5))

            # Test failing to deserialize data because of incompatible julia versions
            # will will return the raw bytes
            result = @test_warn(LOGGER, r"MethodError*", jso["data"])
            @test result == hw_5
        end

        @testset "missing module" begin
            # We need to load and use AxisArrays on another process to cause the
            # deserialization error
            pnum = first(addprocs(1))

            try
                # We need to do this separately because there appears to be a race
                # condition on AxisArrays being loaded.
                f = @spawnat pnum begin
                    @eval Main using AxisArrays
                end

                fetch(f)

                f = @spawnat pnum begin
                    io = IOBuffer()
                    serialize(
                        io,
                        AxisArray(
                            rand(20, 10),
                            Axis{:time}(14010:10:14200),
                            Axis{:id}(1:10)
                        )
                    )
                    return io
                end

                io = fetch(f)
                bytes = take!(io)
                jso = JSOFile(v"1.0", img, sysinfo, Dict("data" => bytes))

                # Test failing to deserailize data because of missing modules will
                # still return the raw bytes
                result = @test_warn(LOGGER, r"UndefVarError*", jso["data"])
                @test result == bytes
            finally
                rmprocs(pnum)
            end
        end
    end
end
