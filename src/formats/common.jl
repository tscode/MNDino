

"""
Support for common image formats via Images.jl.
"""
struct CommonImageFile{C <: Colors.Color} <: ImageFile
  path::String
  data::Array{C}
end

function CommonImageFile(path::String)
  data = FileIO.load(path)
  @assert data isa Array{<: Colors.Color} """
  The file loaded does not correspond to a proper image.
  """
  @assert length(size(data)) == 2 """
  The CommonImageFile wrapper currently only supports without z- or t-channels.
  """
  return CommonImageFile(path, data)
end

extensions(::Type{CommonImageFile}) = [".png", ".tif", ".tiff", ".jpg", ".jpeg"]

location(img::CommonImageFile) = img.path

function variants(ims::CommonImageFile)
  error("TODO")
end

defaultvariant(img::CommonImageFile) = (;)
defaultzindex(img::CommonImageFile) = 1
nzlayers(img::CommonImageFile) = 1

nchannels(img::CommonImageFile{C}) where {C} = length(C)

## TODO: Support more colorants!
channelnames(::CommonImageFile{<: Gray}) = ["Gray"]
channelnames(::CommonImageFile{<: RGB}) = ["Red", "Green", "Blue"]
channelnames(::CommonImageFile{<: RGBA}) = ["Red", "Green", "Blue", "Alpha"]
channelnames(::CommonImageFile{<: ARGB}) = ["Alpha", "Red", "Green", "Blue"]

channelcolors(::CommonImageFile{<: Gray}) = RGB(0., 0., 0.)
channelcolors(::CommonImageFile{<: RGB}) = [RGB(1., 0., 0.), RGB(0., 1., 0.), RGB(0., 0., 1.)]

channelcolors(::CommonImageFile{<: RGBA}) = [RGB(1., 0., 0.), RGB(0., 1., 0.), RGB(0., 0., 1.), RGB(0., 0., 0.)]

channelcolors(::CommonImageFile{<: ARGB}) = [RGB(0., 0., 0.), RGB(1., 0., 0.), RGB(0., 1., 0.), RGB(0., 0., 1.)]


channelname(img::CommonImageFile, cindex) = channelnames(img)[cindex]
channelcolor(img::CommonImageFile, cindex) = channelcolors(img)[cindex]

function metadata(img::CommonImageFile, cindex)
  resolution = size(img.data)
  return (
    cindex = cindex,
    resolution = size(img.data),
    name = channelname(img, cindex),
    color = channelcolor(img, cindex),
    size = (size(img.data)..., 1) # TODO: allow z and t index?
  )
end

function imagedata(img::CommonImageFile, cindex, zindex)
  @assert 1 <= cindex <= nchannels(img) """
  Invalid channel index $cindex.
  """
  @assert 1 <= zindex <= nzlayers(img) """
  Invalid Z index $zindex.
  """
  return ImageCore.channelview(img.data)[cindex, :, :]
end

register_format!(CommonImageFile)
