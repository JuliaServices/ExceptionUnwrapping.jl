module ExceptionUnwrapping

# Document this Module via the README.md file.
@doc let path = joinpath(dirname(@__DIR__), "README.md")
    include_dependency(path)
    read(path, String)
end ExceptionUnwrapping

export unwrap_exception, has_wrapped_exception, unwrap_exception_until,
       unwrap_exception_to_root

"""
    has_wrapped_exception(e, ExceptionType)::Bool

Returns true if the given exception instance, `e`, contains an exception of type `T`
anywhere in its chain of unwrapped exceptions.

Application code should prefer to use `has_wrapped_exception(e, T)` instead of `e isa T` in
catch-blocks, to keep code from breaking when libraries wrap user's exceptions.

This makes application code resilient to library changes that may cause wrapped exceptions,
such as e.g. changes to underlying concurrency decisions (thus maintaining concurrency's
cooperative benefits).

# Example
```julia
try
    # If this becomes concurrent in the future, the catch-block doesn't need to change.
    library_function(args...)
catch e
    if has_wrapped_exception(e, MyExceptionType)
        unwrapped = unwrap_exception_until(e, MyExceptionType)
        handle_my_exception(unwrapped, caught=e)
    else
        rethrow()
    end
end
```
"""
function has_wrapped_exception end

"""
    unwrap_exception(exception_wrapper) -> wrapped_exception
    unwrap_exception(normal_exception) -> normal_exception

    # Add overrides for custom exception types
    ExceptionUnwrapping.unwrap_exception(e::MyWrappedException) = e.wrapped_exception

Unwraps a wrapped exception by one level. *New wrapped exception types should add a method
to this function.*

One example of a wrapped exception is the `TaskFailedException`, which wraps an exception
thrown by a `Task` with a new `Exception` describing the task failure.

It is useful to unwrap the exception to test what kind of exception was thrown in the first
place, which is useful in case you need different exception handling behavior for different
types of exceptions.

Authors of new wrapped exception types can overload this to indicate what field their
exception is wrapping, by adding an overload, e.g.:
```julia
ExceptionUnwrapping.unwrap_exception(e::MyWrappedException) = e.wrapped_exception
```

This is used in the implementations of the other functions in the module:
- [`has_wrapped_exception(e, ::Type)`](@ref)
- [`unwrap_exception_to_root(e)`](@ref)
"""
function unwrap_exception end

"""
    unwrap_exception_until(e, ExceptionType)::ExceptionType

Unwrap a wrapped exception `e` until
"""
function unwrap_exception_until end

"""
    unwrap_exception_to_root(exception_wrapper) -> wrapped_exception
    unwrap_exception_to_root(normal_exception) -> normal_exception

Unwrap a wrapped exception to its bottom layer.
"""
function unwrap_exception_to_root end


struct UnwrappedExceptionNotFound{RequestedType, ExceptionType} <: Base.Exception
    exception::ExceptionType
end
UnwrappedExceptionNotFound{R}(e::E) where {R,E} = UnwrappedExceptionNotFound{R,E}(e)


# Base case is that e -> e
unwrap_exception(e) = e
# Add overloads for wrapped exception types to unwrap the exception.
if VERSION >= v"1.3.0-"
    # TaskFailedExceptions wrap a failed task, which contains the exception that caused it
    # to fail. You can unwrap the exception to discover the root cause of the failure.
    unwrap_exception(e::Base.TaskFailedException) = e.task.exception
end

function has_wrapped_exception(e, ::Type{T}) where T
    if e isa T
        true
    else
        e === unwrap_exception(e) ? false : has_wrapped_exception(unwrap_exception(e), T)
    end
end

function unwrap_exception_until(e, ::Type{T}) where T
    if e isa T
        e
    else
        if e === unwrap_exception(e)
            throw(UnwrappedExceptionNotFound{T}(e))
        else
            unwrap_exception_until(unwrap_exception(e), T)
        end
    end
end

function unwrap_exception_to_root(e)
    e === unwrap_exception(e) ? e : unwrap_exception_to_root(unwrap_exception(e))
end

end # module

# Read names from the user, and sort them by their first letter only
function get_and_sort_names_by_first_letter(n)
    try
        names = [readline() for _ in 1:n]
        return library_sort(names, by=a->a[1])
    catch e
        # Use ExceptionUnwrapping's check to see whether `e` either _is_ a BoundsError _or_
        # if it is _wrapping_ a BoundsError.
        if has_wrapped_exception(e, BoundsError)
            println("Oops! You entered an empty name. Please try again!")
            # Give the user another shot
            return get_and_sort_names_by_first_letter(n)
        else
            rethrow()  # Unknown error
        end
    end
end

library_sort(args...; kwargs...) = sort(args...; kwargs...)
