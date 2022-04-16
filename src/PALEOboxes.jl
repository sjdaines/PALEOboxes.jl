module PALEOboxes

import YAML
import Graphs # formerly LightGraphs
import DataFrames

include("Types.jl")
include("CoordsDims.jl")
include("Fields.jl")
include("AtomicScalar.jl")
include("ScalarData.jl")
include("ArrayScalarData.jl")
include("IsotopeData.jl")
include("VariableAttributes.jl")
include("Interpolation.jl")
include("VariableReaction.jl")
include("VariableDomain.jl")
include("VariableAggregator.jl")
include("VariableStatsMethods.jl")
include("ReactionMethodSorting.jl")
include("Model.jl")
include("Domain.jl")
include("CellRange.jl")
include("Parameter.jl")
include("ReactionMethod.jl")
include("Reaction.jl")
include("ReactionFactory.jl")
include("RateStoich.jl")
include("ModelData.jl")
include("TestUtils.jl")
include("SIMDutils.jl")
include("IteratorUtils.jl")
include("Reservoirs.jl")
include("VariableStats.jl")
include("Fluxes.jl")
include("Grids.jl")
include("SolverView.jl")

end # module
