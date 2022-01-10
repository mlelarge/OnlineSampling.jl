mutable struct MvParticle
    val::Vector{Float64}
    loglikelihood::Float64
end
MvParticle() = MvParticle([0.0], 0.0)
OnlineSMC.value(p::MvParticle) = p.val
OnlineSMC.loglikelihood(p::MvParticle) = p.loglikelihood

const N = 10000
const Nsamples = 1000
const atol = 3 / sqrt(min(N, Nsamples))
const rtol = 0.05

rankone(x::AbstractVector) = x * x'

Statistics.cov(cloud::Cloud{MvParticle}) =
    expectation(rankone, cloud) - rankone(expectation(identity, cloud))
Statistics.mean(cloud::Cloud{MvParticle}) = expectation(identity, cloud)

@testset "tools" begin
    d = MvNormal([0.0], ScalMat(1, 1.0))
    xs = rand(d, N)
    @assert size(xs) == (1, N)

    cloud = Cloud([MvParticle(x, 0.0) for x in eachcol(xs)])
    @test mean(cloud) ≈ mean(d) atol = atol
    @test cov(cloud) ≈ cov(d) atol = atol

    samples = dropdims(rand(cloud, Nsamples); dims = 1)
    @test mean(samples) ≈ only(mean(d)) atol = atol
    @test var(samples) ≈ only(cov(d)) atol = atol

    test = OneSampleADTest(samples, Normal(only(mean(d)), only(cov(d))))
    @test (pvalue(test) > 0.05) || @show test
end

@testset "observe child" begin
    function proposal!(p::MvParticle)
        p.val = rand(MvNormal([0.0], ScalMat(1, 1.0)))
        y = rand(MvNormal(3 .* p.val .+ 1, ScalMat(1, 2.0)))
        obs_y = 2.0
        p.loglikelihood = -0.25 * (3 * only(p.val) + 1 - only(obs_y))^2
    end

    cloud = Cloud(N, MvParticle)
    new_cloud = smc_step(proposal!, cloud)

    target = MvNormal([3 / 11], ScalMat(1, 2 / 11))
    @test mean(new_cloud) ≈ mean(target) rtol = 0.05
    @test cov(new_cloud) ≈ cov(target) rtol = 0.05

    samples = dropdims(rand(new_cloud, Nsamples); dims = 1)
    @test mean(samples) ≈ only(mean(target)) atol = atol
    @test var(samples) ≈ only(cov(target)) atol = atol

    test =
        OneSampleADTest(samples, Normal((only ∘ mean)(target), (sqrt ∘ only ∘ cov)(target)))
    @test (pvalue(test) > 0.01) || @show test
end

@testset "iterate gaussians" begin
    # Model
    # X_1 ∼ N(0, 1)
    # X_{t+1} ∼ N(X_t, 1)
    # observe Y_T ∼ N(X_T, 1)
    function proposal!(p::MvParticle)
        p.val = rand(MvNormal(p.val, ScalMat(1, 1.0)))
        p.loglikelihood = 0.0
    end

    T = 10
    cloud = Cloud(N, MvParticle)
    for _ = 1:(T-1)
        cloud = smc_step(proposal!, cloud)
    end
    obs_y = [1.0]
    cloud = smc_step(cloud) do p
        proposal!(p)
        p.loglikelihood = -0.5 * (only(obs_y) - only(p.val))^2
    end

    σ = sqrt(T / (T + 1))
    target = MvNormal(σ^2 * obs_y, ScalMat(1, σ^2))
    @test mean(cloud) ≈ mean(target) rtol = rtol
    @test cov(cloud) ≈ cov(target) rtol = rtol

    samples = dropdims(rand(cloud, Nsamples); dims = 1)
    @test mean(samples) ≈ only(mean(target)) atol = atol
    @test var(samples) ≈ only(cov(target)) atol = 2 * atol

    test =
        OneSampleADTest(samples, Normal((only ∘ mean)(target), (sqrt ∘ only ∘ cov)(target)))
    @test (pvalue(test) > 0.01) || @show test
end
