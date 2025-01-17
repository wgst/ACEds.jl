struct ACMatrixModel{S} <: MatrixModel{S}
    onsite::OnSiteModels
    offsite::OffSiteModels
    n_rep::Int
    inds::SiteInds
    id::Symbol
    function ACMatrixModel{S}(onsite::OnSiteModels,offsite::OffSiteModels,n_rep::Int, id::Symbol) where {S}
        return new(onsite,offsite, n_rep, _get_basisinds(onsite.models, offsite.models), id)
    end
end

# Basic constructor 
function ACMatrixModel(onsite::OnSiteModels,offsite::OffSiteModels,n_rep::Int; id = nothing) 
    S = _symmetry(onsite.models, offsite.models)
    id = (id === nothing ? _default_id(S) : id) 
    return ACMatrixModel{S}(onsite,offsite,n_rep, id)
end

# Convenience constructors 
function ACMatrixModel(onsitemodels::Dict{AtomicNumber, TM},offsitemodels::Dict{Tuple{AtomicNumber, AtomicNumber}, TM},
    rcut::T, n_rep::Int; id = nothing) where {TM, T<:Real}
    onsite = OnSiteModels(onsitemodels, rcut)
    offsite = OffSiteModels(offsitemodels, rcut)
    return ACMatrixModel(onsite, offsite, n_rep; id=id)
end

function ACMatrixModel(onsitemodels::Dict{AtomicNumber, TM},
    rcut::T, n_rep::Int; id = nothing) where {TM, T<:Real}
    onsite = OnSiteModels(onsitemodels, rcut)
    offsite = OffSiteModels(Dict{Tuple{AtomicNumber, AtomicNumber},TM}(), rcut)
    return ACMatrixModel(onsite, offsite, n_rep; id=id)
end

function ACMatrixModel(offsitemodels::Dict{Tuple{AtomicNumber, AtomicNumber}, TM},
    rcut::T, n_rep::Int; id = nothing) where {TM, T<:Real}
    onsite = OnSiteModels(Dict{AtomicNumber, TM}(), rcut)
    offsite = OffSiteModels(offsitemodels, rcut)
    return ACMatrixModel(onsite, offsite, n_rep; id=id)
end

function matrix!(M::ACMatrixModel, at::Atoms, Σ, filter=(_,_)->true) 
    site_filter(i,at) = (haskey(M.onsite.models, at.Z[i]) && filter(i, at))
    for (i, neigs, Rs) in sites(at, env_cutoff(M.onsite.env))
        if site_filter(i, at) && length(neigs) > 0
            # evaluate onsite model
            Zs = at.Z[neigs]
            sm = _get_model(M, at.Z[i])
            cfg = env_transform(Rs, Zs, M.onsite.env)
            Σ_temp = evaluate(sm, cfg)
            for r=1:M.n_rep
                Σ[r][i,i] += _val2block(M, Σ_temp[r].val)
            end
            # evaluate offsite model
            for (j_loc, j) in enumerate(neigs)
                Zi, Zj = at.Z[i],at.Z[j]
                if haskey(M.offsite.models,(Zi,Zj))
                    sm = _get_model(M, (Zi,Zj))
                    cfg = env_transform(j_loc, Rs, Zs, M.offsite.env)
                    Σ_temp = evaluate(sm, cfg)
                    for r=1:M.n_rep
                        Σ[r][j,i] += _val2block(M, Σ_temp[r].val)
                    end
                end
            end
        end
    end
end

function basis!(B, M::ACMatrixModel, at::Atoms, filter=(_,_)->true ) # Todo change type of B to NamedTuple{(:onsite,:offsite)} 
    
    site_filter(i,at) = (haskey(M.onsite.models, at.Z[i]) && filter(i, at))
    for (i, neigs, Rs) in sites(at, env_cutoff(M.onsite.env))
        if site_filter(i, at) && length(neigs) > 0
            Zs = at.Z[neigs]
            sm = _get_model(M, at.Z[i])
            inds = get_range(M, at.Z[i])
            cfg = env_transform(Rs, Zs, M.onsite.env)
            Bii = evaluate(sm.basis, cfg)
            for (k,b) in zip(inds,Bii)
                B.onsite[k][i,i] += _val2block(M, b.val)
            end
            for (j_loc, j) in enumerate(neigs)
                Zi, Zj = at.Z[i],at.Z[j]
                if haskey(M.offsite.models,(Zi,Zj))
                    sm = _get_model(M, (Zi,Zj))
                    inds = get_range(M, (Zi,Zj))
                    cfg = env_transform(j_loc, Rs, Zs, M.offsite.env)
                    Bij =  evaluate(sm.basis, cfg)
                    for (k,b) in zip(inds, Bij)
                        B.offsite[k][j,i] += _val2block(M, b.val)
                    end
                end
            end
        end
    end
end