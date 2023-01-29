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
const SEPARATOR = "----------"
const INDENT_LENGTH = 4

"""
    summarize_current_exceptions(io::IO=Base.stderr)

Print a summary of the current task's exceptions to `io`.

This is particularly helpful in cases where the exception stack is large, the backtraces are
large, and CompositeExceptions with multiple parts are involved.
"""
function summarize_current_exceptions(io::IO=Base.stderr)
    printstyled(io, TITLE, '\n'; color=Base.info_color())
    _summarize_task_exceptions(io, current_task(), 0)
    return nothing
end

function _indent_print(io::IO, indent::Int, x...; color=:normal)
    printstyled(io, " "^indent, x...; color=color)
end

function _indent_println(io::IO, indent::Int, x...; color=:normal)
    _indent_print(io, indent, x..., "\n"; color=color)
end

function _summarize_task_exceptions(io::IO, task::Task, indent::Int)
    exception_stack = current_exceptions(task)
    for (i, es) in enumerate(exception_stack)
        e, stack = es
        if i != 1
            # TODO: should the indention increase here?
            println(io)
            _indent_println(io, indent, "which caused:"; color=Base.error_color())
        end
        _summarize_exception(io, e, stack, indent)
    end
end

"""
    _summarize_exception(io::IO, e::TaskFailedException, _, indent::Int)
    _summarize_exception(io::IO, e::CompositeException, stack, indent::Int)
    _summarize_exception(io::IO, e::Exception, stack, indent::Int)

The secret sauce that lets us unwrap TaskFailedExceptions and CompositeExceptions, and
summarize the actual exception.

TaskFailedException simply wraps a task, so it is just unwrapped, and processed by
_summarize_task_exceptions().

CompositeException simply wraps a Vector of Exceptions. Each of the individual Exceptions is
summarized.

All other exceptions are printed via [`Base.showerror()`](@ref). The first stackframe in the
backtrace is also printed.
"""
function _summarize_exception(io::IO, e::TaskFailedException, _, indent::Int)
    # recurse down the exception stack to find the original exception
    _summarize_task_exceptions(io, e.task, indent)
end
function _summarize_exception(io::IO, e::CompositeException, stack, indent::Int)
    _indent_println(io, indent, "CompositeException (length ", length(e), "):")
    for (i, ex) in enumerate(e.exceptions)
        _summarize_exception(io, ex, stack, indent + INDENT_LENGTH)
        # print something to separate the multiple exceptions wrapped by CompositeException
        if i != length(e.exceptions)
            _indent_println(io, indent + INDENT_LENGTH, SEPARATOR)
        end
    end
end
# This is the overload that prints the actual exception that occurred.
function _summarize_exception(io::IO, exc, stack, indent::Int)
    # Print the exception.
    _indent_print(io, indent)
    Base.showerror(io, exc)
    println(io)

    # Print the source line number of the where the exception occurred.
    bt = Base.process_backtrace(stack)
    # borrowed from julia/base/errorshow.jl
    (frame, n) = bt[1]
    modulecolordict = copy(Base.STACKTRACE_FIXEDCOLORS)
    modulecolorcycler = Iterators.Stateful(Iterators.cycle(Base.STACKTRACE_MODULECOLORS))
    Base.print_stackframe(io, 1, frame, n, indent, modulecolordict, modulecolorcycler)
    println(io)
end
