
"""
Support for the Imaris File Format (.IMS) by Oxford Instruments.
"""
struct ImarisFile <: ImageFile
  path::String
  hdf5::HDF5.File
end

"""
    ImarisFile(path)

Open the `.ims` file located at `path`.
"""
function ImarisFile(path::String)
  ImarisFile(path, h5open(path, "r"))
end

extension(::Type{ImarisFile}) = ".ims"

function variants(ims::ImarisFile)
  error("TODO")
end

defaultvariant(ims::ImarisFile) = (time=0, resolution=0)

function defaultzindex(ims::ImarisFile)
  nz = nzlayers(ims)
  return max(div(nz, 2), 1)
end

function parseattribute(T, group, name::String)
  return parseattribute(T, read_attribute(group, name))
end

parseattribute(T, attrib::Vector{String}) = parse(T, join(attrib))
parseattribute(::Type{String}, attrib::Vector{String}) = join(attrib)

function parseattribute(::Type{RGB}, attrib::Vector{String})
  rgb = split(join(attrib), " ")
  r, g, b = parse.(Float64, rgb)
  return RGB{Float16}(r, g, b)
end

path(img::ImarisFile) = img.path

function nzlayers(img::ImarisFile; kwargs...)
  group = img.hdf5["DataSetInfo/CustomData"]
  return parseattribute(Int, group, "NumberOfZPoints")
end

function nchannels(img::ImarisFile; kwargs...)
  group = img.hdf5["DataSetInfo/CustomData"]
  return parseattribute(Int, group, "NumberOfChannels")
end

function channelname(img, cindex; kwargs...)
  meta = metadata(img, cindex; kwargs...)
  return meta.name
end

function channelcolor(img, cindex; kwargs...)
  meta = metadata(img, cindex; kwargs...)
  return meta.color
end

function metadata(img::ImarisFile, cindex; kwargs...)
  resolution = get(kwargs, :resolution, defaultvariant(img).resolution)
  time = get(kwargs, :time, defaultvariant(img).time)

  info_group = img.hdf5["DataSetInfo"]
  data_group = img.hdf5["DataSet/ResolutionLevel $resolution/TimePoint $time"]

  info_c = info_group["Channel $(cindex - 1)"]
  data_c = data_group["Channel $(cindex - 1)"]

  return (
    cindex=cindex,
    resolution=resolution,
    time=time,
    name=parseattribute(String, info_c, "Name"),
    color=parseattribute(RGB, info_c, "Color"),
    opacity=parseattribute(Float64, info_c, "ColorOpacity"),
    size = (
      parseattribute(Int, data_c, "ImageSizeX"),
      parseattribute(Int, data_c, "ImageSizeY"),
      parseattribute(Int, data_c, "ImageSizeZ"),
    ),
    extrema = (
      parseattribute(Float64, data_c, "HistogramMin"),
      parseattribute(Float64, data_c, "HistogramMax"),
    )
  )
end

function imagedata(img::ImarisFile, cindex, zindex; kwargs...)
  resolution = get(kwargs, :resolution, defaultvariant(img).resolution)
  time = get(kwargs, :time, defaultvariant(img).time)

  # Prior consistency checks
  @assert 1 <= cindex <= nchannels(img; resolution, time) """
  Invalid channel index $cindex.
  """
  @assert 1 <= zindex <= nzlayers(img; resolution, time) """
  Invalid Z index $zindex. 
  """
  data_group = img.hdf5["DataSet/ResolutionLevel $resolution/TimePoint $time"]
  data = data_group["Channel $(cindex - 1)/Data"]

  # Internal consistency checks
  meta = metadata(img, cindex; resolution, time)
  @assert meta.size[1:2] == size(data)[1:2] """
  Internal resolution mismatch ($(meta.size[1:2]) vs. $(size(data)[1:2])).
  """
  @assert meta.size[3] <= size(data)[3] """
  Number of Z-points in metadata too large.
  """
  return data[:, :, zindex]
end


register_format!(ImarisFile)

