
"""
MNDino project object.

The main purpose of project objects, besides storing metadata like a project
name and theming information, is to collect providers that implement the actual
functionality.
"""
struct Project
  version::String
  date::DateTime
  name::String
  comment::String
  theme::Dict{Symbol, Any}
  providers::OrderedDict{Symbol, Provider}
end

@pack Project in StructFormat [date in StringFormat]

function Project(
  name;
  comment = "",
  date = Dates.now(),
  theme = Dict(),
)
  providers = OrderedDict{Symbol, Provider}()
  return Project("v0.2", date, name, comment, theme, providers)
end

function addprovider!(project, key, provider::Provider)
  @assert !any(isequal(key), keys(project.providers)) """
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

  loadentries!(ctx, project, [:name, :comment, :theme]; obs = true)
  loadentries!(ctx, project, [:version, :date]; obs = false)

  # Happens whenever providers should be forced to update, e.g., right before
  # saving the project
  ctx[:update] = Observable(nothing)

  ctx[:providers] = Dict{Symbol, Dict}()
  for (key, provider) in project.providers
    ctx[:providers][key] = initcontext(provider, ctx)
  end

  return ctx
end

function updateproject(project, ctx)
  providers = OrderedDict{Symbol, Provider}()
  for (key, provider) in project.providers
    providers[key] = update(provider, ctx[:providers][key])
  end
  return Project(
    getvalue(ctx, :version),
    getvalue(ctx, :date),
    getvalue(ctx, :name),
    getvalue(ctx, :comment),
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
StructPack context used for MNDino project packing and unpacking.
"""
struct MNDinoContext <: StructPack.Context end

StructPack.format(::Type{Matrix{Bool}}, ::MNDinoContext) = StructPack.BinArrayFormat()


"""
    packproject(project::Project)
    packproject(io::IO, project::Project)

Return or write a binary representation of `project`.
"""
function packproject(project::Project)
  return StructPack.pack(project, MNDinoContext())
end

function packproject(io::IO, project::Project)
  return StructPack.pack(io, project, MNDinoContext())
end

"""
    unpackproject(bytes::Vector{UInt8})
    unpackproject(io::IO)

Unpack a project from its binary representation.
"""
function unpackproject(bytes::Vector{UInt8})
  return StructPack.unpack(bytes, Project, MNDinoContext())
end

function unpackproject(io::IO)
  return StructPack.unpack(io, Project, MNDinoContext())
end

"""
    saveproject(project, filename)

Serialize `project` into the file `filename`.
"""
function saveproject(project, filename::String)
  io = GZip.open(filename, "w")
  try
    packproject(io, project)
  finally
    close(io)
  end
  return
end

"""
    loadproject(filename)

Deserialize a project from the file `filename`.
"""
function loadproject(filename::String)
  io = GZip.open(filename, "r")
  try
    return unpackproject(io)
  finally
    close(io)
  end
end

