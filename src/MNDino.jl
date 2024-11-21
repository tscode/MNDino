module MNDino

using Serialization
using Statistics

using Colors
using HDF5 # Imaris support

# using GLMakie
using Makie
using Makie.GridLayoutBase: Outer

# Opening and closing files
import NativeFileDialog

# Image operations
import ImageFiltering
import ImageTransformations
import ImageSegmentation
import ImageMorphology

include("patches/dragpan.jl")

function linkobservables(a, b)
  on(a, update = true) do val
    val != b[] && (b[] = val)
  end
  on(b, update = true) do val
    val != a[] && (a[] = val)
  end
end

function getvalue(collection, key :: Symbol, default)
  if haskey(collection, key)
    val = collection[key]
    val = val isa Observable ? val[] : val
  else
    val = default isa Observable ? default[] : default
  end
  return val
end

function getvalue(obj, key)
  val = getfield(obj, key)
  return val isa Observable ? val[] : val
end

function getvalue(dict::Dict, key)
  val = dict[key]
  return val isa Observable ? val[] : val
end

function getvalue(key :: Symbol, args...)
  return c -> getvalue(c, key, args...)
end

function complement(color::C) where {C <: Color}
  hsv = HSV(color)
  hsv = HSV(mod(hsv.h + 180, 360), hsv.s, hsv.v)
  return C(hsv)
end

function desaturate(color::C, factor) where {C <: Color}
  hsv = HSV(color)
  hsv = HSV(hsv.h, factor * hsv.s, hsv.v)
  return C(hsv)
end

include("imagefile.jl")
include("imaris.jl")
include("filter.jl")

include("provider.jl")
include("widget.jl")
include("project.jl")

# providers
include("imagestore.jl")

# widgets
include("widgets/project.jl")
include("widgets/imageselector.jl")
include("widgets/channelview.jl")
include("widgets/channelviewmask.jl")
include("widgets/segmentanalysis.jl")

# --- For efficient compilation of apps --- #
# include("precompile.jl")
include("main.jl")

end # module MNDino
