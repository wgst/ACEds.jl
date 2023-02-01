using LinearAlgebra
using ACEds.FrictionModels
using ACE: scaling, params
using ACEds
using ACEds.FrictionFit
using ACEds.DataUtils
using Flux
using Flux.MLUtils
using ACE
using ACEds: ac_matrixmodel
using Random
using ACEds.Analytics
using ACEds.FrictionFit
using CUDA

cuda = CUDA.functional()

path_to_data = # path to the ".json" file that was generated using the code in "tutorial/import_friction_data.ipynb"
fname =  # name of  ".json" file 
path_to_data = "/Users/msachs2/Documents/Projects/data/friction_tensors/H2Cu"
fname = "/h2cu_20220713_friction"
filename = string(path_to_data, fname,".json")
rdata = ACEds.DataUtils.json2internal(filename; blockformat=true);

# Partition data into train and test set 
rng = MersenneTwister(12)
shuffle!(rng, rdata)
n_train = 1200
data = Dict("train" => rdata[1:n_train], "test"=> rdata[n_train+1:end]);


m_inv = ac_matrixmodel(ACE.Invariant(); n_rep = 2,
        species_maxorder_dict_on = Dict( :H => 1), 
        species_weight_cat_on = Dict(:H => .75, :Cu=> 1.0),
        species_maxorder_dict_off = Dict( :H => 0), 
        species_weight_cat_off = Dict(:H => 1.0, :Cu=> 1.0),
        bond_weight = .5
    );
m_cov = ac_matrixmodel(ACE.EuclideanVector(Float64);n_rep=3,
        species_maxorder_dict_on = Dict( :H => 1), 
        species_weight_cat_on = Dict(:H => .75, :Cu=> 1.0),
        species_maxorder_dict_off = Dict( :H => 0), 
        species_weight_cat_off = Dict(:H => 1.0, :Cu=> 1.0),
        bond_weight = .5
    );

m_equ = ac_matrixmodel(ACE.EuclideanMatrix(Float64);n_rep=2, 
        species_maxorder_dict_on = Dict( :H => 1), 
        species_weight_cat_on = Dict(:H => .75, :Cu=> 1.0),
        species_maxorder_dict_off = Dict( :H => 0), 
        species_weight_cat_off = Dict(:H => 1.0, :Cu=> 1.0),
        bond_weight = .5
    );


fm= FrictionModel((m_cov,m_equ)); #fm= FrictionModel((cov=m_cov,equ=m_equ));
model_ids = get_ids(fm)

#%%

fdata =  Dict(
    tt => [FrictionData(d.at,
            d.friction_tensor, 
            d.friction_indices; 
            weights=Dict("diag" => 2.0, "sub_diag" => 1.0, "off_diag"=>1.0)) for d in data[tt]] for tt in ["test","train"]
);
                                            
#%%
c = params(fm;format=:matrix, joinsites=true)

ffm = FluxFrictionModel(c)

# import ACEds.FrictionFit: set_params!

# function set_params!(m::FluxFrictionModel; sigma=1E-8, model_ids::Array{Symbol}=Symbol[])
#     model_ids = (isempty(model_ids) ? get_ids(m) : model_ids)
#     for (sc,s) in zip(m.c,m.model_ids)
#         if s in model_ids
#             for c in sc
#                 randn!(c) 
#                 c .*=sigma 
#             end
#         end
#     end
# end

set_params!(ffm; sigma=1E-8)
if cuda
    ffm = fmap(cu, ffm)
end

flux_data = Dict( tt=> flux_assemble(fdata[tt], fm, ffm; weighted=true, matrix_format=:dense_reduced) for tt in ["train","test"]);

typeof(ffm.c[1])

using ACEds.FrictionFit: _Gamma
import ACEds.FrictionFit: FluxFrictionModel
import Flux

# BB = flux_data["train"][1].B
# typeof(BB)
# typeof(ffm.c)
# Γ = flux_data["train"][1].friction_tensor
# d = flux_data["train"][1]
# sc = ffm.c
# _Gamma(BB,sc)-Γ
# l2_loss(fm, data) = sum(sum(((fm(d.B) .- d.friction_tensor)).^2) for d in data)

# # data = flux_data["train"][1:2]
# sum(sum((_Gamma(d.B,sc)-d.friction_tensor).^2)  for d in data)

# Flux.gradient(sc->sum(sum((_Gamma(d.B,sc)-d.friction_tensor).^2)  for d in data[1:2]), sc)[1]

(m::FluxFrictionModel)(B) = _Gamma(B, m.c)
l2_loss(fm, data) = sum(sum((fm(d.B)-d.friction_tensor).^2)  for d in data)

Flux.@functor FluxFrictionModel (c,)

# Flux.gradient(fm->sum(sum((fm(d.B)-d.friction_tensor).^2)  for d in data[1:2]), ffm)[1]


g = Flux.gradient(l2_loss,ffm, flux_data["train"][1:2])[1]

# typeof(g[1])
# g[2][1].friction_tensor



# typeof(data[1])
# Flux.gradient(sum(sum((ffm(d.B)-d.friction_tensor).^2)  for d in data[1:2]), ffm.c)[1]

# Flux.gradient(l2_loss,ffm, data)

loss_traj = Dict("train"=>Float64[], "test" => Float64[])
n_train, n_test = length(flux_data["train"]), length(flux_data["test"])
epoch = 0


#opt = Flux.setup(Adam(5E-5, (0.9999, 0.99999)),ffm)
opt = Flux.setup(Adam(1E-4, (0.99, 0.999)),ffm)
dloader5 = cuda ? DataLoader(flux_data["train"] |> gpu, batchsize=10, shuffle=true) : DataLoader(flux_data["train"], batchsize=10, shuffle=true)
nepochs = 10
@time l2_loss(ffm, flux_data["train"])
@time Flux.gradient(l2_loss,ffm, flux_data["train"][2:3])[1]
@time Flux.gradient(l2_loss,ffm, flux_data["train"][10:15])[1][:c]
typeof(ffm.c)


using ACEds.FrictionFit: weighted_l2_loss
for _ in 1:nepochs
    epoch+=1
    @time for d in dloader5
        ∂L∂m = Flux.gradient(weighted_l2_loss,ffm, d)[1]
        Flux.update!(opt,ffm, ∂L∂m)       # method for "explicit" gradient
    end
    for tt in ["test","train"]
        push!(loss_traj[tt], weighted_l2_loss(ffm,flux_data[tt]))
    end
    println("Epoch: $epoch, Abs Training Loss: $(loss_traj["train"][end]), Test Loss: $(loss_traj["test"][end])")
end
println("Epoch: $epoch, Abs Training Loss: $(loss_traj["train"][end]), Test Loss: $(loss_traj["test"][end])")
println("Epoch: $epoch, Avg Training Loss: $(loss_traj["train"][end]/n_train), Test Loss: $(loss_traj["test"][end]/n_test)")


c_fit = params(ffm)

ACE.set_params!(fm, c_fit)

using ACEds.Analytics: error_stats, plot_error, plot_error_all
df_abs, df_rel, df_matrix, merrors =  error_stats(data, fm; filter=(_,_)->true, atoms_sym=:at, reg_epsilon = 0.01)

fig1, ax1 = plot_error(data, fm;merrors=merrors)
display(fig1)
fig1.savefig("./scatter-detailed-equ-cov.pdf", bbox_inches="tight")


fig2, ax2 = plot_error_all(data, fm; merrors=merrors)
display(fig2)
fig2.savefig("./scatter-equ-cov.pdf", bbox_inches="tight")
#%%

using PyPlot
N_train, N_test = length(flux_data["train"]),length(flux_data["test"])
fig, ax = PyPlot.subplots()
ax.plot(loss_traj["train"]/N_train, label="train")
ax.plot(loss_traj["test"]/N_test, label="test")
ax.legend()
display(fig)

# using NeighbourLists
# using ACEds.CutoffEnv: env_cutoff
# using JuLIP: neighbourlist

# rcut = env_cutoff(m_inv.onsite.env)+1.0
# at = fdata["train"][116].atoms

# nlist = neighbourlist(at, rcut)
# Js, Rs = NeighbourLists.neigs(nlist, 55)
