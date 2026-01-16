
"""
Support for Tiff files via TiffImages.jl
"""
struct TiffImageFile <: ImageFile
  path::String
  tiff::AbstractArray{<:Gray, 3}
  layout::Layout
end

struct StackLayout
  nchannels::Int
  nzlayers::Int
  ntlayers::Int
  order::DimensionOrder
end

function deducetiffdim(lay::StackLayout, nplanes::Int, n::Int)
    @assert nplanes % ntz == 0 """
    Given layout $lay does not fit number $nplanes of planes found \
    in Tiff file.
    """
    div(nplanes, ntz)
end

function autocomplete_layout(lay::StackLayout, nplanes::Int)
  if nplanes == 1
    StackLayout(1, 1, 1, layout.order)
  elseif lay.nchannels < 0 && lay.nzlayers > 0 && lay.ntlayers > 0
    nchannels = deducetiffdim(lay, nplanes, lay.nzlayers * lay.ntlayers)
    StackLayout(nchannels, lay.nzlayers, lay.ntlayers, lay.order)
  elseif lay.nzlayers < 0 && lay.nchannels > 0 && lay.ntlayers > 0
    nzlayers = deducetiffdim(lay, nplanes, lay.nchannels * lay.ntlayers)
    StackLayout(lay.nchannels, nzlayers, lay.ntlayers, lay.order)
  elseif lay.ntlayers < 0 && lay.nchannels > 0 && lay.nzlayers > 0
    ntlayers = deducetiffdim(lay, nplanes, lay.nchannels * lay.nzlayers)
    StackLayout(lay.nchannels, lay.nzlayers, ntlayers, lay.order)
  else
    @assert nplanes == lay.ntlayers * lay.nchannels * lay.nzlayers """
    Cannot auto-complete layout $lay to fit $nplanes planes.
    """
    lay
  end
end
  

function TiffImageFile(
  path::String;
  layout:: StackLayout = :auto,
  mmap = true,
)
  tiff = TiffImage.load(path; mmap)

  if layout == :auto
    error("Tiff files cannot deduce their stack layout without metadata.")
  end

  dims = length(size(tiff))
  if dims == 2 # We loaded a 2D tiff file (single plane)
    nplanes = 1
  elseif dims == 3 # We loaded a 3D tiff file (multiple planes)
    nplanes = size(tiff, 3)
  else
    error("Expected a 2D or 3D tiff file. Found $dims dimensions.")
  end

  l = autocomplete_layout(layout, nplanes)

  sz = (size(tiff)[1:2]..., l.nzlayers, l.nchannels, l.ntlayers)
  sz = orderdims(sz, l.order)
  tiff = reshape(tiff, sz)
  dims = (order.x, order.y, order.z, order.c, order.t)
  tiff = PermutedDimsArray(tiff, dims)

  return TiffImageFile(path, order, tiff)
end
