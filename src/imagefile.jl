
"""
Wrapper of an microscopy imaging file.

Optical microscopy imaging data is often stored in more or less sophisticated
file formats that allow for lazy and partial reading of slices of imaging data.

At the very least, an `ImageFile` collects 2D intensity information (represented
as `Matrix`) for a specific number of channels (or colors). Usually several
layers of such information along the Z-dimension are stacked. Sometimes,
variants of imaging data (like images for different timepoints or resolution
levels) are stored as well.
"""
abstract type ImageFile end

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
contains imaging data for `5` resolution levels.
"""
function variants end

"""
    defaultvariant(img::ImageFile)

Returns the default variant of `img`.
"""
function variantdefault end

"""
    defaultzindex(img::ImageFile)

Returns a default valid z-index of `img`.
"""
function zindexdefault end

"""
    channelnames(img::ImageFile)  

Retrieve all channel names of `img`.

See also [`channelname`](@ref).
"""
function channelnames end

"""
    channelname(img::ImageFile, cindex) 

Retrieve the name of the channel at `cindex`.

See also [`channelnames`](@ref).
"""
function channelname end

"""
    channelcolors(img::ImageFile)  

Retrieve all channel colors of `img`.

See also [`channelcolor`](@ref).
"""
function channelcolors end

"""
    channelcolor(img::ImageFile, cindex) 

Retrieve the color of the channel at `cindex`.

See also [`channelcolors`](@ref).
"""
function channelcolor end

"""
    metadata(img::ImageFile, cindex; kwargs...)

Retrieve a named tuple of metadata information about the channel with
channel index `cindex`.

Additional keyword arguments specify the variant of `img`.
"""
function metadata end

"""
    imagedata(img::ImageFile; kwargs...)
    imagedata(img::ImageFile, cindex, zindex, tindex; kwargs...)

Retrieve the full image data stored in `img`.

The image data will typically be a dense multidimensional array with the
dimensions (c, x, y, z, t). Slices can be obtained by additionally providing `cindex`, `zindex`, and `tindex`.

Additional keyword arguments specify the variant of `img`.

!!! note

    Depending on the image and the backend, this operation can potentially be
    slow and memory intensive. Some backends will for this reason not implement
    `imagedata(img)` and may require scalars for indexing.
"""
function imagedata end

function imagedata(img::I; kwargs...) where {I <: ImageFile}
  error("""
  The image file backend I does not support retrieving the full image data
  """)
end

"""
    location(img::ImageFile) 

Returns the location (path) of an image on the hard drive.

Returns the empty string `""` if no meaningful path exists.
"""
function location(::ImageFile)
  return ""
end

"""
Global format storage. Can be extended by registering new subtypes of
`ImageFile`.
"""
const IMAGE_FORMATS = Dict{String, Type{<: ImageFile}}()

function register_format!(::Type{I}) where {I <: ImageFile}
  exts = extensions(I)
  for ext in exts
    IMAGE_FORMATS[ext] = I
  end
  return
end

"""
    loadimagefile(path)

Load the image file located at `path`.
"""
function loadimagefile(path)
  _, ext = splitext(path)
  @assert ext in keys(IMAGE_FORMATS) """
  Unsupported extension $ext at $path. 
  """
  I = IMAGE_FORMATS[ext]
  return I(path)
end
