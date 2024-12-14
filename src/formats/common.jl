
"""
Support for common image formats like PNG or JPG via ImageIO.jl.

Images are loaded into memory in greedily. Large images should
use a different backend.

Note that slices along a potential third axis (e.g., for GIF files) are
interpreted as time frames and not as z stacks.
"""
struct CommonImageFile{C <: Colors.Color} <: ImageFile
  path::String
  data::Array{C, 3}
end

function CommonImageFile(path::String)
  data = FileIO.load(path)
  @assert data isa Array{<:Colors.Color} """
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

nzlayers(img::CommonImageFile) = size(img.data, 3)
ntlayers(img::CommonImageFile) = size(img.data, 4)
nchannels(::CommonImageFile{C}) where {C} = length(C)

channelnames(::CommonImageFile{<:Gray}) = ["Gray"]
channelnames(::CommonImageFile{<:RGB}) = ["Red", "Green", "Blue"]
channelnames(::CommonImageFile{<:RGBA}) = ["Red", "Green", "Blue", "Alpha"]
channelnames(::CommonImageFile{<:ARGB}) = ["Alpha", "Red", "Green", "Blue"]

## TODO: Support more colorants!
function channelnames(::CommonImageFile{C}) where {C}
  return error(
    "Colorant $C currently not supported by CommonImageFile backend.",
  )
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

channelname(img::CommonImageFile, cindex) = channelnames(img)[cindex]
channelcolor(img::CommonImageFile, cindex) = channelcolors(img)[cindex]

function metadata(img::CommonImageFile, cindex)
  resolution = size(img.data)
  return (
    cindex = cindex,
    resolution = size(img.data),
    name = channelname(img, cindex),
    color = channelcolor(img, cindex),
    size = size(img.data),
  )
end

imagedata(img::CommonImageFile) = ImageCore.channelview(img.data)

function imagedata(img::CommonImageFile, cindex, zindex, tindex)
  @assert 1 <= cindex <= nchannels(img) """
  Invalid channel index $cindex.
  """
  @assert 1 <= zindex <= nzlayers(img) """
  Invalid Z index $zindex.
  """
  @assert 1 <= tindex <= ntlayers(img) """
  Invalid T index $tindex.
  """
  return @view imagedata(img)[cindex, :, :, zindex, tindex]
end

register_format!(CommonImageFile)
