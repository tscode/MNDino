
using OMETIFF: OMETIFF
import OMETIFF.ImageMetadata
import OMETIFF.AxisArrays
using FileIO: FileIO

struct DimensionOrder
  c::Int
  x::Int
  y::Int
  z::Int
  t::Int
end

function DimensionOrder(str)
  DimensionOrder(
    findfirst('C', str),
    findfirst('X', str),
    findfirst('Y', str),
    findfirst('Z', str),
    findfirst('T', str)
  )
end

function _ometiff_channelcolor(x)
  return RGBA(
    (x>>24)&0xff,
    (x>>16)&0xff,
    (x>>8)&0xff,
    x&0xff,
  )
end

struct OmeTiffFile <: ImageFile
  path::String
  data::AxisArrays.AxisArray
  order::DimensionOrder
  xml::String
end

function OmeTiffFile(path::String; ckey = nothing, tkey = nothing)
  ometiff = FiloIO.load(path; dropunused = false, inmemory = false)
  data = ImageMetadata.data(ometiff)
  names = AxisArrays.axisnames(data)

  xkey = _findkey(names, [:x, :X])
  ykey = _findkey(names, [:y, :Y])
  zkey = _findkey(names, [:z, :Z])

  @assert !isnothing(xkey) "X axis key not found (OmeTiffImage)"
  @assert !isnothing(ykey) "Y axis key not found (OmeTiffImage)"
  @assert !isnothing(zkey) "Z axis key not found (OmeTiffImage)"

  if isnothing(ckey)
    ckey = _findkey(names, [:c, :channel, :C, :Channel, :CHANNEL])
  else
    @assert ckey in names "Channel key $ckey not found (OmeTiffImage)"
  end

  if isnothing(tkey)
    tkey = _findkey(names, [:t, :time, :T, :Time, :TIME])
  else
    @assert tkey in names "Time key $tkey not found (OmeTiffImage)"
  end

  return OmeTiffFile(path, data, (ckey, xkey, ykey, zkey, tkey))
end

extensions(::Type{OmeTiffFile}) = [".ome.tif", ".ome.tiff"]
location(img::OmeTiffFile) = img.path

# TODO: this could be done by collecting non-CXYZT axes?
function variants(ims::OmeTiffFile)
  return error("TODO")
end

function nchannels(img::OmeTiffFile)
  if isnothing(img.keys[1])
    return 1
  else
    vals = AxisArrays.axisvalues(img.data)
    dim = AxisArrays.axisdim(img.data, Axis{img.keys[1]})
    return length(vals[dim])
  end
end

function nzlayers(img::OmeTiffFile)
  if isnothing(img.keys[4])
    return 1
  else
    vals = AxisArrays.axisvalues(img.data)
    dim = AxisArrays.axisdim(img.data, Axis{img.keys[4]})
    return length(vals[dim])
  end
end

function ntlayers(img::OmeTiffFile)
  if isnothing(img.keys[5])
    return 1
  else
    vals = AxisArrays.axisvalues(img.data)
    dim = AxisArrays.axisdim(img.data, Axis{img.keys[5]})
    return length(vals[dim])
  end
end

variantdefault(::OmeTiffFile) = (;)
tindexdefault(img::OmeTiffFile) = 1

function zindexdefault(img::OmeTiffFile)
  nz = nzlayers(img)
  return max(div(nz, 2), 1)
end

function channelname(img::ImarisFile, cindex)
  vals = AxisArrays.axisvalues(img.data)
  dim = AxisArrays.axisdim(img.data, Axis{img.keys[1]})
  return vals[dim][cindex]
end

function channelcolor(img::ImarisFile, cindex)
  meta = metadata(img, cindex)
  return meta.color
end

function channelnames(img::ImarisFile)
  return map(1:nchannels(img)) do cindex
    return channelname(img, cindex)
  end
end

function channelcolors(img::ImarisFile)
  return map(1:nchannels(img)) do cindex
    return channelcolor(img, cindex)
  end
end

