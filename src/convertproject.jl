
using OrderedCollections
using Dates

include("pack/Pack.jl")
import .Pack

Pack.format(::Type{Dates.DateTime}) = Pack.StringFormat()
Pack.construct(::Type{Dates.DateTime}, x, ::Pack.StringFormat) = DateTime(x)

Pack.format(::Type{RGBf}) = Pack.MapFormat()

function convert_project_files()
  paths = NativeFileDialog.pick_multi_file(filterlist = "dino")
  convert_project_files(paths)
end

function convert_project_files(paths)
  for path in paths
    @info "Loading v0.1 project file $path..."
    project = try
      loadproject(path)
    catch err
      @error """
      Error while trying to load project file: $err.
      Leaving the file in place.
      """
    end
    @info "Converting project..."
    obj = _emulate_v02(project)
    path_old = path * ".v1"
    @info "Moving $path to $path_old"
    Base.Filesystem.mv(path, path_old)
    @info "Saving v0.2 project file to $path"
    GZip.open(path, "w") do file
      Pack.pack(file, obj)
    end
  end
  return
end

function _emulate_v02(project01::Project)
  providers = OrderedDict()
  for (key, provider) in project01.providers
    providers[key] = _emulate_v02(provider)
  end
  return (
    version = "v0.2",
    date = Dates.now(),
    name = project01.name,
    comment = project01.comment,
    theme = Dict(),
    providers = providers,
  )
end

function _emulate_v02(store01::VariableStore)
  type = (
    name = "VariableStore",
    path = ["MNDino"],
    params = [],
  )
  value = (;)
  return (; type, value)
end

function _emulate_v02(widget::AnalysisWidget)
  type = (
    name = "AnalysisWidget",
    path = ["MNDino"],
    params = [],
  )
  value = (
    title = widget.title,
    script_path = widget.script_path,
    image_store = widget.image_store,
    variable_store = widget.variable_store,
  )
  return (; type, value)
end

function _emulate_v02(c::ChannelSpec)
  return (
    cindex = c.index,
    name = c.name,
    color = convert(RGBf, c.color),
  )
end

function _emulate_v02(widget::ChannelViewWidget)
  type = (
    name = "ChannelViewWidget",
    path = ["MNDino"],
    params = [],
  )
  value = (
    title = widget.title,
    filter = _emulate_v02(widget.filter),
    channels = map(_emulate_v02, widget.channels),
    image_store = widget.image_store,
    variable_store = widget.variable_store,
  )
  return (; type, value)
end

function _emulate_v02(filter::NoFilter)
  type = (
    name = "NoFilter",
    path = ["MNDino"],
    params = [],
  )
  value = (;)
  return (; type, value)
end

function _emulate_v02(filter::GaussFilter)
  type = (
    name = "GaussFilter",
    path = ["MNDino"],
    params = [],
  )
  value = (; radius = filter.radius)
  return (; type, value)
end

function _emulate_v02(widget::ChannelViewMaskWidget)
  type = (
    name = "ChannelViewMaskWidget",
    path = ["MNDino"],
    params = [],
  )
  value = (
    title = widget.title,
    mask_channels = [], # not yet used actually in version 0.2
    parent = widget.parent,
    image_store = widget.image_store,
    variable_store = widget.variable_store,
  )
  return (; type, value)
end

function _emulate_v02(widget::ImageSelectorWidget)
  type = (
    name = "ImageSelectorWidget",
    path = ["MNDino"],
    params = [],
  )
  value = (
    title = widget.title,
    image_store = widget.image_store,
  )
  return (; type, value)
end

function _emulate_v02(widget::ProjectWidget)
  type = (
    name = "ProjectWidget",
    path = ["MNDino"],
    params = [],
  )
  value = (
    title = widget.title,
    path = widget.path,
  )
  return (; type, value)
end

function _emulate_v02(widget::SegmentsWidget)
  type = (
    name = "SegmentsWidget",
    path = ["MNDino"],
    params = [],
  )
  value = (
    title = widget.title,
    segment_provider = widget.segment_provider,
  )
  return (; type, value)
end

function _emulate_v02(store01::ImageStore)
  shelfs = OrderedDict()
  for (key, shelf) in store01.shelfs
    shelfs[key] = _emulateshelf_v02(key, shelf)
  end
  type = (
    name = "ImageStore",
    path = ["MNDino"],
    params = [],
  )
  value = (
    ids = store01.ids,
    paths = store01.paths,
    shelfs = shelfs,
    active_index = store01.active_index,
  )
  return (; type, value)
end

function _emulateshelf_v02(key::Symbol, shelf::Dict)
  if key == :channelview
    type = (
      name = "Shelf",
      path = ["MNDino"],
      params = [(name = "View", path = ["MNDino"], params = [])],
    )
  elseif key == :mask
    type = (
      name = "Shelf",
      path = ["MNDino"],
      params = [(name = "MaskData", path = ["MNDino"], params = [])],
    )
  else
    error("Unrecognized shelf with key $key")
  end
  value = [key => _emulatestorable_v02(value) for (key, value) in shelf]
  return (; type, value = OrderedDict(value))
end

function _emulatestorable_v02(view01::View2D)
  return (zindex = view01.zindex, tindex = 1)
end

function _emulatestorable_v02(mask01::Dict{Int, BitMatrix})
  return (; masks = OrderedDict(mask01))
end
