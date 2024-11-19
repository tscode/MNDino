
"""
Metadata object for an image channel.

Stores the index of the channel in the image, the channel name, and an optional
channel color.
"""
struct Channel
  index::Int
  name::String
  color::Color
end

"""
Project object.
"""
struct Project
  name::String
  comment::String
  paths::Vector{String}
  channels::Vector{Channel}
  theme::Dict
  widgets::Vector{Pair{Symbol, Widget}}
end

function Project(
  name,
  paths;
  comment = "",
  channels = nothing,
  theme = Dict()
)
  paths = filter(paths) do path
    try loadimagefile(path)
    catch err
      @error """
      Unable to load image file at path '$path': $err.
      Removing this file from the project.
      """
      return false
    end
    return true
  end

  if isnothing(channels)
    img = loadimagefile(paths[1])
    channels = map(1:nchannels(img)) do cindex
      cname = channelname(img, cindex)
      ccolor = channelcolor(img, cindex)
      return Channel(cindex, cname, ccolor)
    end
  end

  paths = filter(paths) do path
    img = loadimagefile(path)
    nc = nchannels(img)
    mc = maximum(c -> c.index, channels)
    if mc > nc
      @error """
      Image file at path '$path' has no channel $mc.
      Removing this file from the project.
      """
      return false
    end
    return true
  end

  widgets = Vector{Pair{Symbol, Widget}}()
  return Project(
    name,
    comment,
    paths,
    channels,
    theme,
    widgets,
  )
end

function addwidget!(project, key, widget::Widget)
  @assert !any(isequal(key), first.(project.widgets)) """
  Location key :$key is already taken by another widget.
  """
  push!(project.widgets, key => widget)
  return
end

function initcontext(project::Project)
  ctx = Dict{Symbol, Any}()
  ctx[:project] = project
  
  ctx[:name] = Observable(project.name)
  ctx[:comment] = Observable(project.comment)
  ctx[:paths] = Observable(project.paths)
  ctx[:theme] = Observable(project.theme)
  ctx[:channels] = Observable(project.channels)

  ctx[:nimages] = lift(length, ctx[:paths])
  ctx[:nchannels] = lift(length, ctx[:channels])
  
  ctx[:widgets] = Dict{Symbol, Dict}()

  for (key, widget) in project.widgets
    ctx[:widgets][key] = initcontext(widget, ctx)
  end

  return ctx
end

function updateproject(project, ctx)
  widgets = map(project.widgets) do (key, widget)
    return key => updatewidget(widget, ctx[:widgets][key])
  end
  return Project(
    getvalue(ctx, :name),
    getvalue(ctx, :comment),
    getvalue(ctx, :paths),
    getvalue(ctx, :channels),
    getvalue(ctx, :theme),
    widgets,
  )
end

"""
    saveproject(project, filename)

Serialize `project` into the file `filename`.
"""
function saveproject(project, filename::String)
  Serialization.serialize(filename, project)
  return
end

"""
    loadproject(filename)

Deserialize a project from the file `filename`.
"""
function loadproject(filename::String)
  return Serialization.deserialize(filename)
end

