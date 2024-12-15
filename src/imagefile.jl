

"""
Default channel colors if they cannot be derived from metadata.
"""
const _default_colors = [
  colorant"red",
  colorant"green",
  colorant"blue",
  colorant"orange",
  colorant"purple",
]

function _getcolor(index)
  index = mod1(index, length(_default_colors))
  return _default_colors[index]
end


"""
Metadata object for an image channel.

Stores the index of the channel in the image, the channel name, and the channel color.
"""
struct Channel
  cindex::Int
  name::String
  color::RGBf
end

@pack Channel in Pack.MapFormat color in Pack.MapFormat

struct ChannelSlice{M <: AbstractMatrix}
  cindex::Int
  name::String
  color::RGBf
  data::M
end

"""
The dimension ordering of an 5d (XYZCT) image array.
"""
struct DimensionOrder
  x::Int
  y::Int
  z::Int
  c::Int
  t::Int
end

"""
    DimensionOrder(str)  

Obtain the dimension ordering from the string `str`.

This string must only contain a subset of the symbols "XYZCT", where "X" and "Y"
are required and "ZCT" are optional.
"""
function DimensionOrder(str)
  keys = ['x', 'y', 'z', 'c', 't']
  lstr = lowercase(str)
  @assert all(s -> s in keys, collect(lstr)) """
  Dimension string '$str' contains unrecognized dimensions.
  """
  indices = map(keys) do key
    index = findfirst(key, lstr)
    index = isnothing(index) ? 0 : index
    @assert 0 <= index <= 5
    return index
  end
  @assert indices[1] > 0 && indices[2] > 0 """
  Dimension string '$str does not contain X or Y dimension.
  """
  return DimensionOrder(indices...)
end

"""
    orderdims(s, order::DimensionOrder) 

Adapt the input tuple `s`, which is assumed to be in XYZCT ordering, to the
ordering defined by `order`.
"""
function orderdims(s, order::DimensionOrder)
  pairs = map(k -> k => getfield(order, k), [:x, :y, :z, :c, :t])
  perm = sortperm(pairs, by = pair -> pair[2])
  filter!(index -> pairs[index][2] != 0, perm)
  return Tuple(s[index] for index in perm)
end

"""
Wrapper of an image file.

The image files of interest for MNDino, particularly microscopy images, are
often stored in complex formats that allow for lazy and partial reading of
slices of the data.

At the very least, an image collects 2D intensity information (X and Y
dimensions) for a specific number of channels (C dimension).
Usually several layers of such information are stacked along a Z dimension and
sometimes an additional T (time) dimension.

Depending on the specific format, varying amounts of metadata can be stored.
In some cases, variants of the imaging data, like different resolution levels,
are stored as well.
"""
abstract type ImageFile end

"""
    location(img::ImageFile) 

Returns the location (path) of an image on the hard drive.

Returns the empty string `""` if no meaningful path exists.
"""
function location(::ImageFile)
  return ""
end

"""
    extensions(I::Type{<: ImageFile}) 
    extensions(img::ImageFile) 

List of supported file extensions for the image file backend I.
"""
extensions(::I) where {I <: ImageFile} = extensions(I)

"""
    nchannels(img::ImageFile)

Return the number of channels of `img`.
"""
function nchannels end

"""
    nzlayers(img::ImageFile)

Return the number of Z-layers of `img`
"""
function nzlayers end

"""
    variants(img::ImageFile)

Returns a named tuple of variant information of `img`.

An example could be `variants(img) = (resolution = 0:4)` if `img`
contains imaging data for `5` resolution levels. This is common for the Imaris
file format (supported by`ImarisFile`).
"""
function variants end

"""
    variantdefault(img::ImageFile)

Returns the default variant of `img`.
"""
function variantdefault end

"""
    zindexdefault(img::ImageFile)

Returns a default valid z-index of `img`.
"""
function zindexdefault end

"""
    tindexdefault(img::ImageFile)

Returns a default valid t-index of `img`.
"""
function tindexdefault end

"""
    channels(img::ImageFile) 

Retrive the channel specification of `img`.

The channels must be ordered according to their channel index.
See [`Channel`](@ref) for more details.
"""
function channels end

"""
    channelnames(img::ImageFile)  

Retrieve all channel names of `img`.
"""
function channelnames(img::ImageFile)
  return map(c -> c.name, channels(img))
end

"""
    channelname(img::ImageFile, cindex) 

Retrieve the name of the channel at `cindex`.

"""
function channelname(img::ImageFile, cindex)
  return channelnames(img)[cindex]
end

"""
    channelcolors(img::ImageFile)  

Retrieve all channel colors of `img`.

See also [`channelcolor`](@ref).
"""
function channelcolors(img::ImageFile)
  return map(c -> c.color, channels(img))
end

"""
    channelcolor(img::ImageFile, cindex) 

Retrieve the color of the channel at `cindex`.

See also [`channelcolors`](@ref).
"""
function channelcolor(img::ImageFile, cindex)
  return channelcolors(img)[cindex]
end

"""
    metadata(img::ImageFile; kwargs...)

Retrieve a named tuple of common metadata information about `img`. 

The returned metadata object will depend on the image file format and
the loader capabilities.

Additional keyword arguments specify the variant of `img`.
"""
function metadata end

"""
    imagedata(img::ImageFile; kwargs...)

Retrieve the full image data stored in `img`.

Additional keyword arguments specify the variant of `img`.

!!! note

    Depending on the image and the backend, this operation can potentially be
    slow and memory intensive. Some backends will for this reason not implement
    `imagedata(img)` and may require scalars for indexing.

---

    imagedata(img::ImageFile, cindex, zindex, tindex; kwargs...)

Retrieve the 2d slice of image data stored at a given index for the channel, z
dimension, and time dimension.

Additional keyword arguments specify the variant of `img`.
"""
function imagedata end

function imagedata(img::I; kwargs...) where {I <: ImageFile}
  error("""
  Image file backend $I does not support collecting the full image data
  """)
end

"""
Global image format storage.

Can be extended by registering new subtypes of
`[ImageFile](@ref)` via `[registerformat!](@ref)`.
"""
const IMAGE_FORMATS = Dict{String, Type{<: ImageFile}}()

function registerformat!(::Type{I}) where {I <: ImageFile}
  exts = extensions(I)
  for ext in exts
    @assert !haskey(IMAGE_FORMATS, ext) """
    Image file extension $ext is already registered.
    """
    IMAGE_FORMATS[ext] = I
  end
  return
end

function fitsextension(path, I ::Type{<: ImageFile})
  return any(extensions(I)) do ext
    re = Regex(ext * "\$")
    !isnothing(match(re, path))
  end
end

"""
    loadimagefile(path)

Load the image file located at `path`.
"""
function loadimagefile(path)
  exts = collect(keys(IMAGE_FORMATS))
  # check all extensions against the file name
  exts = filter(exts) do ext
    re = Regex(ext * "\$")
    !isnothing(match(re, path))
  end
  @assert !isempty(exts) """
  Unsupported extension at '$path'. 
  """
  # pick the longest match. E.g., this would pick ".ome.tiff" over ".tiff"
  exts = sort(exts, by = length)
  I = IMAGE_FORMATS[exts[end]]
  return I(path)
end
