
"""
Structure derived from the 'Pixels' node in an OME XML
"""
struct OmePixels
  id::String
  order::DimensionOrder
  size::NTuple{5, Int}
  type::DataType
end

const _ometiff_pixel_types = Dict(
  "int8" => Int8,
  "int16" => Int16,
  "int32" => Int32,
  "uint8" => UInt8,
  "uint16" => UInt16,
  "uint32" => UInt32,
  "float" => Float32,
  "double" => Float64,
)

"""
    OmePixels(node)

Create an OmePixels object from a OME-XML `<Pixels>` node `node`.
"""
function OmePixels(node)
  @assert XML.tag(node) == "Pixels" """
  Expected OME-XML <Pixels> node.
  """
  attribs = XML.attributes(node)
  id = attribs["Id"]
  type_str = lowercase(attribs["Type"]) 
  @assert type_str in keys(_ometiff_pixel_types) """
  Support for pixel type $type_str is currently not implemented.
  """
  type = _ometiff_pixel_types(type_str)
  order_str = attribs["DimensionOrder"]
  @assert order_str[1:2] == "XY" """
  Support for DimensionOrder = $order_str is currently not implemented.
  """
  # Regarding memory layout: What OmeTiff calls SizeY is apparently the
  # length of the contiguous (faster) axis in the XY-Slices stored in Tiff.
  # The length of the non-contiguous (slower) axis is denoted by SizeX.
  # Since X is usually named first in the DimensionOrder, this indicates
  # row-major indexing.
  # However, all remaining dimensions "ZCT" seem to use colum-major ordering. 
  # Phew...
  # For that reason, we are bold and call what belongs to SizeY our X-axis
  # and vice versa.
  order = DimensionOrder(order_str)
  size = map(("SizeY", "SizeX", "SizeZ", "SizeC", "SizeT")) do key
    return parse(Int, attribs[key])
  end
  return OmePixels(id, order, size, type)
end

"""
Structure that references a specific TiffData plane.

Each `OmeTiffDataPlane` object corresponds to one XY slice of the image and
contains all necessary information (path and ifd) to access the corresponding
data.
"""
struct OmeTiffDataPlane
  path::String
  uuid::String
  ifd::Int
  zct::NTuple{3, Int}
end

"""
    _ometiff_parse_tiffdata(node, fname, uuid)

Parse the information in a OME-XML `<TiffData>` node `node`.

If `node` does not contain a UUID child, use `path` and `uuid` as fallback.
"""
function _ometiff_parse_tiffdata(node, pixels, fname, uuid)
  @assert XML.tag(node) == "TiffData" """
  Expected OME-XML <TiffData> node.
  """
  attribs = XML.attributes(node)
  uuids = filter(c -> XML.tag(c) == "UUID", XML.children(node))

  @assert length(uuids) <= 1 """
  Found $(length(uuids)) <UUID> nodes in <TiffData> node. Expected 0 or 1.
  """

  if !isempty(uuids)
    uattribs = XML.attributes(uuids[1])
    fname = get(uattribs, "FileName", fname)
    uuid = XML.simple_value(uuids[1])
  end

  # Extract the idf as well as the Z, C, and T position of all planes
  # described by this TiffData node
  planecount = get(attribs, "PlaneCount", 1)
  first_idf = get(attribs, "IFD", 0)
  first_zct = (
    get(attribs, "FirstZ", 0),
    get(attribs, "FirstC", 0),
    get(attribs, "FirstT", 0),
  )

  # The planecount proceeds linearly from first_zct on, but
  # in the order described by pixels.order
  first_zct_ordered = orderpartialdims(first_zct, pixels.order)
  size_ordered = orderpartialdims(pixels.size[3:5], pixels.order)

  lindices = LinearIndices(size_ordered)
  cindices = CartesianIndices(size_ordered)
  first_linear = lindices[CartesianIndex(first_zct_ordered)]

  izcts = map(1:planecount) do index
    ifd = first_idf + (index - 1)
    zct_sorted = cindices[first_linear + (index - 1)]
    zct = revorderpartialdims(zct_sorted, pixels.order)
    (ifd, zct)
  end

  return map(izcts) do (ifd, zct)
    OmeTiffDataPlane(fname, uuid, ifd, zct)
  end
end

function _ometiff_check_tiffdata(tiffdata)
  # Get all data paths
  # Check if planes are complete and harmonize with SizeZ, SizeC, sizeT
end

#
# I found this color conversion here:
#   https://forum.image.sc/t/color-tag-in-ome-tiff-xml/48106
#
function _ometiff_parse_color(x)
  return RGBAf((x >> 24) & 0xff, (x >> 16) & 0xff, (x >> 8) & 0xff, x & 0xff)
end

function _ometiff_wavelength_to_rgb(lambda)
  lambda = clamp(lambda, 400, 675)
  hue = 270 * (lambda - 675) / 275
  return RGBf(HSV(hue, 1, 1))
end

function _ometiff_extract_channelcolor(node, index, nchannels)
  attribs = XML.attributes(node)
  if haskey(attribs, "Color")
    return _ometiff_parse_color(attribs["Color"])
  elseif haskey(attribs, "EmissionWavelength")
    return _ometiff_wavelength_to_rgb(attribs["EmissionWavelength"])
  elseif haskey(attribs, "ExcitationWavelength")
    return _ometiff_wavelength_to_rgb(attribs["ExcitationWavelength"])
  else
    @warn "Could not determine channel color. Picking a random one."
    hue = index / nchannels * 270
    return RGBf(HSV(hue, 1, 1))
  end
end

function _ometiff_channels(nodes, pixels)
  @assert length(nodes) == pixels.size[2] """
  Found more channel XML entries ($(length(nodes))) than expected \
  ($(pixels.size[2])).
  """
  # Make sure that we can read the ids and
  # that they are stored in the right order
  ids = map(nodes) do node
    attribs = XML.attributes(node)
    @assert XML.tag(node) == "TiffData" """
    Expected OME-XML <TiffData> node.
    """
    m = match(r"Channel:[0-9]+:([0-9]+)", attribs["ID"])
    @assert !isnothing(m) """
    Could not determine channel id (ID $(attribs["ID"])).
    """
    return m[1]
  end
  perm = sortperm(ids)
  return map(enumerate(nodes[perm])) do (cindex, node)
    attribs = XML.attributes(node)
    name = get(attribs, "Name", "")
    color = _ometiff_extract_channelcolor(node, cindex, length(nodes))
    return Channel(cindex, name, color)
  end
end

# TODO: I have read that there may be multiple IMAGEDESCRIPTION tags?
function _ometiff_extract_xml(tiff)
  ifds = TiffImages.ifds(tiff)
  ifd = ifds isa TiffImages.IFD ? ifds : ifds[1]
  xmlstr = ifd[TiffImages.IMAGEDESCRIPTION].data
  return XML.parse(XML.LazyNode, xmlstr)
end

function _ometiff_extract_xmlnodes(xml)
  ome = nothing
  pixels = nothing
  tiffdata = []
  channels = []
  for node in xml
    if XML.tag(node) == "OME"
      ome = node
    elseif XML.tag(node) == "Pixels"
      attribs = XML.attributes(node)
      order = attribs["DimensionOrder"]
      @assert order[1:2] in ["XY", "YX"] """
      Dimension order $order is not supported. Must start with X and Y.
      """
      pixels = node
    elseif XML.tag(node) == "TiffData"
      push!(tiffdata, node)
    elseif XML.tag(node) == "Channel"
      push!(channels, node)
    end
  end
  @assert !isnothing(ome) """
  Missing <OME> tag in OME-XML.
  """
  @assert !isnothing(pixels) """
  Missing <Pixels> tag in OME-XML.
  """
  @debug "Found <OME> node"
  @debug "Found <Pixels> node"
  @debug "Found $(length(tiffdata)) <TiffData> nodes"
  @debug "Found $(length(channels)) <Channel> nodes"
  return (; ome, pixels, tiffdata, channels)
end

"""
    _ometiff_parse_xml(xml, fname)  

Parse the OME-XML of an OME-TIFF file with filename fname.
"""
function _ometiff_parse_xml(xml, fname)
  nodes = _ometiff_extract_xmlnodes(xml)
  uuid = get(XML.attributes(nodes.ome), "UUID", nothing)
  pixels = OmePixels(nodes.pixels)
  tiffdata = mapreduce(vcat, nodes.tiffdata) do node
    _ometiff_parse_tiffdata(node, pixels, fname, uuid)
  end
  sort!(tiffdata, by = t -> t.zct)

  channels = _ometiff_channels(nodes.channels, pixels)
  return (; uuid, pixels, tiffdata, channels)
end

"""
Support for the Open Microscopy Environment (OME) Tiff format.
"""
struct OmeTiffFile <: ImageFile
  path::String
  pixels::OmePixels
  channels::Vector{Channel}
  tiff::AbstractArray{<:Gray, 5}
end

function OmeTiffFile(path::String)
  tiff = TiffImages.load(path; mmap = true, verbose = false)
  xml = _ometiff_omexml(tiff)
  pixels = _ometiff_pixels(xml)
  channels = _ometiff_channels(xml)

  # After previous attempts interchanged the X and Y axes, I found this:
  #  https://github.com/tlnagy/OMETIFF.jl/blob/a58e9369da47d02295120dbe3f1af852adf75be4/src/parsing.jl#L170C1-L170C85
  # Apparently, YX... gives the right specification for 2D slices for colum-major languages. That is, SizeY describes the length of the axis tightest in memory while SizeX corresponds to the second tightest.
  ostr = "YX" * pixels["DimensionOrder"][3:end]
  order = DimensionOrder(ostr)
  sz = map(("SizeX", "SizeY", "SizeZ", "SizeC", "SizeT")) do key
    return parse(Int, pixels[key])
  end
  sz = orderdims(sz, order)
  # We always expect that TiffImages has gotten the first two dimensions right
  @assert sz[1:2] == size(tiff)[1:2] """
  Inconsistency of XY dimensions between metadata and loaded tiff image.
  """
  @assert prod(sz) == prod(size(tiff)) """
  Inconsistency between shape metadata and loaded tiff image.
  """
  tiff = reshape(tiff, sz)
  dims = (order.x, order.y, order.z, order.c, order.t)
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

planesize(img::OmeTiffFile) = (size(img.tiff)[2], size(img.tiff)[1])

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
      Could not determine channel name. Falling back to 'Channel $cindex'
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

function imagedata(img::OmeTiffFile, zindex, cindex, tindex)
  slice = @view img.tiff[:, :, zindex, cindex, tindex]
  slice = ImageCore.channelview(slice) # remove color wrapper (Gray)
  slice = reinterpret.(slice) # remove Normed FixedPointNumber
  return reinterpret(UInt8, slice)
end

registerformat!(OmeTiffFile)
