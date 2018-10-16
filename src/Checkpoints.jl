"""
    Checkpoints

A very minimal module for defining checkpoints or save location in large codebase with
the ability to configure how those checkpoints save data externally
(similar to how Memento.jl works for logging).
"""
module Checkpoints

using AWSCore
using AWSS3
# using FileIO
using Memento
using Mocking

using Compat: @__MODULE__

export JLSO

const CHECKPOINTS = Dict{String, Function}()
const LOGGER = getlogger(@__MODULE__)

__init__() = Memento.register(LOGGER)

include("JLSO.jl")

# function filesave(prefix; ext="jld2")
#     function f(label, data)
#         parts = split(label, '.')
#         parts[end] = string(parts[end], '.', ext)
#         path = joinpath(prefix, parts...)
#         save(path, data)
#     end

#     return f
# end

# function s3save(config::AWSConfig=AWSCore.aws_config(), bucket, prefix)
#     verinfo = sprint(versioninfo, true)
#     image = ""

#     # If we're running on AWS batch then store the docker_image
#     if haskey(ENV, "AWS_BATCH_JOB_ID")
#         job_id = ENV["AWS_BATCH_JOB_ID"]
#         response = @mock describe_jobs(Dict("jobs" => [job_id]))

#         if length(response["jobs"]) > 0
#             image = first(response["jobs"])["container"]["image"]
#         else
#             warn(LOGGER, "No jobs found with id: $job_id.")
#         end
#     end

#     function f(label, data)
#         fileobj = Dict(
#             "image" => image,
#             "versioninfo" => sprint(verinfo,
#             "data" => data,
#         )

#         parts = split(label, '.')
#         parts[end] = string(parts[end], '.jso')
#         key = join(vcat([prefix], parts), "/")
#         s3_put(config, bucket, key, sprint(serialize, fileobj))
#     end

#     return f
# end

# function s3load(config::AWSConfig=AWSCore.aws_config(), bucket, key)
#     obj = s3_get(aws, bucket, key)

# end

# function register(labels::String...)
#     for l in labels
#         if haskey(CHECKPOINTS, l)
#             warn(LOGGER, "$l has already registered")
#         else
#             CHECKPOINTS[l] = (k, v) -> nothing
#         end
#     end
# end

# function config(backend::Callable, labels::String...)
#     for l in labels
#         if haskey(CHECKPOINTS, l)
#             CHECKPOINTS[l] = backend
#         else
#             warn(LOGGER, "$l is not a registered checkpoint label")
#         end
#     end
# end

# checkpoint(label::String, x) = CHECKPOINTS[label](label, x)

# labels() = collect(keys(CHECKPOINTS))

end  # module
