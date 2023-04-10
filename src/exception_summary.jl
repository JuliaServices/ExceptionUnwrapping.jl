###############
#=
# TODOs
- Call it from our codebase
- Unit tests
- Seen set, for deduplication
=#

# Consider adding a _summarize_exception() overload for DistributedException
#     Pros: less noise
#     Cons: possibly hiding intermediate exceptions that might have been helpful to see.

const TITLE = "=== EXCEPTION SUMMARY ==="
const SEPARATOR = "--"
const INDENT_LENGTH = 4

"""
    summarize_current_exceptions(io::IO = Base.stderr, task = current_task())

Print a summary of the [current] task's exceptions to `io`.

This is particularly helpful in cases where the exception stack is large, the backtraces are
large, and CompositeExceptions with multiple parts are involved.
"""
function summarize_current_exceptions(io::IO = Base.stderr, task::Task = current_task())
    _indent_print(io, TITLE, '\n'; color=Base.info_color())
    println(io)
    _summarize_task_exceptions(io, task)
    return nothing
end

function _indent_print(io::IO, x...; color=:normal, prefix = nothing)
    indent = get(io, :indent, 0)
    if prefix !== nothing
        ind = max(0, indent - length(prefix))
        printstyled(io, " "^ind, prefix, x...; color=color)
    else
        printstyled(io, " "^indent, x...; color=color)
    end
end

function _indent_println(io::IO, x...; color=:normal, prefix = nothing)
    _indent_print(io, x..., "\n"; color=color, prefix=prefix)
end

function _indent_print(io::IO, io_src::IO; prefix = nothing)
    indent = get(io, :indent, 0)
    for (i, line) in enumerate(eachline(io_src))
        if prefix !== nothing && i == 1
            ind = max(0, indent - length(prefix))
            printstyled(io, " "^ind, prefix, line)
        else
            i !== 1 && println(io)
            printstyled(io, " "^indent, line)
        end
    end
end

function _summarize_task_exceptions(io::IO, task::Task; prefix = nothing)
    exception_stack = current_exceptions(task)
    for (i, (e, stack)) in enumerate(exception_stack)
        if i != 1
            # TODO: should the indention increase here?
            println(io)
            # Clear out the prefix after the first exception being printed
            prefix = nothing
            _indent_println(io, "which caused:"; color=Base.error_color())
        end
        _summarize_exception(io, e, stack, prefix = prefix)
    end
end

"""
    _summarize_exception(io::IO, e::TaskFailedException, _)
    _summarize_exception(io::IO, e::CompositeException, stack)
    _summarize_exception(io::IO, e::Exception, stack)

The secret sauce that lets us unwrap TaskFailedExceptions and CompositeExceptions, and
summarize the actual exception.

TaskFailedException simply wraps a task, so it is just unwrapped, and processed by
_summarize_task_exceptions().

CompositeException simply wraps a Vector of Exceptions. Each of the individual Exceptions is
summarized.

All other exceptions are printed via [`Base.showerror()`](@ref). The first stackframe in the
backtrace is also printed.
"""
function _summarize_exception(io::IO, e::TaskFailedException, _unused_ ; prefix = nothing)
    # recurse down the exception stack to find the original exception
    _summarize_task_exceptions(io, e.task, prefix = prefix)
end
function _summarize_exception(io::IO, e::CompositeException, stack; prefix = nothing)
    # If only one Exception is wrapped, go directly to it to avoid a level of indentation.
    if length(e) == 1
        return _summarize_exception(io, only(e.exceptions), stack; prefix = prefix)
    end

    _indent_println(io, "CompositeException (", length(e), " tasks):", prefix = prefix)
    indent = get(io, :indent, 0)
    io = IOContext(io, :indent => indent + INDENT_LENGTH)
    for (i, ex) in enumerate(e.exceptions)
        _summarize_exception(io, ex, stack; prefix = "$i. ")
        # print something to separate the multiple exceptions wrapped by CompositeException
        if i != length(e.exceptions)
            sep_io = IOContext(io, :indent => indent+1)
            _indent_println(sep_io, SEPARATOR)
        end
    end
end
# This is the overload that prints the actual exception that occurred.
function _summarize_exception(io::IO, exc, stack; prefix = nothing)
    # First, check that this exception isn't some other kind of user-defined
    # wrapped exception. We want to unwrap this layer as well, so that we are
    # printing just the true exceptions in the summary, not any exception
    # wrappers.
    if is_wrapped_exception(exc)
        unwrapped = unwrap_exception(exc)
        return _summarize_exception(io, unwrapped, stack; prefix)
    end
    # Otherwise, we are at the fully unwrapped exception, now.

    indent = get(io, :indent, 0)  # used for print_stackframe

    # Print the unwrapped exception.
    exc_io = IOBuffer()
    Base.showerror(exc_io, exc)
    seekstart(exc_io)
    # Print all lines of the exception indented.
    _indent_print(io, exc_io; prefix = prefix)

    println(io)

    # Print the source line number of the where the exception occurred.
    # In order to save performance, only process the backtrace up until the first printable
    # frame. (Julia skips frames from the C runtime when printing backtraces.)
    local bt
    for i in eachindex(stack)
        bt = Base.process_backtrace(stack[i:i])
        if !isempty(bt)
            break
        end
    end
    # Now print just the very first frame we've collected:
    if isempty(bt)
        # A report was received about bt being a 0-element Vector. It's not clear why the
        # stacktrace is missing, but this should tide us over in the meantime.
        _indent_println(io, "no stacktrace available")
    else
        (frame, n) = bt[1]
        # borrowed from julia/base/errorshow.jl
        modulecolordict = copy(Base.STACKTRACE_FIXEDCOLORS)
        modulecolorcycler = Iterators.Stateful(Iterators.cycle(Base.STACKTRACE_MODULECOLORS))
        Base.print_stackframe(io, 1, frame, n, indent+1, modulecolordict, modulecolorcycler)
        println(io)
    end
end
