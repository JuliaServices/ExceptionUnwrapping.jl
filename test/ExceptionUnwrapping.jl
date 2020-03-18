module ExceptionUnwrappingTest

using Test
using ExceptionUnwrapping
using ExceptionUnwrapping: UnwrappedExceptionNotFound


# TaskFailedException is available in Julia 1.3+
if VERSION >= v"1.3.0-"
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
end

struct MyWrappedException{T}
    wrapped_exception::T
end
# Implement the ExceptionUnwrapping API:
ExceptionUnwrapping.unwrap_exception(e::MyWrappedException) = e.wrapped_exception

@testset "Custom Exception Types" begin
    e1 = ErrorException("1")
    e2 = MyWrappedException(ErrorException("1"))
    try
        throw(e2)
    catch e
        @assert e === e2
        @assert (e isa ErrorException) == false
        @assert e isa MyWrappedException

        @test unwrap_exception(e) === e1
        @test unwrap_exception_to_root(e) === e1
        @test has_wrapped_exception(e, ErrorException)
        @test has_wrapped_exception(e, MyWrappedException)
        @test has_wrapped_exception(e, ArgumentError) == false
        @test unwrap_exception_until(e, ErrorException) === e1
        @test_throws UnwrappedExceptionNotFound{ArgumentError} unwrap_exception_until(e, ArgumentError) isa ErrorException
    end
end

struct MyWrappedException2
    exc::Any
end
# Implement the ExceptionUnwrapping API:
ExceptionUnwrapping.unwrap_exception(e::MyWrappedException2) = e.exc

@testset "Multiple Layers" begin
    e1 = ErrorException("1")
    e2 = MyWrappedException(ErrorException("1"))
    e3 = MyWrappedException2(MyWrappedException(ErrorException("1")))
    try
        throw(e3)
    catch e
        @assert e === e3

        @test unwrap_exception(e) === e2
        @test unwrap_exception(unwrap_exception(e)) === e1
        @test unwrap_exception_to_root(e) === e1
        @test has_wrapped_exception(e, ErrorException)
        @test has_wrapped_exception(e, MyWrappedException)
        @test has_wrapped_exception(e, MyWrappedException2)
        @test unwrap_exception_until(e, MyWrappedException) === e2
        @test unwrap_exception_until(e, ErrorException) === e1
    end
end


end # module
