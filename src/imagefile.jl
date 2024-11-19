
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

extension(::I) where {I <: ImageFile} = extension(I)

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

An example could be `variants(img) = (time = 0:10, resolution = 0:4)` if `img`
contains imaging data for `11` time points and `4` resolution levels.
"""
function variants end

"""
    defaultvariant(img::ImageFile)

Returns the default variant of `img`.
"""
function defaultvariant end

"""
    defaultzindex(img::ImageFile)

Returns a default valid z-index of `img`.
"""
function defaultzindex end

"""
    metadata(img::ImageFile, cindex; variant_options...)

Retrieve a named tuple of metadata information about the image slice with
channel index `cindex`. Additional options rely on `img`.

This operation should be fast.
"""
function metadata end

"""
    channelname(img::ImageFile, cindex; variant_options...) 

Retrieve the name of the channel at `cindex`.
"""
function channelname end

"""
    channelcolor(img::ImageFile, cindex; variant_options...) 

Retrieve the color of the channel at `cindex`.
"""
function channelcolor end

"""
    imagedata(img::ImageFile, zindex, cindex; variant_options...)

Retrieve the intensity information of the image slice with Z index `zindex` and
channel index `cindex`. Additional options rely on `img`.

Depending on the image, this operation can potentially be slow and memory
intensive.
"""
function imagedata end

"""
Global format storage. Can be extende by new subtypes of `ImageFile`.
"""
const FORMATS = Dict{String, Type{<: ImageFile}}()

function register_format!(::Type{I}) where {I <: ImageFile}
  ext = extension(I)
  FORMATS[ext] = I
  return
end

"""
    loadimagefile(path)

Load the image file located at `path`.
"""
function loadimagefile(path)
  _, ext = splitext(path)
  @assert ext in keys(FORMATS) """
  Unsupported extension $ext at $path. 
  """
  I = FORMATS[ext]
  return I(path)
end
