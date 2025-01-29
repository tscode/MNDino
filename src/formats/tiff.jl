
"""
Support for Tiff files via TiffImages.jl
"""
struct TiffImageFile <: ImageFile
  path::String
  order::DimensionOrder
  tiff::TiffImages.AbstractTiff
end

function TiffImageFile(
  path::String;
  mmap = true,
  nchannels = 1,
  nzlayers = nothing,
  ntlayers = 1,
  order::DimensionOrder = "XYZCT",
)
  tiff = TiffImage.load(path; mmap)

  dims = length(size(tiff))
  if isnothing(nzlayers)
    if dims == 2 # We loaded a 2D tiff file (single plane)
      nzlayers = 1
    elseif dims == 3 # We loaded a 3D tiff file (multiple planes)
      nzlayers = size(tiff, 3)
    else
      error("Expected a 2D or 3D tiff file. Found $dims dimensions.")
    end
  end

  @assert nzlayers * nchannels * ntlayers == size(tiff, 3) """
  Number of planes ($(size(tiff, 3))) is not correctly distributed between \
  Z-layers ($nzlayers), channels ($nchannels), and time layers ($ntlayers).
  """

  sz = (size(tiff)[1:2]..., nzlayers, nchannels, ntlayers)
  sz = orderdims(sz, order)
  tiff = reshape(tiff, sz)
  dims = (order.x, order.y, order.z, order.c, order.t)
  tiff = PermutedDimsArray(tiff, dims)

  return TiffImageFile(path, order, tiff)
end
