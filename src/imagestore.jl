
struct ImageDescriptor
  id::Int
  path::String
  image::ImageFile
end

function ImageDescriptor(id, path :: String)
  return ImageDescriptor(id, path, loadimagefile(path))
end

function ImageDescriptor(id, image :: ImageFile)
  return ImageDescriptor(id, location(image), image)
end

function imagefile(entry::ImageDescriptor)
  return entry.image
end

function location(entry::ImageDescriptor)
  return entry.path
end

"""
Provides an updatable image store with an active / selected image plus the
capacity to save metadata.
"""
struct ImageStore <: Provider
  ids::Vector{Int}
  paths::Vector{String}
  shelfs::Dict{Symbol, Dict}
  active::Int
end

function ImageStore(paths :: Vector{String})
  return ImageStore(
    collect(1:length(paths)),
    paths,
    Dict{Symbol, Dict}(),
    isempty(paths) ? -1 : 1,
  )
end

function initcontext(store::ImageStore, ctx)
  pctx = Dict{Union{Symbol, Int}, Any}()

  # Changing this observable will change the active images of the store.
  pctx[:entries] = Observable(ImageDescriptor.(store.ids, store.paths))
  pctx[:ids] = lift(entries -> getfield.(entries, :id), pctx[:entries])
  pctx[:paths] = lift(entries -> location.(entries), pctx[:entries])

  # For interal purposes
  pctx[:shelfs] = store.shelfs

  # Changing this observable will try to change the active image.
  pctx[:select] = Observable(-1)

  # The id of the active entry. Select may change this.
  # Should not be listened to. Use pctx[:entry] instead.
  pctx[:active] = Observable(store.active)

  # Remember the most recent active entry id. For internal purposes.
  pctx[:recent] = Observable(store.active)

  # Stores the currently active shelfs of the store. For interal purposes.
  pctx[:shelfkeys] = Symbol[]
  
  on(pctx[:select]) do select
    if select == pctx[:active][]
      return
    elseif select == -1 # deselect
      pctx[:active][] = -1
    else # try to select an entry -- must exist
      entries = pctx[:entries][]
      index = findfirst(entry -> entry.id == select, entries)
      if !isnothing(index)
        pctx[:active][] = select
      end
    end
  end

  # Listen to this to get notified of changes in the entry.
  # Happens BEFORE pctx[:change], pctx[:change_to], but AFTER pctx[:change_from]
  pctx[:entry] = Observable{Union{Nothing, ImageDescriptor}}(nothing)

  # Listen to this to get notified of change events in the entry
  pctx[:change] = Observable{Tuple}((nothing, nothing))
  pctx[:change_from] = Observable{Union{Nothing, ImageDescriptor}}(nothing)
  pctx[:change_to] = Observable{Union{Nothing, ImageDescriptor}}(nothing)

  on(pctx[:active], update = true) do active
    entries = pctx[:entries][]

    index = findfirst(entry -> entry.id == active, entries)
    next = isnothing(index) ? nothing : entries[index]
    index = findfirst(entry -> entry.id == pctx[:recent][], entries)
    prev = isnothing(index) ? nothing : entries[index]

    pctx[:recent][] = active
    pctx[:change_from][] = prev
    pctx[:entry][] = next
    pctx[:change_to][] = next
    pctx[:change][] = (next, prev)
  end

  on(pctx[:entries]) do entries
    active = pctx[:active][]
    index = findfirst(entry -> entry.id == active, entries)
    if isnothing(index)
      pctx[:active][] = -1
    end
  end

  return pctx
end

"""
    addshelf!(pctx, key)

Add a shelf with name `key` to the store with provider context `pctx`.

Note that the returned shelf could already be populated with content if the
project was loaded / saved.
"""
function addshelf!(pctx, key)
  if key in pctx[:shelfkeys]
    @error """
    Shelf key $key already assigned by another !
    """
    return
  end
  push!(pctx[:shelfkeys], key)
  # Shelf could already exist from loading a populated store
  pctx[:shelfs][key] = get(pctx[:shelfs], key, Dict())
  return pctx[:shelfs][key]
end

"""
store = loadcontext(ctx, :store)
shelf = addshelf!(store, :mystuff) # gets me a dictionary per image in store

# Listen to changes of the active ImageDescriptor # and use my store
# appropriately.
# 
# The store should not contain observables, but only quantities for which it
# makes sense to store (and serialize / deserialize) them.

on(ctx[:store][:change]) do (next, prev)
  shelf[prev.id] = update_metadata(pctx)
  shelf[next.id] = haskey(self, next.id) ? load_metadata(pctx) : init_metadata(pctx)

  # changes I have to do in order to handle changes of the image
  pctx[:image] = loadimage(next.image)
end
"""
