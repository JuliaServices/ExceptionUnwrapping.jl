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

            @test is_wrapped_exception(e)
            @test unwrap_exception(e) isa TaskFailedException
            @test unwrap_exception_to_root(e) isa ErrorException
            @test has_wrapped_exception(e, ErrorException)
            @test has_wrapped_exception(e, TaskFailedException)
            @test has_wrapped_exception(e, ArgumentError) == false
            @test unwrap_exception_until(e, ErrorException) isa ErrorException
            @test_throws UnwrappedExceptionNotFound{ArgumentError} unwrap_exception_until(e, ArgumentError) isa ErrorException
        end
    end

    @testset "Wrapped CapturedException" begin
        e = CapturedException(ErrorException("oh no"), backtrace())
        @test unwrap_exception(e) == ErrorException("oh no")
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

        @test is_wrapped_exception(e2)
        @test !is_wrapped_exception(e1)
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

        @test is_wrapped_exception(e3)
        @test is_wrapped_exception(e2)
        @test !is_wrapped_exception(e1)
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

@testset "allocations" begin
    t = @async throw(ArgumentError("foo"))
    try wait(t) catch end
    TE = TaskFailedException(t)

    # Precompile it once
    @test ExceptionUnwrapping.has_wrapped_exception(TE, ArgumentError) == true
    @test ExceptionUnwrapping.unwrap_exception(TE) isa ArgumentError

    # Test no allocations
    @test @allocated(ExceptionUnwrapping.has_wrapped_exception(TE, ArgumentError)) == 0
    @test @allocated(ExceptionUnwrapping.unwrap_exception(TE)) == 0

    # Test that there's nothing being compiled, even for novel types
    @eval struct Foo <: Exception end
    e = Foo()
    @test @allocated(ExceptionUnwrapping.has_wrapped_exception(e, ArgumentError)) == 0
    @test @allocated(ExceptionUnwrapping.has_wrapped_exception(e, Foo)) == 0
    @test @allocated(ExceptionUnwrapping.unwrap_exception(e)) == 0
end



end # module
