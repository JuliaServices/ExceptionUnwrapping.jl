# ExceptionUnwrapping.jl

`ExceptionUnwrapping.jl` provides exception handling utilities to allow inspecting and
unwrapping "wrapped exceptions," by which we mean any Exception type that itself embeds
another Exception.

The most common example is a `TaskFailedException`, which wraps a `Task` and the exception
that caused that Task to fail. Another example is the exception types in
[Salsa.jl](https://github.com/RelationalAI-oss/Salsa.jl).

## API

- `has_wrapped_exception(e, ExceptionType)::Bool`

- `is_wrapped_exception(e)::Bool`

- `unwrap_exception(exception_wrapper) -> wrapped_exception`

- `unwrap_exception(normal_exception) -> normal_exception`

- `unwrap_exception_until(e, ExceptionType)::ExceptionType`

- `unwrap_exception_to_root(exception_wrapper) -> wrapped_exception`

- `unwrap_exception_to_root(normal_exception) -> normal_exception`

## Usage

If your library provides a wrapped exception type, you should register it
with this package by simply adding a method to `unwrap_exception`:
```julia
ExceptionUnwrapping.unwrap_exception(e::MyWrappedException) = e.exception
```

In client code, you should use `has_wrapped_exception` and `unwrap_exception_until`
in catch blocks:
```julia
try
    ...
catch e
    if has_wrapped_exception(e, BoundsError)
        be = unwrap_exception_until(e, BoundsError)
        # ...Use BoundsError...
    else
        rethrow()
    end
end
```

Finally, you can improve robustness in client tests via `@test_throws_wrapped`:
```julia
@test_throws_wrapped AssertionError my_possibly_multithreaded_function()
```

## Motivating Example: Stable Exception Handling
### A Problem: Adding Concurrency to a Library Can Break Users' Exception Handling
As we all start using concurrency more, exception handling can get a bit weird. Julia's
cooperative multithreading is designed to be _composable_ as a fundamental principle, but
changing syncronous code to run concurrently in a `Task` **changes the types of Exceptions
that code will throw!**

Consider for example this silly program, which wants to handle a certain type of Exception
(`BoundsError`s) in order to take meaningful action (ask the user to try again):
```julia
function get_and_sort_names_by_first_letter(n)
    try
        names = [readline() for _ in 1:n]
        # Use this libary's sort function because it's supposed to be wicked fast 🤘
        return library_sort(names, by=a->a[1])
    catch e
        if e isa BoundsError
            println("Oops! You entered an empty name. Please try again!")
            # Give the user another shot
            return get_and_sort_names_by_first_letter(n)
        else
            rethrow()  # Unknown error
        end
    end
end
```

All is well and good:
```julia
julia> get_and_sort_names_by_first_letter(2)

Valentin
Oops! You entered an empty name. Please try again!
Valentin
Jane
2-element Array{String,1}:
 "Jane"
 "Valentin"
```

But what happens if that library decides to _parallelize its sorting function_, so now its
even wicked faster? (🤘🤘?)
```julia
# lol, well, this won't make it any faster, but it demonstrates the point.
library_sort(args...; kwargs...) = fetch(Threads.@spawn sort(args...; kwargs...))
```

_What happens_ is the library has inadvertently broken its caller:
```julia
julia> get_and_sort_names_by_first_letter(2)

Nathan
ERROR: TaskFailedException:
BoundsError: attempt to access String
  at index [1]
Stacktrace:
 [1] checkbounds at ./strings/basic.jl:193 [inlined]
 [2] codeunit at ./strings/string.jl:89 [inlined]
 [3] getindex at ./strings/string.jl:210 [inlined]
 [4] #10 at /Users/nathan.daly/.julia/dev/ExceptionUnwrapping/src/ExceptionUnwrapping.jl:125 [inlined]
 [5] lt(::Base.Order.By{var"#10#12"}, ::String, ::String) at ./ordering.jl:51
 [6] sort!(::Array{String,1}, ::Int64, ::Int64, ::Base.Sort.InsertionSortAlg, ::Base.Order.By{var"#10#12"}) at ./sort.jl:468
 [7] sort!(::Array{String,1}, ::Int64, ::Int64, ::Base.Sort.MergeSortAlg, ::Base.Order.By{var"#10#12"}, ::Array{String,1}) at .
```

The library never promised to return a `BoundsError`, so it can't know it's supposed to
handle and unwrap any TaskFailedException it encounters; maybe the user _would want to see_
the TaskFailedException. And the user's code felt comfortable depending on the
`BoundsError`, since it's coming from the lambda it provided directly, so it thought it
would know what kind of exceptions could be produced.

And since this code path is _error handling_, it's quite possibly it's poorly tested!

What a conundrum! And so, we present here a solution: `ExceptionUnwrapping.jl`

### The Solution: ExceptionUnwrapping.jl
If the user always structures their execption checks using ExceptionUnwrapping, then it will
continue working despite any changes to the underlying concurrency model:
```julia
function get_and_sort_names_by_first_letter(n)
    try
        names = [readline() for _ in 1:n]
        # Use this libary's sort function because it's supposed to be wicked fast 🤘
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
```
Now it will work again, regardless of whether `library_sort` is using Tasks internally or
not, which is exactly what we want from composable multithreading! :)
```julia
julia> get_and_sort_names_by_first_letter(2)

Nathan
Oops! You entered an empty name. Please try again!
Nathan
Martin
2-element Array{String,1}:
 "Martin"
 "Nathan"
```

--------------

## Terminology:

### "Wrapped Exceptions" vs "Exception Causes"

In julia, one exception can be "caused by" another exception if a new exception is thrown
from within an `catch`-block (or `finally`-block). This is _not_ the situation that this
package is addressing.

For example:
```julia
julia> try
           throw(ErrorException("1"))
       catch e
           throw(ErrorException("2"))
       end
ERROR: 2
Stacktrace:
 [1] top-level scope at REPL[1]:4
caused by [exception 1]
1
Stacktrace:
 [1] top-level scope at REPL[1]:2
```

This is situation already well covered by Julia's standard library, which has functions like
`Base.catch_stack()` which will return the above stack of exceptions that were thrown (and
is used to print the `caused by` display above).

Instead, this package is for dealing with _"wrapped exceptions"_, which is a term we are
coining to refer to Exceptions that embed another Exception inside of them, either to add
information or context, or because the exception mechanism cannot cross the boundary between
Tasks.
