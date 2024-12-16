
module MNDino

using Statistics
using Dates
using PrecompileTools

using OrderedCollections

# Saving and loading projects in gzipped msgpack
using Pack
using GZip
using Serialization # To be removed

# Support for common images
import ImageIO, FileIO    # CommonImageFile (JPG, PNG, GIF)
import HDF5               # ImarisFile (Imaris .ims format)
import TiffImages, XML    # OmeTiffFile (OMETIFF .ome.tiff format)

# Image operations
using Colors
import ImageCore
import ImageFiltering
import ImageTransformations
import ImageSegmentation
import ImageMorphology

# Plotting / GUI framework
using Makie
using Makie.GridLayoutBase: Outer
using Observables

# Opening and saving files
import NativeFileDialog

# Exporting analysis results as CSV
using DelimitedFiles

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

function fadelabel(label, msg, color = colorant"black"; duration = 5)
  @async begin
    label.color[] = color
    label.text[] = msg
    sleep(duration)
    label.text[] = ""
  end
end

# Makie "patch" to move dragpan to the *left* mouse button
include("patches/dragpan.jl")

include("imagefile.jl")
include("filter.jl")

include("provider.jl")
include("widget.jl")
include("project.jl")
include("dinoscript.jl")

# Supported image formats
include("formats/common.jl")
include("formats/imaris.jl")
include("formats/ometiff.jl")

# Store providers
include("stores/image.jl")
include("stores/variable.jl")

# Widgets
include("widgets/project.jl")
include("widgets/imageselector.jl")
include("widgets/channelview.jl")
include("widgets/channelviewmask.jl")
include("widgets/segments.jl")
include("widgets/analysis.jl")

# Entry point to the GUI
include("main.jl")

# Precompilation statements to reduce startup time
include("precompile.jl")

end # module MNDino
