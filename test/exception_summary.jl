using Test
using ExceptionUnwrapping: summarize_current_exceptions, TITLE, INDENT_LENGTH, SEPARATOR

function get_current_exception_string()
    io = IOBuffer()
    summarize_current_exceptions(io)
    str = String(take!(io))
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

    sep_indent = ' '^(INDENT_LENGTH-3)
    error_msg = "AssertionError: 1 == 0\n"
    sep = sep_indent * SEPARATOR * '\n'
    @test occursin("CompositeException (3 tasks):", str)
    # check that message appears thrice
    @test occursin(Regex(" 1. $error_msg(\n|.)*$sep 2. $error_msg(\n|.)*$sep 3. $error_msg"), str)
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

    indent = ' '^INDENT_LENGTH
    error_msg = indent * "AssertionError: 1 == 0\n"
    @test occursin("CompositeException (1 tasks):", str)
    @test occursin("\n 1. AssertionError: false\n", str)
    @test occursin("\n    which caused:\n    AssertionError: 2 + 2 == 3\n", str)
    @test occursin("\nwhich caused:\nAssertionError: 1 - 1 == 4\n", str)
end

function replace_file_line(str)
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
                    throw_multiline(0)
                catch
                    throw_multiline(1)
                end
                Threads.@spawn throw_multiline(2)
            end
        catch
            throw_multiline(3)
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
         [1] throw_multiline(x::Int64)
           @ Main FILE:LINE

        which caused:
        MultiLineException(
            1
        )
         [1] throw_multiline(x::Int64)
           @ Main FILE:LINE
     --
     2. MultiLineException(
            2
        )
         [1] throw_multiline(x::Int64)
           @ Main FILE:LINE

    which caused:
    MultiLineException(
        3
    )
     [1] throw_multiline(x::Int64)
       @ Main FILE:LINE
    """
end

