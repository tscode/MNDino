
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
    _ometiff_read_pixels(node)

Create an OmePixels object from a OME-XML `<Pixels>` node `node`.
"""
function _ometiff_read_pixels(node)
  @debug "Reading the <Pixels> node of OME-XML"
  @assert XML.tag(node) == "Pixels" """
  Expected OME-XML <Pixels> node.
  """
  attribs = XML.attributes(node)
  id = attribs["Id"]
  @debug "Found pixels id $id" 
  type_str = lowercase(attribs["Type"]) 
  @debug "Found pixels element type $type_str"
  @assert type_str in keys(_ometiff_pixel_types) """
  Support for pixel type $type_str is currently not implemented.
  """
  type = _ometiff_pixel_types(type_str)
  order_str = attribs["DimensionOrder"]
  @debug "Found pixels dimension order $order_str"
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
    _ometiff_read_tiffdata(node, fname, uuid)

Parse the information in a OME-XML `<TiffData>` node `node`.

If `node` does not contain a UUID child, use `path` and `uuid` as fallback.
"""
function _ometiff_read_tiffdata(node, pixels, fname, uuid)
  @debug "Reading a <TiffData> node of OME-XML"
  @assert XML.tag(node) == "TiffData" """
  Expected OME-XML <TiffData> node.
  """
  attribs = XML.attributes(node)
  uuids = filter(c -> XML.tag(c) == "UUID", XML.children(node))
  @debug "Found tiff data UUID tags: $uuids"
  @assert length(uuids) <= 1 """
  Found $(length(uuids)) <UUID> nodes in <TiffData> node. Expected 0 or 1.
  """
  if !isempty(uuids)
    uattribs = XML.attributes(uuids[1])
    uuid = XML.simple_value(uuids[1])
    @debug "Found tiff data UUID tag: $uuid"
    if haskey(uattribs, "FileName")
      fname = uattribs["FileName"]
      @debug "Found FileName attribute in UUID node: $fname"
    else
      fname = nothing
      @debug "Found no FileName attribute in UUID node"
    end
  end

  # Extract the ifd as well as the Z, C, and T position of all planes
  # described by this TiffData node
  planecount = get(attribs, "PlaneCount", 1)
  @debug "Found plane count $planecount"
  first_ifd = get(attribs, "IFD", 0)
  @debug "Found first ifd $first_ifd"
  first_zct = (
    get(attribs, "FirstZ", 0),
    get(attribs, "FirstC", 0),
    get(attribs, "FirstT", 0),
  )
  @debug "Found first zct index $first_zct"

  # The planecount proceeds linearly from first_zct on, but
  # in the order described by pixels.order
  first_zct_ordered = orderpartialdims(first_zct, pixels.order)
  size_ordered = orderpartialdims(pixels.size[3:5], pixels.order)

  lindices = LinearIndices(size_ordered)
  cindices = CartesianIndices(size_ordered)
  first_linear = lindices[CartesianIndex(first_zct_ordered)]

  izcts = map(1:planecount) do index
    ifd = first_ifd + (index - 1)
    zct_sorted = cindices[first_linear + (index - 1)]
    zct = revorderpartialdims(zct_sorted, pixels.order)
    (ifd, zct)
  end

  return map(izcts) do (ifd, zct)
    OmeTiffDataPlane(fname, uuid, ifd, zct)
  end
end

function _ometiff_rearrange_planes(planes, pixels)
  @debug "Rearranging the planes vector"
  @assert length(planes) == prod(pixels.size[3:5]) """
  Number of TIFF data planes ($(length(planes))) does not match \
  number of planes announced by the <Pixels> node.
  """
  # Bring planes into a 3d grid where the cartesian index coincides with
  # the zct tuple
  planes = sort(planes, by = t -> t.zct)
  planes = reshape(planes, pixels.size[3:5])
  planes_complete = all(CartesianIndices(planes)) do c
    planes[c].zct == Tuple(c)
  end
  @assert planes_complete """
  Not all planes announced by the <Pixels> node could be identified.
  """
  return planes
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

function _ometiff_read_channelcolor(node, index, nchannels)
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

function _ometiff_read_channels(nodes, pixels)
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
    color = _ometiff_read_channelcolor(node, cindex, length(nodes))
    return Channel(cindex, name, color)
  end
end

# TODO: I have read that there may be multiple IMAGEDESCRIPTION tags?
function _ometiff_extract_xml(tiff)
  @debug "Extracting OME-XML from IMAGEDESCRIPTION tag of the provided tiff"
  ifds = TiffImages.ifds(tiff)
  ifd = ifds isa TiffImages.IFD ? ifds : ifds[1]
  xmlstr = ifd[TiffImages.IMAGEDESCRIPTION].data
  return XML.parse(XML.LazyNode, xmlstr)
end

"""
    _ometiff_extract_xmlnodes(xml)

Return a named tuple containing the relevant xml nodes in the passed
OME XML `xml`.
"""
function _ometiff_extract_xmlnodes(xml)
  @debug "Filtering relevant nodes from OME-XML"
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
  @debug "Found <OME> node"
  @assert !isnothing(pixels) """
  Missing <Pixels> tag in OME-XML.
  """
  @debug "Found <Pixels> node"
  @debug "Found $(length(tiffdata)) <TiffData> nodes"
  @debug "Found $(length(channels)) <Channel> nodes"
  return (; ome, pixels, tiffdata, channels)
end

"""
    _ometiff_extract_paths(planes)

Extract all tiff file paths that are referenced in the `<TiffData>` nodes
read by `planes`.
"""
function _ometiff_extract_paths(planes, dir)
  @debug "Extracting tiff file paths"
  uuid_paths = map(planes) do td
    @assert !isnothing(td.fname) """
    Lookup of tiff file by UUID alone is currently not supported
    """
    path = joinpath(dir, td.fname)
    @assert Base.isfile(path) """
    Expected file at $path.
    """
    uuid => path
  end
  uuid_paths = unique(uuid_paths)
  @debug "Found $(length(uuid_paths)) UUID-path pairs"
  for (u1, p1) in uuid_paths, (u2, p2) in uuid_paths
    if u1 == u2
      @assert p1 == p2 """
      Inconsistency when extracting tiff paths: UUID $u1 is assigned to files \
      $p1 and $p2.
      """
    elseif p1 == p2
      @assert u1 == u2 """
      Inconsistency when extracting tiff paths: Path $p1 is assigned UUID \
      $u1 and $u2.
      """
    end
  end
  return Dict(uuid_paths)
end

"""
    _ometiff_parse_xml(xml, fname) 

Read the OME-XML of an OME-TIFF file with filename `fname`.
"""
function _ometiff_parse_xml(xml, fname, dir)
  nodes = _ometiff_extract_xmlnodes(xml)
  uuid = get(XML.attributes(nodes.ome), "UUID", nothing)
  @debug "OME-XML has UUID $uuid"
  pixels = _ometiff_read_pixels(nodes.pixels)
  planes = mapreduce(vcat, nodes.tiffdata) do node
    _ometiff_read_planes(node, pixels, fname, uuid)
  end
  planes = _ometiff_rearrange_planes(planes, pixels)
  @debug "Parsing channels"
  channels = _ometiff_read_channels(nodes.channels, pixels)
  paths = _ometiff_extract_paths(planes, dir)
  return (; uuid, pixels, planes, paths, channels)
end

function _ometiff_load_xml(path)
  @debug "Trying to extract OME-XML from $path"
  if lowercase(splitext(path)[2]) == ".ome"
    xml = open(path) do io
      read(io, XML.Node)
    end
    fname = nothing
  else
    tiff = TiffImages.load(path; mmap = true, verbose = false)
    xml = _ometiff_extract_omexml(tiff)
    close(tiff)
    fname = Base.basename(path)
  end
  @debug "Sucessfully extracted OME-XML from $path"
  return _ometiff_parse_xml(xml, fname, Base.dirname(path))
end

"""
Support for the Open Microscopy Environment (OME) Tiff format.
"""
struct OmeTiffFile <: ImageFile
  path::String
  pixels::OmePixels
  channels::Vector{Channel}
  planes::Array{3, OmeTiffDataPlane}
  tiffs::Dict{String, AbstractArray{<:Gray, 5}}
end

function OmeTiffFile(path::String)
  meta = _ometiff_load_xml(path)
  sz = meta.pixels.size[1:2]
  tiffs = map(pairs(meta.paths)) do (uuid, fname)
    p = joinpath(dirname(path), fname)
    @debug "Loading TIFF file $p with expected UUID $uuid."
    m = _ometiff_load_xml(p)
    @assert m.uuid == uuid """
    Expected UUID $uuid but found $(m.uuid) in file $p.
    """
    tiff = TiffImages.load(path; mmap = true, verbose = false)
    @assert size(tiff)[1:2] == sz """
      Expected XY dimensions $sz but file $p has dimensions $(size(tiff)[1:2]).
    """
    @debug "Loading TIFF file $p was successfull."
    uuid => tiff
  end
  tiffs = Dict(tiffs)

  return OmeTiffFile(path, meta.pixels, meta.channels, meta.order, tiffs)
end

extensions(::Type{OmeTiffFile}) = [".ome", ".ome.tif", ".ome.tiff"]
location(img::OmeTiffFile) = img.path

# From what I know, OMETIFF files do not store multiple versions / variants
# Update: There seems to be an option for "pyramidal" OMETIFF images in newer versions. For now, we do not support this.
variants(::OmeTiffFile) = (;)

nzlayers(img::OmeTiffFile) = img.pixels.size[3]
nchannels(img::OmeTiffFile) = img.pixels.size[4]
ntlayers(img::OmeTiffFile) = img.pixels.size[5]
planesize(img::OmeTiffFile) = img.pixels.size[1:2]

variantdefault(::OmeTiffFile) = (;)
tindexdefault(img::OmeTiffFile) = 1

function zindexdefault(img::OmeTiffFile)
  nz = nzlayers(img)
  return max(div(nz, 2), 1)
end

channels(img::OmeTiffFile) = img.channels

function metadata(img::OmeTiffFile)
  return (
    resolution = size(img.tiff)[1:2],
    channels = channels(img),
  )
end

function imagedata(img::OmeTiffFile, zindex, cindex, tindex)
  plane = img.planes[zindex, cindex, tindex]
  tiff = img.tiffs[plane.uuid]
  slice = @view tiff[:, :, plane.ifd]]
  return slice

  # slice = @view img.tiff[:, :, zindex, cindex, tindex]
  # slice = ImageCore.channelview(slice) # remove color wrapper (Gray)
  # slice = reinterpret.(slice) # remove Normed FixedPointNumber
  # return reinterpret(UInt8, slice)
end

registerformat!(OmeTiffFile)
