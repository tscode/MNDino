
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

function location(entry::ImageDescriptor)
  entry.path
end

"""
Provides an updatable image store with an active / selected image plus the
capacity to save metadata.
"""
struct ImageStore <: Provider
  entries::Vector{ImageDescriptor}
  shelfs::Dict{Symbol, Dict}
  active::Int
end

function ImageStore(sources :: Vector{<: Union{String, ImageFile}})
  entries = map(ImageDescriptor, eachindex(sources), sources)
  return ImageStore(
    entries,
    Dict{Symbol, Dict}(),
    isempty(entries) ? -1 : entries[1].id,
  )
end

function initcontext(store::ImageStore, ctx)
  pctx = Dict{Union{Symbol, Int}, Any}()

  # Changing this observable will change the active images of the store.
  pctx[:entries] = Observable(store.entries)

  # For interal purposes
  pctx[:shelfs] = store.shelfs

  # Changing this observable will try to change the active image.
  pctx[:select] = Observable(-1)

  # The actual active entry. Select may change this
  pctx[:active] = Observable(store.active)

  # Remember the most recent active entries. For internal purposes.
  pctx[:recent] = Observable(store.active)

  # Stores the currently active shelfs of the store. For interal purposes.
  pctx[:shelfkeys] = Symbol[]
  
  on(pctx[:select]) do select
    if select == pctx[:active][]
      return
    elseif select == -1 # deselect
      pctx[:active][] = -1
    else # try to select an entry -- must exist
      index = findfirst(entry -> entry.id == select, entries)
      if !isnothing(index)
        pctx[:active][] = select
      end
    end
  end

  pctx[:change] = Observable{Tuple}((nothing, nothing))

  on(pctx[:active]) do active
    entries = pctx[:entries][]
    index = findfirst(entry -> entry.id == active, entries)
    next = isnothing(index) ? nothing : entries[index]
    index = findfirst(entry -> entry.id == pctx[:recent][], entries)
    prev = isnothing(index) ? nothing : entries[index]
    pctx[:recent][] = active
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
