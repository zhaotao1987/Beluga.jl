# This should be a script for non-julia users to run the rjMCMC as in my paper
# ______________________________________________________________________________
using Distributed
@everywhere env_dir = "."
@everywhere using Pkg; @everywhere Pkg.activate(env_dir)
using DataFrames, CSV, Distributions, Parameters, JLD
@everywhere using Beluga

# configuration ________________________________________________________________
# this could end up in an argparse kind of thing
config = (
    treefile = "test/data/sim100/plants2.nw",
    datafile = "test/data/sim100/set6_c10_counts.csv",
    # datafile = "test/data/dicots/dicots-f01-100.csv",
    outdir   = "/tmp/irmcmc",
    niter    = 11000,
    burnin   = 1000,
    saveiter = 2500,
    ppsiter  = 2500,
    theta0   = 1.5, sigma0 = 0.5, cov0 = 0.45,
    sigma    = 1.0, cov    = 0.0,
    qa       = 1.0, qb     = 3.0,
    etaa     = 3.0, etab   = 1.0,
    pk       = DiscreteUniform(0, 20),
    qkernel  = Beta(1,3),
    λkernel  = Exponential(0.001),
    expected = LogNormal(log(1), 0.1)
)

# script _______________________________________________________________________
@unpack treefile, datafile, outdir = config
@unpack niter, burnin, saveiter, ppsiter = config
@unpack theta0, sigma0, cov0, cov, sigma = config
@unpack etaa, etab, qa, qb, pk, qkernel, λkernel, expected = config
isdir(outdir) ? nothing : mkdir(outdir)
@info "config" config
open(joinpath(outdir, "config.txt"), "w") do f; write(f, string(config)); end

nw = open(treefile, "r") do f ; readline(f); end
df = CSV.read(datafile, delim=",")
d, p = DLWGD(nw, df, theta0, theta0, 0.9, Branch)

# prior
prior = IidRevJumpPrior(
    Σ₀=[sigma cov ; cov sigma],
    X₀=MvNormal(log.([theta0, theta0]), [sigma0 cov0 ; cov0 sigma0]),
    πK=pk,
    πq=Beta(qa,qb),
    πη=Beta(etaa,etab),
    Tl=treelength(d),
    πE=expected)

chain = RevJumpChain(data=p, model=deepcopy(d), prior=prior)
Beluga.init!(chain, qkernel=qkernel, λkernel=λkernel)

function main(chain, outdir, niter, burnin, saveiter, ppsiter)
    gen = 0
    while gen < niter
        rjmcmc!(chain, saveiter, show=10, trace=1, rjstart=0)
        gen += saveiter
        posterior_Σ!(chain)
        posterior_E!(chain)
        @info "Saving trace (gen = $gen)"
        CSV.write(joinpath(outdir, "trace.csv"), chain.trace)
        JLD.save(joinpath(outdir, "wgdtrace.jld"), "wgds", get_wgdtrace(chain))
        @info "Computing Bayes factors"
        bfs = branch_bayesfactors(chain, burnin)
        CSV.write(joinpath(outdir, "bfs.csv"), bfs)
        if gen % ppsiter == 0
            @info "Doing posterior predicive simulations (PPS)"
            pps = PostPredSim(chain, df, 1000, burnin=burnin)
            JLD.save(joinpath(outdir,"pps.jld"), "pps", pps)
            @info "PPS results" pp_pvalues(pps);
        end
    end
    return chain
end

# run it _______________________________________________________________________
chain = main(chain, outdir, niter, burnin, saveiter, ppsiter)

# ______________________________________________________________________________