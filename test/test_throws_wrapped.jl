module TestThrowsWrappedTest

using Test
using ExceptionUnwrapping: @test_throws_wrapped

@testset "Parity Successes" begin
    @test_throws         ErrorException error("ohnoes")
    @test_throws_wrapped ErrorException error("ohnoes")

    @test_throws         Int throw(2)
    @test_throws         2   throw(2)
    @test_throws_wrapped Int throw(2)
    @test_throws_wrapped 2   throw(2)

    e = MethodError(+,(2,3))
    @test_throws_wrapped e throw(e)
    @test_throws_wrapped e throw(e)
end
@testset "Wrapped Exceptions" begin
    @test_throws_wrapped ErrorException fetch(@async(error("ohnoes")))
    @test_throws_wrapped Int fetch(@async(throw(2)))
    @test_throws_wrapped 2 fetch(@async(throw(2)))

    e = MethodError(+,(2,3))
    @test_throws_wrapped e fetch(@async(throw(e)))

    @testset "Multi-layer" begin
        @test_throws_wrapped MethodError fetch(@async(fetch(@async(throw(e)))))
        @test_throws_wrapped e           fetch(@async(fetch(@async(throw(e)))))
    end
end


# Test expected Fail results:
# (This test infra copied from stdlib Test)
mutable struct NoThrowTestSet <: Test.AbstractTestSet
    results::Vector
    NoThrowTestSet(desc) = new([])
end
Test.record(ts::NoThrowTestSet, t::Test.Result) = (push!(ts.results, t); t)
Test.finish(ts::NoThrowTestSet) = ts.results

fails = @testset NoThrowTestSet begin
    # Parity failures
    @test_throws         Int error("ohnoes")
    @test_throws_wrapped Int error("ohnoes")

    e1 = MethodError(+,(2,3))
    e2 = MethodError(+,(3,4))
    @test_throws         e1 throw(e2)
    @test_throws_wrapped e1 throw(e2)


    # Wrapped failures
    @test_throws_wrapped Int fetch(@async(error("ohnoes")))
    @test_throws_wrapped e1 fetch(@async(throw(e2)))

    # Multilayer
    @test_throws_wrapped Int fetch(@async(fetch(@async(throw(e1)))))
    @test_throws_wrapped e1  fetch(@async(fetch(@async(throw(e2)))))
end

@testset "Parity Failures" begin
    @assert fails[1] isa Test.Fail
    @test fails[2] isa Test.Fail

    @assert fails[3] isa Test.Fail
    @test fails[4] isa Test.Fail

    @test all(f isa Test.Fail for f in fails[5:end])
end

# Test un-expected Pass results:
@testset "Unexpected Pass" begin
    # This _expected_ an ErrorException, but it passes, so here we ensure that we get a
    # test failure.
    # TODO: Not exactly sure how to test this... This is working now upon manual inspection.
    #       But e1 and e2 don't contain any info. they're just this no matter what:
    #       `Test.FallbackTestSetException("There was an error during testing")`
    e1 = try
        @test_throws_unwrapped ErrorException true
    catch e e end

    e2 = try
        @test_throws ErrorException true
    catch e e end

    @test e1 == e2
end

end
