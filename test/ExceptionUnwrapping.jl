using Test
using ExceptionUnwrapping
using ExceptionUnwrapping: UnwrappedExceptionNotFound

@testset "Wrapped TaskFailedException" begin
    try
        fetch(@async fetch(@async error("hi")))
    catch e
        @assert (e isa ErrorException) == false
        @assert e isa TaskFailedException
        @test unwrap_exception(e) isa TaskFailedException
        @test unwrap_exception_to_root(e) isa ErrorException
        @test has_wrapped_exception(e, ErrorException)
        @test has_wrapped_exception(e, TaskFailedException)
        @test has_wrapped_exception(e, ArgumentError) == false
        @test unwrap_exception_until(e, ErrorException) isa ErrorException
        @test_throws UnwrappedExceptionNotFound{ArgumentError} unwrap_exception_until(e, ArgumentError) isa ErrorException
    end
end
