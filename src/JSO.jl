"""
A julia serialized object (JSO) file format for storing checkpoint data.

# Structure
```
version=1.0
image=xxxxxxxxxxxx.dkr.ecr.us-east-1.amazonaws.com/myrepository:latest
systeminfo=Julia Version 0.6.4
---
var1|5=[0x35, 0x10, 0x01, 0x04, 0x44],
var2|8=[...]
```
WARNING: The serialized object data is using julia's builtin serialization format which is
not intended for long term storage. As a result, we're storing the serialized object data
in a json file which should also be able to load the docker image and versioninfo to allow
reconstruction.
"""
module JSO

using AWSCore
using AWSS3
using Compat
using Memento
using Mocking

using Compat.Serialization

const LOGGER = getlogger(@__MODULE__)
const VALID_VERSIONS = (v"1.0", v"2.0")

# Cache of the versioninfo and image, so we don't compute these every time.
const _CACHE = Dict{Symbol, String}(
    :VERSIONINFO => "",
    :IMAGE => "",
)

__init__() = Memento.register(LOGGER)

struct InvalidFileError <: Exception
    msg::String     # The msg to display
    hpos::Int       # Start position in IO
    epos::Int       # Failure position in IO
end

struct JSOFile
    version::VersionNumber
    image::String
    systeminfo::String
    objects::Dict{String, Vector{UInt8}}
end

function JSOFile(
    data::Dict{String, <:Any};
    image=_image(),
    systeminfo=_versioninfo(),
    version=v"1.0"
)
    _versioncheck(version)

    objects = map(data) do t
        varname, vardata = t
        io = IOBuffer()
        serialize(io, vardata)
        return varname => take!(io)
    end |> Dict

    return JSOFile(version, image, systeminfo, objects)
end

JSOFile(data) = JSOFile(Dict("data" => data))
JSOFile(data::Pair...) = JSOFile(Dict(data...))

function Base.:(==)(a::JSOFile, b::JSOFile)
    return (
        a.version == b.version &&
        a.image == b.image &&
        a.systeminfo == b.systeminfo &&
        a.objects == b.objects
    )
end

function Base.write(io::IO, jso::JSOFile)
    # Write the header info
    header = "version=$(jso.version)\nimage=$(jso.image)\nsysteminfo=$(jso.systeminfo)\n---"
    write(io, header)

    for (name, data) in jso.objects
        nb = length(data)
        write(io, "\n$name|$nb=")
        write(io, data)
    end
end

function Base.read(io::IO, ::Type{JSOFile})
    version = v"0.0.0"
    img = ""
    systeminfo = ""
    objects = Dict{String, Vector{UInt8}}()
    hpos = position(io)

    version = read_version(io, hpos)
    img = read_image(io, hpos)
    systeminfo = read_sysinfo(io, hpos)

    ################################
    # Extract each stored variable
    ################################
    varname = Compat.readuntil(io, "="; keep=true)
    while !isempty(varname)
        if !startswith(varname, "\n")
            error(
                LOGGER,
                InvalidFileError(
                    "Expected newline before variable ($varname).",
                    hpos,
                    position(io)
                )
            )
        end

        # Strip any whitespace and '='
        varname = strip(varname[1:end-1])
        varname, nb = split(varname, '|')
        objects[varname] = read(io, parse(Int, nb))

        varname = Compat.readuntil(io, "="; keep=true)
    end

    return JSOFile(version, img, systeminfo, objects)
end

function Base.getindex(jso::JSOFile, name::String)
    try
        return deserialize(IOBuffer(jso.objects[name]))
    catch e
        warn(LOGGER, e)
        return jso.objects[name]
    end
end

# save(io::IO, data) = write(io, JSOFile(data))
# load(io::IO, data) = read(io, JSOFile(data))

#########################################
# Utility function for reading JSO file
########################################
"""
Extract and validate the format version
"""
function read_version(io, hpos)
    str = Compat.readuntil(io, "version="; keep=true)
    if isempty(str)
        error(
            LOGGER,
            InvalidFileError("JSO file does not contain 'version='", hpos, position(io))
        )
    end

    if !startswith(str, "version=")
        error(
            LOGGER,
            InvalidFileError("JSO file did not start with 'version='", hpos, position(io))
        )
    end

    str = Compat.readuntil(io, "image="; keep=true)
    if isempty(str)
        error(
            LOGGER,
            InvalidFileError("JSO file does not contain 'image='", hpos, position(io))
        )
    end

    tokenized = split(str)
    if length(tokenized) == 1
        error(
            LOGGER,
            InvalidFileError("A version number was not provided", hpos, position(io))
        )
    end

    version = VersionNumber(first(tokenized))
    _versioncheck(version)

    return version
end

"""
Extract the docker image
"""
function read_image(io, hpos)
    str = Compat.readuntil(io, "systeminfo="; keep=true)
    if isempty(str)
        error(
            LOGGER,
            InvalidFileError("JSO file does not contain 'systeminfo='", hpos, position(io))
        )
    end

    tokenized = split(str)
    if length(tokenized) == 1
        debug(LOGGER, "No docker image specified")
        return ""
    else
        return first(tokenized)
    end
end

"""
Extract the system info
"""
function read_sysinfo(io, hpos)
    str = Compat.readuntil(io, "\n---"; keep=true)
    if isempty(str)
        error(
            LOGGER,
            InvalidFileError("JSO file missing header separator '---'", hpos, position(io))
        )
    end

    return str[1:end-4]
end

#######################################
# Functions for lazily evaluating the #
# VERSIONINFO and IMAGE at runtime    #
#######################################
function _versioninfo()
    if isempty(_CACHE[:VERSIONINFO])
        global _CACHE[:VERSIONINFO] = sprint(versioninfo, true)
    end

    return _CACHE[:VERSIONINFO]
end

function _image()
    if isempty(_CACHE[:IMAGE]) && haskey(ENV, "AWS_BATCH_JOB_ID")
        job_id = ENV["AWS_BATCH_JOB_ID"]
        response = @mock describe_jobs(Dict("jobs" => [job_id]))

        if length(response["jobs"]) > 0
            global _CACHE[:IMAGE] = first(response["jobs"])["container"]["image"]
        else
            warn(LOGGER, "No jobs found with id: $job_id.")
        end
    end

    return _CACHE[:IMAGE]
end

function _versioncheck(version::VersionNumber)
    supported = first(VALID_VERSIONS) <= version < last(VALID_VERSIONS)
    supported || error(LOGGER, ArgumentError(
        string(
            "Unsupported version ($version). ",
            "Expected a value between ($VALID_VERSIONS)."
        )
    ))
end

end
