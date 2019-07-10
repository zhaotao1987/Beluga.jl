# MLE using the Optim library
"""
    mle(w::WhaleModel, ccd::CCDArray, optimizer=LBFGS(); kwargs...)
"""
function mle(d::DLModel, M::AbstractArray, optimizer=LBFGS(); kwargs...)
    kwargs = merge(Dict(:show_every=>10, :show_trace=>true, :constant=true), kwargs)
    W = get_wstar(d, M)
    x = kwargs[:constant] ? [d[1].λ, d[1].μ] : asvector(d)
    f  = (x) -> -logpdf(DLModel(t, x, d.η), ccd)
    g! = (G, x) -> G .= -gradient(WhaleModel(t, x, w.η, w.cond), ccd)
    lower, upper = bounds(w)
    opts = Optim.Options(;kwargs...)
    out = do_opt(optimizer, opts, f, g!, lower, upper, x)
    m = WhaleModel(t, out.minimizer, w.η, w.cond)
    return m, out
end

function asvector(d::DLModel)
    l = [x.λ for x in d.b]
    m = [x.μ for x in d.b]

do_opt(optimizer::Optim.FirstOrderOptimizer, opts, args...) =
    optimize(args..., Fminbox(optimizer), opts)

do_opt(optimizer::Optim.ZerothOrderOptimizer, opts, args...) =
    optimize(args[1], args[3:end]..., Fminbox(optimizer), opts)

# get bounds for Whale model
function bounds(w::WhaleModel)
    lower = [0. for i=1:length(asvector1(w))]
    upper = [[Inf for i=1:2*nrates(w.S)] ; [1. for i=1:nwgd(w.S)]]
    return lower, upper
end

#=function f(x::Vector)  # using KissThreading
    w = WhaleModel(t, x)
    v0 = -logpdf(w, ccd[1])
    return @views tmapreduce(+, ccd[2:end], init=v0) do c
        -logpdf(w, c)
    end
end=#
