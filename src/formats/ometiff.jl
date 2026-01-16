
module OmeTiff

using XML
using Colors
using TiffImages

using ..MNDino: ImageFile
using ..MNDino: Channel
using ..MNDino: DimensionOrder, orderpartialdims, revorderpartialdims

"""
Constant dictionary that maps OME-TIFF pixel type strings to julia types.
"""
const PIXEL_TYPES = Dict(
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
Structure derived from the <Pixels> node in an OME-XML.
"""
struct Pixels
  id::String
  order::DimensionOrder
  size::NTuple{5, Int}
  type::DataType
end

"""
    parse_pixels_node(node)

Create a `Pixels` object from a given OME-XML <Pixels> node.
"""
function parse_pixels_node(node)
  @debug "Reading the <Pixels> node of OME-XML"
  @assert XML.tag(node) == "Pixels" """
  Expected OME-XML <Pixels> node.
  """
  attribs = XML.attributes(node)
  id = attribs["ID"]
  @debug "Found pixels id $id" 
  type_str = lowercase(attribs["Type"]) 
  @debug "Found pixels element type $type_str"
  @assert type_str in keys(PIXEL_TYPES) """
  Support for pixel type $type_str is not implemented.
  """
  type = PIXEL_TYPES[type_str]
  order_str = attribs["DimensionOrder"]
  @debug "Found pixels dimension order $order_str"
  @assert order_str[1:2] == "XY" """
  Support for the dimension order $order_str is currently not implemented.
  """
  # Regarding memory layout: What OmeTiff calls SizeY is apparently the
  # length of the contiguous (faster) axis in the XY-Slices stored in Tiff.
  # The length of the non-contiguous (slower) axis is denoted by SizeX.
  # Since X is usually named first in the DimensionOrder, this indicates
  # row-major indexing.
  # However, all remaining dimensions "ZCT" seem to use colum-major ordering,
  # i.e., in case of XYZCT the dimension Z would iterate the fastest, then C and
  # then T.
  # Phew...
  # For that reason, we are pragmatic and call what corresponds to SizeY our
  # X-axis and vice versa.
  order = DimensionOrder(order_str)
  size = map(("SizeY", "SizeX", "SizeZ", "SizeC", "SizeT")) do key
    return parse(Int, attribs[key])
  end
  return Pixels(id, order, size, type)
end

"""
Structure that references a specific plane associated to a <TiffData> node.

Each plane corresponds to a XY slice of the image. An instance of `Plane`
contains all necessary information (in particular the filename and ifd
(1-based)) to access the corresponding slice data. It additionally stores the
uuid of the file and the ZCT indices (1-based).
"""
struct Plane
  fname::String
  uuid::String
  ifd::Int
  zct::NTuple{3, Int}
end

"""
    parse_tiffdata_node(node, pixels, fname, uuid)

Parse the information in an OME-XML <TiffData> node. The argument `pixels` of 
type `Pixels` is needed to access the dimension ordering and the image size.

Return a vector of `Plane` objects.

If `node` does not contain a <UUID> child, use `fname` and `uuid` as fallback.
"""
function parse_tiffdata_node(node, pixels, fname, uuid)
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
    children = XML.children(uuids[1])
    @assert length(children) == 1 && XML.nodetype(children[1]) == XML.Text """
    Expected single text node as child of <UUID> node.
    """
    uuid = XML.value(children[1])
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
  planecount = parse(Int, get(attribs, "PlaneCount", "1"))
  @debug "Found plane count $planecount"
  first_ifd = parse(Int, get(attribs, "IFD", "0")) .+ 1
  @debug "Found first ifd $first_ifd"
  first_zct = (
    parse(Int, get(attribs, "FirstZ", "0")),
    parse(Int, get(attribs, "FirstC", "0")),
    parse(Int, get(attribs, "FirstT", "0")),
  ) .+ 1
  @debug "Found first zct index $first_zct ($(first_zct .- 1) in 0-based indexing)"

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
    Plane(fname, uuid, ifd, zct)
  end
end

function rearrange_planes(planes, pixels)
  @debug "Rearranging the planes vector"
  @assert length(planes) == prod(pixels.size[3:5]) """
  Number of TIFF data planes ($(length(planes))) does not match \
  number of planes announced by the <Pixels> node.
  """
  # Bring planes into a 3d grid where the cartesian index coincides with
  # the zct tuple
  planes = sort(planes, by = t -> reverse(t.zct))
  planes = reshape(planes, pixels.size[3:5])
  planes_complete = all(CartesianIndices(planes)) do c
    planes[c].zct == Tuple(c)
  end
  @assert planes_complete """
  Not all planes announced by the <Pixels> node could be identified.
  """
  return planes
end

"""
    resolve_path(fname, uuid, dir)

Given either a filename `fname` or `uuid` (or both), resolve the path in
the directory `dir`.
"""
function resolve_path(fname, uuid, dir)
  if isnothing(fname)
    error("Lookup of tiff file by UUID alone is currently not supported")
  else
    path = joinpath(dir, fname)
    @assert Base.isfile(path) """
    Expected file at $path
    """
    if !isnothing(uuid)
      # TODO: This check here is *very* costly if the disk is slow!
      # I have to find another way to check the uuid for consistency.
      # Probably by using an uuid-cache that stores the uuid of every file that has been looked at once.
      #
      # @assert uuid == load_uuid(path) """
      # Given UUID $uuid does not match UUID $(load_uuid(path)) of the file $path.
      # """
    end
    return path
  end
end


"""
    collect_paths(planes, dir)

Collect all tiff file paths that are referenced in the vector of `Plane` objects
`planes`.

The directory `dir` is required since each `Plane` object only stores the file name.
"""
function collect_paths(planes, dir)
  @debug "Extracting tiff file paths"
  uuid_paths = map(planes) do plane
    path = resolve_path(plane.fname, plane.uuid, dir)
    plane.uuid => path
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
    parse_channelcolor(node, index, nchannels)

Parse the color of an OME-XML <Channel> node.

If no color is specified (via a color or wavelength attribute), pick a
color that is linearly spaced in hue corresponding to the fraction of `index`
in `nchannels`.
"""
function parse_channelcolor(node, index, nchannels)
  attribs = XML.attributes(node)
  if haskey(attribs, "Color")
    color_int = parse(Int32, attribs["Color"])
    return parse_color(color_int)
  elseif haskey(attribs, "EmissionWavelength")
    lambda = parse(Int, attribs["EmissionWavelength"])
    return wavelength_to_rgb(lambda)
  elseif haskey(attribs, "ExcitationWavelength")
    lambda = parse(Int, attribs["EmissionWavelength"])
    return wavelength_to_rgb(lambda)
  else
    @warn "Could not determine channel color. Picking a random one."
    hue = index / nchannels * 270
    return RGB{Float32}(HSV(hue, 1, 1))
  end
end

function parse_color(x)
  # I found this color conversion here:
  #   https://forum.image.sc/t/color-tag-in-ome-tiff-xml/48106
  return RGBA{Float32}(
    (x >> 24) & 0xff,
    (x >> 16) & 0xff,
    (x >> 8) & 0xff,
    x & 0xff,
  )
end

function wavelength_to_rgb(lambda)
  lambda = clamp(lambda, 400, 675)
  hue = 270 * (675 - lambda) / 275
  return RGB{Float32}(HSV(hue, 1, 1))
end

"""
    parse_channels(nodes, pixels)

Parse a vector of OME-XML <Channel> nodes and return a vector of `Channel`
objects.
"""
function parse_channels(nodes, pixels)
  @assert length(nodes) == pixels.size[4] """
  Unexpected number of <Channel> nodes ($(length(nodes)) instead of $(pixels.size[4])).
  """
  # Make sure that we can read the ids and
  # that they are stored in the right order
  ids = map(nodes) do node
    attribs = XML.attributes(node)
    @assert XML.tag(node) == "Channel" """
    Expected OME-XML <Channel> node.
    """
    m = match(r"Channel:([0-9:]+)", attribs["ID"])
    @assert !isnothing(m) """
    Could not determine channel id (ID $(attribs["ID"])).
    """
    @debug "Extracted channel ID $(m[1])"
    return m[1]
  end
  perm = sortperm(ids)
  @assert all(perm .== 1:length(ids)) """
  Channel ordering is unresolved. Order in OME-XML does not fit channel IDs.
  """
  return map(enumerate(nodes[perm])) do (cindex, node)
    attribs = XML.attributes(node)
    name = get(attribs, "Name", "channel $cindex")
    color = parse_channelcolor(node, cindex, length(nodes))
    return Channel(cindex, name, color)
  end
end

"""
    extract_nodes(xml)

Return a named tuple containing the relevant xml nodes in the passed OME-XML.
"""
function extract_nodes(xml)
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
    parse_xml(xml, fname, dir) 

Read the OME-XML of an OME-TIFF file with filename `fname` in the directory `dir`.
"""
function parse_xml(xml, fname, dir)
  nodes = extract_nodes(xml)
  uuid = get(XML.attributes(nodes.ome), "UUID", nothing)
  @debug "OME-XML has UUID $uuid"
  pixels = parse_pixels_node(nodes.pixels)
  planes = mapreduce(vcat, nodes.tiffdata) do node
    parse_tiffdata_node(node, pixels, fname, uuid)
  end
  planes = rearrange_planes(planes, pixels)
  paths = collect_paths(planes, dir)
  @debug "Parsing channels"
  channels = parse_channels(nodes.channels, pixels)
  return (; uuid, pixels, planes, paths, channels)
end

"""
    load_uuid(path)

Load the UUID of the OME file at `path`.
"""
function load_uuid(path)
  @debug "Loading OME-XML UUID of file $path"
  xml = load_xml(path, accept_partial = true)
  for node in xml
    if XML.tag(node) == "OME"
      attribs = XML.attributes(node)
      @assert haskey(attribs, "UUID") """
      Error when loading uuid: <OME> node misses UUID attribute.
      """
      return attribs["UUID"]
    end
  end
  error("Obtaining uuid of file $path failed")
end

"""
    load_xml(path; accept_partial = false)

Load the OME-XML stored in the file at `path`.

This can either point to a `.ome` XML file or to a `.ome.tiff` (or similar) OME-TIFF file.

If `accept_partial = true`, XMLs that only contain partial OME metadata are
accepted as well. This for example happens for OME-TIFF files with <BinaryOnly>
node.
"""
function load_xml(path; accept_partial = false)
  @debug "Trying to extract OME-XML from $path"
  if lowercase(splitext(path)[2]) == ".ome"
    xml = open(path) do io
      read(io, XML.LazyNode)
    end
  else
    @debug "Loading TIFF file $path to access OME-XML"
    tiff = TiffImages.load(path; mmap = true, verbose = false)
    xml = extract_xml(tiff, Base.dirname(path); accept_partial)
  end
  @debug "Successfully extracted OME-XML from $path"
  return xml
end

function extract_xml(tiff, dir; accept_partial = false)
  @debug "Extracting OME-XML from IMAGEDESCRIPTION tag of the provided tiff"
  ifds = TiffImages.ifds(tiff)
  ifd = ifds isa TiffImages.IFD ? ifds : ifds[1]
  xmlstr = ifd[TiffImages.IMAGEDESCRIPTION].data
  xml = XML.parse(XML.LazyNode, String(xmlstr))
  if !accept_partial
    for node in xml
      if XML.tag(node) == "BinaryOnly"
        attribs = XML.attributes(node)
        fname = get(attribs, "MetadataFile", nothing)
        uuid = get(attribs, "UUID", nothing)
        @info """
        Given OME-TIFF file has <BinaryOnly> node.
        Looking at $fname with UUID $uuid for metadata.
        """
        path = resolve_path(fname, uuid, dir)
        return load_xml(path)
      end
    end
  end
  return xml
end


"""
Support for the Open Microscopy Environment (OME) Tiff format.
"""
struct OmeTiffFile <: ImageFile
  path::String
  pixels::Pixels
  channels::Vector{Channel}
  planes::Array{Plane, 3}
  tiffs::Dict{String, AbstractArray{<:Gray, 3}}
end

function OmeTiffFile(path::String; layout = :auto)
  xml = load_xml(path)
  meta = parse_xml(xml, Base.basename(path), Base.dirname(path))
  sz = meta.pixels.size[1:2]
  tiffs = map(collect(meta.paths)) do (uuid, path_tiff)
    uuid_loaded = load_uuid(path_tiff)
    @assert uuid == uuid_loaded """
    Expected UUID $uuid but found $uuid_loaded in file $path_tiff.
    """
    tiff = TiffImages.load(path_tiff; mmap = true, verbose = false)
    @assert size(tiff)[1:2] == sz """
      Expected XY dimensions $sz but file $p has dimensions $(size(tiff)[1:2]).
    """
    @debug "Loading TIFF file $path was successfull."
    uuid => tiff
  end
  tiffs = Dict(tiffs)

  return OmeTiffFile(path, meta.pixels, meta.channels, meta.planes, tiffs)
end

end # module OmeTiff

using .OmeTiff: OmeTiffFile

extensions(::Type{OmeTiffFile}) = [".ome", ".ome.tif", ".ome.tiff", ".ome.tf2"]
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
    resolution = img.pixels.size[1:2],
    channels = channels(img),
  )
end

function imagedata(img::OmeTiffFile, zindex, cindex, tindex)
  plane = img.planes[zindex, cindex, tindex]
  tiff = ImageCore.channelview(img.tiffs[plane.uuid])
  slice = @view tiff[:, :, plane.ifd]

  # It is crucial for other parts of the program that planesize predicts the
  # right plane size
  @assert size(slice) == planesize(img) """
  Inconsistent plane dimensions: <Pixels> node says $(planesize(img)),\
  but actual tiff data says $(size(slice)).
  """
  return reinterpret.(slice) # remove Normed FixedPointNumber
end

registerformat!(OmeTiffFile)
