using Distributions
using BirthDeathProcesses
using PhyloTrees

t = LabeledTree(read_nw(
    "(D:18.03,(C:12.06,(B:7.06,A:7.06):4.99):5.97);")[1:2]...)
d = DLModel(t, 0.2, 0.3)
x = [2, 3, 4, 2]
M = get_M(d, x)
W = get_wstar(d, M)
L = csuros_miklos(d, M, W)


# Naive truncated probabilistic graphical model (VE) approach (CAFE?), intuitive
function pgm(d::DLModel, x::Vector{Int64}, max=50)
    P = zeros(length(d), max+1)
    for e in d.porder
        if isleaf(d, e)
            P[e, leafmap(d[e])+1] = 1.0
        else
            children = childnodes(d, e)
            for i = 0:max
                p = 1.
                for c in children
                    p_ = 0.
                    for j in 0:length(P[c, :])-1
                        p_ += tp(d.b[c], i, j, parentdist(d, c)) * P[c, j+1]
                    end
                    p *= p_
                end
                P[e, i+1] = p
            end
        end
    end
    return P
end
