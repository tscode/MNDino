module MNDino

using Serialization
using Statistics
using DelimitedFiles

using Colors
using HDF5 # Imaris support
using GZip # Reduce the size of project files greatly

using Observables
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
include("dinoscript.jl")

# store providers
include("stores/image.jl")
include("stores/variable.jl")

# widgets
include("widgets/project.jl")
include("widgets/imageselector.jl")
include("widgets/channelview.jl")
include("widgets/channelviewmask.jl")
include("widgets/segments.jl")
include("widgets/analysis.jl")

include("main.jl")

include("rescueproject.jl")

# precompilation statements
# include("compilat.jl")

end # module MNDino
