
#
# I found this color conversion here:
#   https://forum.image.sc/t/color-tag-in-ome-tiff-xml/48106
#

function _ometiff_parse_color(x)
  return RGBAf((x >> 24) & 0xff, (x >> 16) & 0xff, (x >> 8) & 0xff, x & 0xff)
end

# TODO: I have read that there may be multiple IMAGEDESCRIPTION tags?
function _ometiff_omexml(tiff)
  ifds = TiffImages.ifds(tiff)
  ifd = ifds isa TiffImages.IFD ? ifds : ifds[1]
  xmlstr = ifd[TiffImages.IMAGEDESCRIPTION].data
  return XML.parse(XML.LazyNode, xmlstr)
end

function _ometiff_pixels(xml)
  for node in xml
    if XML.tag(node) == "Pixels"
      return XML.attributes(node)
    end
  end
end

function _ometiff_channels(xml)
  channels = []
  for node in xml
    if XML.tag(node) == "Channel"
      push!(channels, XML.attributes(node))
    end
  end
  nchannels = parse(Int, _ometiff_pixels(xml)["SizeC"])
  @assert length(channels) == nchannels """
  Found more channel XML entries than expected
  """
  # Make sure that we can read the ids and
  # that they are stored in the right order
  ids = map(channels) do channel
    m = match(r"Channel:[0-9]+:([0-9]+)", channel["ID"])
    @assert !isnothing(m) """
    Could not determine channel id (ID $(channel["ID"]))
    """
    return m[1]
  end
  perm = sortperm(ids)
  return channels[perm]
end

struct OmeTiffFile <: ImageFile
  path::String
  pixels::OrderedDict{String, String}
  channels::Vector{OrderedDict{String, String}}
  order::DimensionOrder
  tiff::AbstractArray{<:Gray, 5}
end

function OmeTiffFile(path::String)
  tiff = TiffImages.load(path; mmap = true, verbose = false)
  xml = _ometiff_omexml(tiff)
  pixels = _ometiff_pixels(xml)
  channels = _ometiff_channels(xml)
  order = DimensionOrder(pixels["DimensionOrder"])

  sz = map(("SizeX", "SizeY", "SizeZ", "SizeC", "SizeT")) do key
    return parse(Int, pixels[key])
  end

  # We always expect the first two dimensions to correspond to XY or YX
  @assert prod(sz[1:2]) == prod(size(tiff)[1:2]) """
  Inconsistency of XY dimensions between metadata and loaded tiff image
  """
  @assert prod(sz) == prod(size(tiff)) """
  Inconsistency between shape metadata and loaded tiff image
  """
  sz = orderdims(sz, order)
  tiff = reshape(tiff, sz)
  @show sz
  dims = (order.x, order.y, order.z, order.c, order.t)
  @assert sz == size(tiff) """
  Inconsistency while permuting array dimensions
  """
  tiff = PermutedDimsArray(tiff, dims)
  return OmeTiffFile(path, pixels, channels, order, tiff)
end

extensions(::Type{OmeTiffFile}) = [".ome.tif", ".ome.tiff"]
location(img::OmeTiffFile) = img.path

# From what I know, OMETIFF files do not store multiple versions / variants
# Update: There seems to be an option for "pyramidal" OMETIFF images in newer versions. For now, we do not support this.
variants(::OmeTiffFile) = (;)

nchannels(img::OmeTiffFile) = parse(Int, img.pixels["SizeC"])
nzlayers(img::OmeTiffFile) = parse(Int, img.pixels["SizeZ"])
ntlayers(img::OmeTiffFile) = parse(Int, img.pixels["SizeT"])

variantdefault(::OmeTiffFile) = (;)
tindexdefault(img::OmeTiffFile) = 1

function zindexdefault(img::OmeTiffFile)
  nz = nzlayers(img)
  return max(div(nz, 2), 1)
end

function channels(img::OmeTiffFile)
  return map(enumerate(img.channels)) do (cindex, ch)
    if haskey(ch, "Name")
      name = ch["Name"]
    else
      @warn """
      Could not determine channel name. Fall back to 'Channel $cindex'
      """
      name = "Channel $cindex"
    end
    if haskey(ch, "Color")
      color = _ometiff_parse_color(parse(Int, ch["Color"]))
    else
      @warn """
      Could not determine channel color. Picking a random one.
      """
      color = _getcolor(cindex)
    end
    Channel(cindex, name, color)
  end
end

function metadata(img::OmeTiffFile)
  return (
    resolution = size(img.tiff)[1:2],
    channels = channels(img),
  )
end

function imagedata(img::OmeTiffFile, cindex, zindex, tindex)
  slice = @view img.tiff[:, :, zindex, cindex, tindex]
  slice = ImageCore.channelview(slice) # remove color wrapper (Gray)
  slice = reinterpret.(slice) # remove Normed FixedPointNumber
  return reinterpret(UInt8, slice)
end

registerformat!(OmeTiffFile)
