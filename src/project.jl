
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
  providers::Vector{Pair{Symbol, Provider}}
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

  providers = Vector{Pair{Symbol, Provider}}()
  return Project(
    name,
    comment,
    paths,
    channels,
    theme,
    providers,
  )
end

function addprovider!(project, key, provider::Provider)
  @assert !any(isequal(key), first.(project.providers)) """
  Location key :$key is already taken by another provider.
  """
  push!(project.providers, key => provider)
  return
end

function addprovider!(f::Function, project, key)
  addprovider!(project, key, f())
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

  # Happens whenever providers should update, e.g., right before saving project
  ctx[:update] = Observable(nothing)

  ctx[:nimages] = lift(length, ctx[:paths])
  ctx[:nchannels] = lift(length, ctx[:channels])
  
  ctx[:providers] = Dict{Symbol, Dict}()

  for (key, provider) in project.providers
    ctx[:providers][key] = initcontext(provider, ctx)
  end


  return ctx
end

function updateproject(project, ctx)
  providers = map(project.providers) do (key, provider)
    return key => update(provider, ctx[:providers][key])
  end
  return Project(
    getvalue(ctx, :name),
    getvalue(ctx, :comment),
    getvalue(ctx, :paths),
    getvalue(ctx, :channels),
    getvalue(ctx, :theme),
    providers,
  )
end

"""
    initproject(project::Project, layouts; options)

Run the project by initializing the runtime context and populating `layouts`
with the corresponding widgets.

Returns the runtime context.
"""
function initproject(project, layouts; options)
  options = Dict(options)
  layouts = Dict(layouts)
  ctx = initcontext(project)
  for (key, provider) in project.providers
    if provider isa Widget
      plotwidget(
        provider,
        layouts[key],
        ctx[:providers][key];
        theme = project.theme,
        get(options, key, (;))...,
      )
    end
  end
  return ctx
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

