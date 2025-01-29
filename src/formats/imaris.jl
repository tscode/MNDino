
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
  return ImarisFile(path, HDF5.h5open(path, "r"))
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
  return parseattribute(T, HDF5.read_attribute(group, name))
end

parseattribute(T, attrib::Vector{String}) = parse(T, join(attrib))
parseattribute(::Type{String}, attrib::Vector{String}) = join(attrib)

function parseattribute(::Type{RGB}, attrib::Vector{String})
  rgb = split(join(attrib), " ")
  r, g, b = parse.(Float32, rgb)
  return RGBf(r, g, b)
end

function planesize(img::ImarisFile; resolution = variantdefault(img).resolution)
  # We extract the actual size of the data array stored in the HDF5 file, since 
  # the metadata (ImageSizeX, ImageSizeY) does not seem to be reliable
  data_group = img.hdf5["DataSet/ResolutionLevel $resolution/TimePoint 0"]
  data = data_group["Channel 0/Data"]
  return size(data)[1:2]
end

function nzlayers(img::ImarisFile)
  # TODO: We should not trust that this metadata is reliably included in every Imaris file!
  group = img.hdf5["DataSetInfo/CustomData"]
  return parseattribute(Int, group, "NumberOfZPoints")
end

function ntlayers(img::ImarisFile)
  # TODO: We should not trust that this metadata is reliably included  in every Imaris file!
  group = img.hdf5["DataSetInfo/CustomData"]
  return parseattribute(Int, group, "NumberOfTimePoints")
end

function nchannels(img::ImarisFile)
  # TODO: We should not trust that this metadata is reliably included  in every Imaris file!
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

function metadata(img::ImarisFile; resolution = variantdefault(img).resolution)
  info_group = img.hdf5["DataSetInfo"]
  data_group = img.hdf5["DataSet/ResolutionLevel $resolution/TimePoint 0"]

  cmeta = map(1:nchannels(img)) do cindex
    info_c = info_group["Channel $(cindex - 1)"]
    data_c = data_group["Channel $(cindex - 1)"]

    cindex = cindex
    name = parseattribute(String, info_c, "Name")
    color = parseattribute(RGB, info_c, "Color")
    opacity = parseattribute(Float64, info_c, "ColorOpacity")
    size = (
      parseattribute(Int, data_c, "ImageSizeX"),
      parseattribute(Int, data_c, "ImageSizeY"),
      parseattribute(Int, data_c, "ImageSizeZ"),
    )
    extrema = (
      parseattribute(Float64, data_c, "HistogramMin"),
      parseattribute(Float64, data_c, "HistogramMax"),
    )
    return (; cindex, name, color, opacity, size, extrema)
  end

  return (resolution = cmeta[1].size[1:2], channels = cmeta)
end

function channels(img::ImarisFile)
  return map(metadata(img).channels) do c
    return Channel(c.cindex, c.name, c.color)
  end
end

function imagedata(
  img::ImarisFile,
  zindex,
  cindex,
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

  return data[:, :, zindex]
end

registerformat!(ImarisFile)
