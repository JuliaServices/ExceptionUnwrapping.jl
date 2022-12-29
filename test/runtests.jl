using Test

@testset "ExceptionUnwrapping.jl" begin
    include("ExceptionUnwrapping.jl")
end
@testset "test_throws_wrapped.jl" begin
    include("test_throws_wrapped.jl")
end
@testset "exception_summary.jl" begin
    include("exception_summary.jl")
end
