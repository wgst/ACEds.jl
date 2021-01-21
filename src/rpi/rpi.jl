
# --------------------------------------------------------------------------
# ACE.jl and SHIPs.jl: Julia implementation of the Atomic Cluster Expansion
# Copyright (c) 2019 Christoph Ortner <christophortner0@gmail.com>
# All rights reserved.
# --------------------------------------------------------------------------



module RPI

path_to_ACE_src = "/Users/msachs2/Documents/GitHub/ACE.jl/src"
include(string(path_to_ACE_src, "/extimports.jl"))

include(string(path_to_ACE_src,"/aceimports.jl"))


import ACE.SphericalHarmonics: SHBasis, index_y

export RPIBasis, SparsePSHDegree, BasicPSH1pBasis,
       diagonal_regulariser

# specify the `Rotations3D` submodule for CLebsch-Gordan and related
include("rotations3d.jl")
using ACEds.RPI.Rotations3D

# some basic degree types useful for RPI type constructions
# (this file also specifies the PSH1pBasisFcn
include("rpi_degrees.jl")

# the basic RPI type 1-particle basis
include("rpi_basic1pbasis.jl")
include("rpi_1pbasis.jl")

# RPI basis and RPI potential
# (the RPI potential is specified through the combine function in this file)
include("rpi_basis.jl")

end
