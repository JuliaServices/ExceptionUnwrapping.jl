using Test
using ExceptionUnwrapping: summarize_current_exceptions, TITLE, INDENT_LENGTH, SEPARATOR
import ExceptionUnwrapping

function get_current_exception_string()
    str = sprint(summarize_current_exceptions)
    # check this here since it applies to every string
    @test startswith(str, TITLE)
    return str
end

# Similar to Base.occursin() except this function accepts a count. Requires `count`
# allocations, so not the most efficient way to check.
# (Dropped the type-signature since AbstractPattern isn't available in julia 1.3-)
function occursin_n(needle, haystack, count::Int)
    for _ in 1:count
        new_haystack = replace(haystack, needle => "", count=1)
        @test haystack != new_haystack
        haystack = new_haystack
    end
end

@testset "TaskFailedException" begin
    local str
    ch = Channel{Nothing}() do ch
        @assert false
        put!(ch, nothing)
    end
    try
        take!(ch)
    catch
        str = get_current_exception_string()
    end

    @test occursin("AssertionError: false", str)
end

@testset "CompositeException" begin
    local str
    try
        @sync begin
            Threads.@spawn @assert false
            Threads.@spawn @assert !true
            Threads.@spawn @assert true
        end
    catch
        str = get_current_exception_string()
    end

    @test occursin("CompositeException (2 tasks):", str)
    @test occursin("AssertionError: false", str)
    @test occursin("AssertionError: !true", str)
end

@testset "Chained Causes in TaskFailedException" begin
    local str
    ch = Channel{Nothing}() do ch
        try
            @assert false
            put!(ch, nothing)
        catch
            fetch(
                Threads.@spawn error("INSIDE CATCH BLOCK")
            )
        end
    end
    try
        fetch(
            Threads.@spawn take!(ch)
        )
    catch
        str = get_current_exception_string()
    end

    @test occursin("AssertionError: false", str)
    @test occursin("which caused:\nINSIDE CATCH BLOCK", str)
end

@testset "Duplicates" begin
    local str
    try
        ch = Channel() do ch
            @assert 1 == 0
        end
        @time @sync begin
            Threads.@spawn take!(ch)
            Threads.@spawn take!(ch)
            Threads.@spawn take!(ch)
        end
    catch
        str = get_current_exception_string()
    end

    @test occursin("CompositeException (3 tasks):", str)
    # check that message appears thrice
    @test occursin(Regex(
        """
         1. AssertionError: 1 == 0(\n|.)*
         --
         2. AssertionError: 1 == 0(\n|.)*
         --
         3. AssertionError: 1 == 0
        """), str)
end

@testset "More caused by" begin
    local str
    try
        try
            @sync begin
                Threads.@spawn try
                    @assert false
                catch
                    @assert 2+2 == 3
                end
            end
        catch
            @assert 1-1 == 4
        end
    catch
        str = get_current_exception_string()
    end

    @test !occursin("CompositeException", str)
    @test occursin("\nAssertionError: false\n", str)
    @test occursin("\nwhich caused:\nAssertionError: 2 + 2 == 3\n", str)
    @test occursin("\nwhich caused:\nAssertionError: 1 - 1 == 4\n", str)
end

function replace_file_line(str::AbstractString)
    replace(str, r"@ Main (\S*)" => "@ Main FILE:LINE")
end

# Exception with multi-line show:
struct MultiLineException x::Any end
Base.showerror(io::IO, e::MultiLineException) = print(io, "MultiLineException(\n    $(e.x)\n)")

throw_multiline(x) = throw(MultiLineException(x))

@testset "multiline exception" begin
    local str
    try
        try
            @sync begin
                Threads.@spawn try
                    throw_multiline(0x0)  # use UInt8 for consistent printing in CI
                catch
                    throw_multiline(0x1)
                end
                Threads.@spawn throw_multiline(0x2)
            end
        catch
            throw_multiline(0x3)
        end
    catch
        str = get_current_exception_string()
    end

    @test replace_file_line(str) === """
    === EXCEPTION SUMMARY ===

    CompositeException (2 tasks):
     1. MultiLineException(
            0
        )
         [1] throw_multiline(x::UInt8)
           @ Main FILE:LINE

        which caused:
        MultiLineException(
            1
        )
         [1] throw_multiline(x::UInt8)
           @ Main FILE:LINE
     --
     2. MultiLineException(
            2
        )
         [1] throw_multiline(x::UInt8)
           @ Main FILE:LINE

    which caused:
    MultiLineException(
        3
    )
     [1] throw_multiline(x::UInt8)
       @ Main FILE:LINE
    """
end


# Custom Wrapped Exception Types
struct ContextException
    inner::Exception
    context_msg::String
end
# This entire string should be *ignored* by get_current_exception_string()
function Base.showerror(io::IO, e::ContextException)
    print(io, "Caught $(typeof(e.inner)) while $(e.context_msg):\n")
    Base.showerror(io, e.inner)
end
ExceptionUnwrapping.unwrap_exception(e::ContextException) = e.inner

# (Use uints to have consistent test results across architectures)
@noinline do_the_assertion1(x) = @assert x === 0x1
@noinline do_the_assertion2(x) = @assert x === 0x2
@noinline do_the_assertion3(x) = @assert x === 0x3
function check_val(x)
    @sync begin
        Threads.@spawn try
            do_the_assertion1(x)
        catch
            do_the_assertion2(x)
        end
        Threads.@spawn do_the_assertion3(x)
    end
end

@testset "wrapped exception" begin
    str = try
        try
            # Do the thing
            check_val(0x0)
        catch e
            rethrow(ContextException(e, "Performing sync-spawn to 'Do the thing.'"))
        end
    catch
        get_current_exception_string()
    end

    @test replace_file_line(str) === """
    === EXCEPTION SUMMARY ===

    CompositeException (2 tasks):
     1. AssertionError: x === 0x01
         [1] do_the_assertion1(x::UInt8)
           @ Main FILE:LINE

        which caused:
        AssertionError: x === 0x02
         [1] do_the_assertion2(x::UInt8)
           @ Main FILE:LINE
     --
     2. AssertionError: x === 0x03
         [1] do_the_assertion3(x::UInt8)
           @ Main FILE:LINE
    """
end


