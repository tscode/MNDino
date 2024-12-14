
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
  return ImarisFile(path, h5open(path, "r"))
end

extensions(::Type{ImarisFile}) = [".ims"]
location(ims::ImarisFile) = ims.path

variantdefault(::ImarisFile) = (; resolution = 0)
tindexdefault(::ImarisFile) = 1

function zindexdefault(ims::ImarisFile)
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

function nzlayers(img::ImarisFile)
  group = img.hdf5["DataSetInfo/CustomData"]
  return parseattribute(Int, group, "NumberOfZPoints")
end

function ntlayers(img::ImarisFile)
  group = img.hdf5["DataSetInfo/CustomData"]
  return parseattribute(Int, group, "NumberOfTimePoints")
end

function nchannels(img::ImarisFile)
  group = img.hdf5["DataSetInfo/CustomData"]
  return parseattribute(Int, group, "NumberOfChannels")
end

function variants(ims::ImarisFile)
  resolution = map(keys(ims.hdf5["DataSet"])) do key
    m = match(r"ResolutionLevel ([0-9]+)", key)
    return isnothing(m):nothing:parse(Int, m[1])
  end
  filter!(!isnothing, resolution)
  sort!(resolution)
  return (; resolution)
end

function channelname(img::ImarisFile, cindex)
  meta = metadata(img, cindex)
  return meta.name
end

function channelcolor(img::ImarisFile, cindex)
  meta = metadata(img, cindex)
  return meta.color
end

function channelnames(img::ImarisFile)
  return map(1:nchannels(img)) do cindex
    return channelname(img, cindex)
  end
end

function channelcolors(img::ImarisFile)
  return map(1:nchannels(img)) do cindex
    return channelcolor(img, cindex)
  end
end

function metadata(
  img::ImarisFile,
  cindex;
  resolution = variantdefault(img).resolution,
)
  info_group = img.hdf5["DataSetInfo"]
  data_group = img.hdf5["DataSet/ResolutionLevel $resolution/TimePoint 0"]

  info_c = info_group["Channel $(cindex - 1)"]
  data_c = data_group["Channel $(cindex - 1)"]

  return (
    cindex = cindex,
    resolution = resolution,
    time = time,
    name = parseattribute(String, info_c, "Name"),
    color = parseattribute(RGB, info_c, "Color"),
    opacity = parseattribute(Float64, info_c, "ColorOpacity"),
    size = (
      parseattribute(Int, data_c, "ImageSizeX"),
      parseattribute(Int, data_c, "ImageSizeY"),
      parseattribute(Int, data_c, "ImageSizeZ"),
    ),
    extrema = (
      parseattribute(Float64, data_c, "HistogramMin"),
      parseattribute(Float64, data_c, "HistogramMax"),
    ),
  )
end

function imagedata(
  img::ImarisFile,
  cindex,
  zindex,
  tindex;
  resolution = variantdefault(img).resolution,
)
  # Prior consistency checks
  @assert 1 <= cindex <= nchannels(img) """
  Invalid channel index $cindex.
  """
  @assert 1 <= zindex <= nzlayers(img) """
  Invalid Z index $zindex. 
  """
  data_group =
    img.hdf5["DataSet/ResolutionLevel $resolution/TimePoint $(tindex - 1)"]
  data = data_group["Channel $(cindex - 1)/Data"]

  # Internal consistency checks
  meta = metadata(img, cindex; resolution)
  if meta.size[1:2] != size(data)[1:2]
    @warn """
    Internal resolution mismatch ($(meta.size[1:2]) vs. $(size(data)[1:2])).
    """
  end
  @assert meta.size[3] <= size(data)[3] """
  Wrong number of Z layers in metadata.
  """
  return data[:, :, zindex]
end

register_format!(ImarisFile)
