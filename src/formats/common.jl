
"""
Support for common image formats like PNG or JPG via ImageIO.jl.

Images are loaded into memory greedily. Large images should therefore use a
different backend.

Note that slices along a potential third axis (e.g., for GIF files) are
interpreted as time frames and not as z stacks.
"""
struct CommonImageFile{C <: Colors.Colorant} <: ImageFile
  path::String
  data::Array{C, 4}
end

function CommonImageFile(path::String)
  data = FileIO.load(path)
  @assert data isa Array{<:Colors.Colorant} """
  The specified path does not point to an image of proper array type.
  """
  @assert 2 <= length(size(data)) <= 3 """
  The CommonImageFile backend only handles 2D (x, y) or 3D (x, y, t) images.
  """
  if length(size(data)) == 2
    data = reshape(data, size(data)..., 1, 1)
  else
    data = reshape(data, size(data)[1:2]..., 1, size(data, 3))
  end
  return CommonImageFile(path, data)
end

extensions(::Type{CommonImageFile}) = [".png", ".jpg", ".jpeg", ".gif"]
location(img::CommonImageFile) = img.path
variants(::CommonImageFile) = (;)

variantdefault(::CommonImageFile) = (;)
zindexdefault(img::CommonImageFile) = 1
tindexdefault(img::CommonImageFile) = 1

planesize(img::CommonImageFile) = size(img.data)[1:2]
nzlayers(img::CommonImageFile) = size(img.data, 3)
ntlayers(img::CommonImageFile) = size(img.data, 4)
nchannels(::CommonImageFile{C}) where {C} = length(C)

channelnames(::CommonImageFile{<:Gray}) = ["Gray"]
channelnames(::CommonImageFile{<:RGB}) = ["Red", "Green", "Blue"]
channelnames(::CommonImageFile{<:RGBA}) = ["Red", "Green", "Blue", "Alpha"]
channelnames(::CommonImageFile{<:ARGB}) = ["Alpha", "Red", "Green", "Blue"]

## TODO: Support more colorants!
function channelnames(::CommonImageFile{C}) where {C}
  return error("Colorant $C not supported by the common image backend.")
end

channelcolors(::CommonImageFile{<:Gray}) = RGB(0.0, 0.0, 0.0)

function channelcolors(::CommonImageFile{<:RGB})
  return [RGB(1.0, 0.0, 0.0), RGB(0.0, 1.0, 0.0), RGB(0.0, 0.0, 1.0)]
end

function channelcolors(::CommonImageFile{<:RGBA})
  return [
    RGB(1.0, 0.0, 0.0),
    RGB(0.0, 1.0, 0.0),
    RGB(0.0, 0.0, 1.0),
    RGB(0.0, 0.0, 0.0),
  ]
end

function channelcolors(::CommonImageFile{<:ARGB})
  return [
    RGB(0.0, 0.0, 0.0),
    RGB(1.0, 0.0, 0.0),
    RGB(0.0, 1.0, 0.0),
    RGB(0.0, 0.0, 1.0),
  ]
end

## TODO: Support more colorants!
function channelcolors(::CommonImageFile{C}) where {C}
  return error(
    "Colorant $C currently not supported by CommonImageFile backend.",
  )
end

function channels(img::CommonImageFile) 
  ns = channelnames(img)
  cs = channelcolors(img)
  return map(enumerate(zip(ns, cs))) do (cindex, (name, color))
    Channel(cindex, name, color)
  end
end

function metadata(img::CommonImageFile)
  return (
    resolution = size(img.data)[1:2],
    channels = channels(img),
  )
end

imagedata(img::CommonImageFile) = ImageCore.channelview(img.data)

function imagedata(img::CommonImageFile, zindex, cindex, tindex)
  @assert 1 <= cindex <= nchannels(img) """
  Invalid channel index $cindex.
  """
  @assert 1 <= zindex <= nzlayers(img) """
  Invalid Z index $zindex.
  """
  @assert 1 <= tindex <= ntlayers(img) """
  Invalid T index $tindex.
  """
  data = ImageCore.channelview(img.data)
  slice = @view data[cindex, :, :, zindex, tindex]

  @assert size(slice) == planesize(img) """
  Inconsistent plane dimensions: <Pixels> node says $(planesize(img)),\
  but actual tiff data says $(size(slice)).
  """

  return slice
end

registerformat!(CommonImageFile)
