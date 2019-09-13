"""
    GeometricBrownianMotion{T<:Real,Ψ<:Arboreal}

Distribution induced by a Geometric Brownian Motion (GBM) over a tree. `r` is
the value at the root of the tree, `ν` is the standard deviation
(autocorrelation strength).

The log density for the GBM distribution is computed with an implementation of
the GBM prior on rates based on Ziheng Yang's MCMCTree, described in [Rannala &
Yang (2007)](https://academic.oup.com/sysbio/article/56/3/453/1657118). This
uses the approach whereby rates are defined for midpoints of branches, and where
a correction is performed to ensure that the correlation is proper (in contrast
with Thorne et al. 1998).
"""
struct GeometricBrownianMotion{T<:Real,Ψ<:Arboreal} <:
        ContinuousMultivariateDistribution
    t::Ψ
    r::T  # rate at root
    ν::T  # autocorrelation strength
end

const GBM = GeometricBrownianMotion
GBM(t::Ψ, r::Real, v::Real) where Ψ<:Arboreal = GBM(t, promote(r, v)...)
Base.length(d::GBM) = length(d.t.tree.nodes)

# Distributions interface
function Distributions.insupport(d::GBM, x::AbstractVector{T}) where {T<:Real}
    for i=1:length(x)
        @inbounds 0.0 < x[i] < Inf ? continue : (return false)
    end
    true
end

Distributions.assertinsupport(::Type{D}, m::AbstractVector) where {D<:GBM} =
    @assert insupport(D, m) "[GBM] rates should be positive"

Distributions.sampler(d::GBM) = d

# XXX refer to Whale implementation for how to deal with WGDs
function Distributions.rand(d::GBM{T,Ψ}) where {T<:Real,Ψ<:Arboreal}
    tree = d.t
    r = zeros(length(d))
    r[findroot(tree)] = d.r
    function walk(n::Int64)
        if !isroot(tree.tree, n)
            p = parentnode(tree, n)
            t = distance(tree.tree, n, p)
            r[n] = exp(rand(Normal(log(r[p]) - d.ν^2*t/2, √t*d.ν)))
        end
        isleaf(tree, n) ? (return) : [walk(c) for c in childnodes(tree, n)]
    end
    walk(findroot(tree))
    return r
end

# XXX refer to Whale implementation for how to deal with WGDs
function Distributions.logpdf(d::GBM{T,Ψ}, x::AbstractVector{T}) where
        {T<:Real,Ψ<:Arboreal}
    if !insupport(d, x)
        return -Inf
    end
    tree = d.t
    logp = -log(2π)/2.0*(2*length(findleaves(tree.tree))-2)  # from Normal
    for n in preorder(tree)
        if isleaf(tree, n)
            continue
        end
        babies = childnodes(tree, n)
        ta = n == 1 ? 0. : distance(tree.tree, parentnode(tree, n), n) / 2.
        t1 = distance(tree.tree, n, babies[1])/2.
        t2 = distance(tree.tree, n, babies[2])/2.
        # determinant of the var-covar matrix Σ up to factor σ^2
        dett = t1*t2 + ta*(t1+t2)
        # correction terms for correlation given rate at ancestral b
        tinv0 = (ta + t2) / dett
        tinv1 = tinv2 = -ta/dett
        tinv3 = (ta + t1) / dett
        ra = x[n]
        r1 = x[babies[1]]
        r2 = x[babies[2]]
        y1 = log(r1/ra) + (ta + t1)*d.ν^2/2  # η matrix
        y2 = log(r2/ra) + (ta + t2)*d.ν^2/2
        zz = (y1*y1*tinv0 + 2*y1*y2*tinv1 + y2*y2*tinv3)
        logp -= zz/(2*d.ν^2) + log(dett*d.ν^4)/2 + log(r1*r2);
        # power 4 is from determinant (which is computed up to the factor from
        # the variance) i.e. Σ = [ta+t1, ta ; ta, ta + t2] × ν^2, so the
        # determinant is: |Σ| = (ta + t1)ν^2 × (ta + t2)ν^2 - ta ν^2 × ta ν^2 =
        # ν^4[ta × (t1 + t2) + t1 × t2] =#
    end
    return logp
end