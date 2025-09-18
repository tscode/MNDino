
"""
A storable quantity.

Usually, a `Storable` contains information associated to an image and is stored
inside of the [`Shelf`](@ref) of an [`ImageStore`](@ref).

Each storable must be packable in `StructPack.StructFormat`.
"""
abstract type Storable end

@pack {<: Storable} in StructFormat

"""
A shelf contains one `Storable` object per image id.

Providers that want to make use of an `ImageStore` can receive shelves during
context initialization via [`addshelf!`](@ref).

Shelfs can be used like ordered dictionaries that take `Int` as key.
"""
struct Shelf{S <: Storable} <: AbstractDict{Int, S}
  dict::OrderedDict{Int, S}

  Shelf{S}() where {S} = new{S}(OrderedDict{Int, S}())
  Shelf{S}(dict::AbstractDict{Int, S}) where {S} = new{S}(dict)
  Shelf{S}(args...) where {S} = new{S}(OrderedDict{Int, S}(args...))
end

@pack {<: Shelf} in TypedFormat{MapFormat}

StructPack.typeparamtypes(::Type{<: Shelf}) = (Type,)

Base.keytype(::Type{<: Shelf}) = Int
Base.valtype(::Type{<: Shelf{S}}) where {S} = S
Base.keys(s::Shelf) = Base.keys(s.dict)
Base.values(s::Shelf) = Base.values(s.dict)
Base.length(s::Shelf) = Base.length(s.dict)
Base.iterate(s::Shelf, args...) = Base.iterate(s.dict, args...)
Base.getindex(s::Shelf, args...) = Base.getindex(s.dict, args...)
Base.setindex!(s::Shelf, args...) = Base.setindex!(s.dict, args...)
Base.get(s::Shelf, args...) = Base.get(s.dict, args...)
Base.get(f::Function, s::Shelf, args...) = Base.get(f, s.dict, args...)
Base.haskey(s::Shelf, args...) = Base.haskey(s.dict, args...)
Base.delete!(s::Shelf, args...) = Base.delete!(s.dict, args...)

"""
Image descriptor exposed by the ImageStore.
"""
struct ImageDescriptor
  id::Int
  path::String
  image::Task
end

function ImageDescriptor(id, path::String)
  return ImageDescriptor(id, path, Threads.@spawn(loadimagefile(path)))
end

# function ImageDescriptor(id, image::ImageFile)
#   return ImageDescriptor(id, location(image), image)
# end

function imagefile(entry::ImageDescriptor)
  return fetch(entry.image)
end

function location(entry::ImageDescriptor)
  return entry.path
end

function Base.basename(entry::ImageDescriptor)
  return basename(entry.path)
end

"""
An image store.

Keeps track of a number of loaded images as well as an active / selected image.
Other providers can save permanent metadata for each image by making use of
shelves (see [`addshelf!`](@ref)). Data stored in the shelves of an image store
is meant to survive the runtime.
"""
struct ImageStore <: Provider
  ids::Vector{Int}
  paths::Vector{String}
  shelfs::OrderedDict{Symbol, Shelf}
  active_index::Int
end

function ImageStore(paths::Vector{String})
  return ImageStore(
    collect(1:length(paths)),
    paths,
    OrderedDict{Symbol, Shelf}(),
    isempty(paths) ? -1 : 1,
  )
end

"""
    rmimages(store::ImageStore, ids)
    rmimages(store::ImageStore, paths)

Remove the images defined by `paths` or `ids` from the image store `store`.
"""
function rmimages(store::ImageStore, paths_to_remove::Vector{String})
  ids = copy(store.ids)
  paths = copy(store.paths)
  shelfs = copy(store.shelfs)
  active_index = store.active_index
  @assert 1 <= active_index <= length(ids) """
  Image store malformed: field :active_index is greater than number of images.
  """
  active_id = ids[active_index]

  for path in paths_to_remove
    index = findfirst(isequal(path), paths)
    if isnothing(index)
      @error "Image $path does not exist. Cannot remove it from image store."
    else
      id = ids[index]
      @info "Deleting image $id at $path from image store."
      deleteat!(ids, index)
      deleteat!(paths, index)
      for shelf in values(shelfs)
        delete!(shelf, id)
      end
    end
  end

  active_index = findfirst(isequal(active_id), ids)
  if isnothing(active_index)
    active_index = isempty(paths) ? -1 : 1
    @info "Active index of the store was set to $active_index"
  end

  return ImageStore(ids, paths, shelfs, active_index)
end

function rmimages(store::ImageStore, ids_to_remove::Vector{Int})
  paths_to_remove = map(ids_to_remove) do id
    index = findfirst(isequal(id), store.ids)
    store.paths[index]
  end
  rmimages(store, paths_to_remove)
end


function initcontext(store::ImageStore, ctx)
  pctx = Dict{Union{Symbol, Int}, Any}()

  # public (set, get): Changing this observable will change the images of the store.
  pctx[:entries] = Observable(ImageDescriptor.(store.ids, store.paths))

  # public (get): The ids of the image of the store
  pctx[:ids] = lift(entries -> getfield.(entries, :id), pctx[:entries])

  # public (get): The paths of the image of the store
  pctx[:paths] = lift(entries -> location.(entries), pctx[:entries])

  # private: for interal purposes
  pctx[:shelfs] = store.shelfs

  # public (set): Changing this observable to a valid entry id will change the active entry
  pctx[:select_id] = Observable(-1)

  # public (set): Changing this observable to a valid entry index will change the active entry
  pctx[:select_index] = Observable(-1)

  # public (set): Notifying one of these observables will jump to the first or last entry
  pctx[:select_first] = Observable(nothing)
  pctx[:select_last] = Observable(nothing)

  # public (set): Notifying one of these observables will move the selected entry up or down
  pctx[:select_prev] = Observable(nothing)
  pctx[:select_next] = Observable(nothing)

  # public (get): The id of the active entry. Can be -1 if nothing is selected
  pctx[:active_id] = Observable(-1)

  # public (get): The index of the active entry. Can be -1 if nothing is selected
  pctx[:active_index] = Observable(-1)

  # public (get): The last index of the store
  pctx[:last_index] = lift(length, pctx[:entries])

  # public (get): Whether the image store is currently loading or has finished
  pctx[:loading] = Observable(false)

  # private: Used to cleanly create entry changes. For internal purposes only.
  pctx[:activate_id] = Observable(-1)
  pctx[:recent_id] = Observable(-1)

  # private: Stores the currently active shelfs of the store. For interal purposes.
  pctx[:shelfkeys] = Symbol[]

  on(pctx[:select_first]) do _
    return pctx[:select_index][] = 1
  end

  on(pctx[:select_last]) do _
    return pctx[:select_index][] = length(pctx[:entries][])
  end

  on(pctx[:select_prev]) do _
    if pctx[:active_index][] > 1
      pctx[:select_index][] = pctx[:select_index][] - 1
    end
  end

  on(pctx[:select_next]) do _
    if pctx[:active_index][] < length(pctx[:entries][])
      pctx[:select_index][] = pctx[:select_index][] + 1
    end
  end

  on(pctx[:select_id]) do id
    if id == -1
      pctx[:select_index][] = -1
    else
      index = findfirst(entry -> entry.id == id, pctx[:entries])
      if !isnothing(index)
        pctx[:select_index][] = index
      end
    end
  end

  on(pctx[:select_index]) do index
    if index == pctx[:active_index][]
      return
    elseif index == -1 # deselect
      pctx[:loading][] = true
      pctx[:activate_id][] = -1 # update pctx[:entry] and related observables
      pctx[:active_id][] = -1
      pctx[:active_index][] = -1
      pctx[:loading][] = false
    elseif 1 <= index <= length(pctx[:entries][])
      pctx[:loading][] = true
      entry = pctx[:entries][][index]
      pctx[:activate_id][] = entry.id # update pctx[:entry] and related observables
      pctx[:active_id][] = entry.id
      pctx[:active_index][] = index
      pctx[:loading][] = false
    end
  end

  # public (get)
  # Listen to this to get notified of changes in the entry.
  # Happens AFTER pctx[:change]
  pctx[:entry] = Observable{Union{Nothing, ImageDescriptor}}(nothing)

  # public (get)
  # Listen to this to get notified of change events in the entry
  # This gets updated BEFORE pctx[:entry]
  pctx[:change] = Observable{Tuple}((nothing, nothing))

  # public (get, set)
  # Listen or notify on this observable to handle or send store-update queries
  pctx[:update] = Observable(nothing)

  # public (get)
  # Observable pointing to the current image. Updated when pctx[:entry] is
  # updated.
  pctx[:image] = Observable{Union{Nothing, ImageFile}}(nothing)
  pctx[:path] = Observable{Union{Nothing, String}}(nothing)

  on(pctx[:entry]) do entry
    if !isnothing(entry)
      pctx[:image][] = imagefile(entry)
      pctx[:path][] = location(entry)
    else
      pctx[:image][] = nothing
      pctx[:path][] = nothing
    end
  end

  # Trigger update if a global context update is triggered
  on(_ -> notify(pctx[:update]), ctx[:update])

  on(pctx[:activate_id]; update = true) do id
    entries = pctx[:entries][]

    index = findfirst(entry -> entry.id == id, entries)
    next = isnothing(index) ? nothing : entries[index]
    index = findfirst(entry -> entry.id == pctx[:recent_id][], entries)
    prev = isnothing(index) ? nothing : entries[index]

    pctx[:recent_id][] = id
    pctx[:change][] = (next, prev)
    pctx[:entry][] = next

    return
  end

  on(pctx[:entries]) do entries
    id = pctx[:active_id][]
    index = findfirst(entry -> entry.id == id, entries)
    if isnothing(index)
      pctx[:select_index][] = -1
    else
      pctx[:select_index][] = index
    end
  end

  # All dependencies are in place. Now select the correct initial index
  pctx[:select_index][] = store.active_index

  return pctx
end

"""
    addshelf!(pctx, key, S)

Add a shelf with name `key` and storable type `S <: Storable` to the store with
provider context `pctx`.

Note that the returned shelf could already be populated with content if the
project was loaded / saved.
"""
function addshelf!(pctx, key, S)
  if key in pctx[:shelfkeys]
    @error """
    Shelf key $key already assigned by another !
    """
    return
  end
  push!(pctx[:shelfkeys], key)
  # Shelf could already exist from loading a populated store
  pctx[:shelfs][key] = get(pctx[:shelfs], key, Shelf{S}())
  return pctx[:shelfs][key]
end

"""
    addimages!(pctx, paths)

Add images from `paths` to the image store with provider context `pctx`.
"""
function addimages!(pctx, paths)
  idmax = maximum(pctx[:ids][], init = 1)
  new_paths = filter(paths) do path
    !(path in pctx[:paths][])
  end
  new_entries = map(enumerate(new_paths)) do (index, path)
    ImageDescriptor(idmax + index, path)
  end
  append!(pctx[:entries][], new_entries)
  notify(pctx[:entries])
  return
end

"""
    rmimages!(pctx, paths)

Remove the images at `paths` from the image store with provider context `pctx`.
"""
function rmimages!(pctx, paths)
  diff = setdiff(paths, pctx[:paths][])
  if !isempty(diff)
    @error """
    Cannot remove images that are not part of the image store: $diff.
    """
  end
  ids = map(paths) do path
    index = findfirst(entry -> entry.path == path, pctx[:entries][])
    pctx[:entries][][index].id
  end

  # Purge shelfs
  for key in keys(pctx[:shelfs])
    shelf = pctx[:shelfs][key]
    foreach(id -> delete!(shelf, id), ids)
  end

  # Purge entries and notify the change
  todelete = map(pctx[:entries][]) do entry
    entry.id in ids
  end
  deleteat!(pctx[:entries][], todelete)
  notify(pctx[:entries])

  return
end
