using Test

@testset "ExceptionUnwrapping.jl" begin
    include("ExceptionUnwrapping.jl")
end
@testset "test_throws_wrapped.jl" begin
    include("test_throws_wrapped.jl")
end
@static if VERSION >= v"1.7.0-"
    @testset "exception_summary.jl" begin
        include("exception_summary.jl")
    end
end
