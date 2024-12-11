
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

function Base.basename(entry::ImageDescriptor)
  return basename(entry.path)
end

"""
An image store.

Keeps track of a number of loaded images as well as an active or selected image.
Other providers can save permanent metadata for each image, meaning that this
data survives the runtime.
"""
struct ImageStore <: Provider
  ids::Vector{Int}
  paths::Vector{String}
  shelfs::Dict{Symbol, Dict}
  active_index::Int
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

  # Changing this observable will change the images of the store.
  pctx[:entries] = Observable(ImageDescriptor.(store.ids, store.paths))
  pctx[:ids] = lift(entries -> getfield.(entries, :id), pctx[:entries])
  pctx[:paths] = lift(entries -> location.(entries), pctx[:entries])

  # For interal purposes
  pctx[:shelfs] = store.shelfs

  # Changing this observable to a valid entry id will change the active entry
  pctx[:select_id] = Observable(-1)

  # Changing this observable to a valid entry index will change the active entry
  # Do not listen to this observable
  pctx[:select_index] = Observable(-1)

  # Notifying one of these observables will jump to the first or last entry
  # Do not listen to these observables
  pctx[:select_first] = Observable(nothing)
  pctx[:select_last] = Observable(nothing)

  # Notifying one of these observables will move the selected entry up or down
  # Do not listen to these observables
  pctx[:select_prev] = Observable(nothing)
  pctx[:select_next] = Observable(nothing)

  # The id of the active entry. Can be -1 if nothing is selected
  pctx[:active_id] = Observable(-1)

  # The index of the active entry. Can be -1 if nothing is selected
  pctx[:active_index] = Observable(-1)

  # Used to cleanly create entry changes. For internal purposes only.
  pctx[:activate_id] = Observable(-1)
  pctx[:recent_id] = Observable(-1)

  # Stores the currently active shelfs of the store. For interal purposes.
  pctx[:shelfkeys] = Symbol[]

  on(pctx[:select_first]) do _
    pctx[:select_index][] = 1
  end

  on(pctx[:select_last]) do _
    pctx[:select_index][] = length(pctx[:entries][])
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
      pctx[:activate_id][] = -1 # update pctx[:entry] and related observables
      pctx[:active_id][] = -1
      pctx[:active_index][] = -1
    elseif 1 <= index <= length(pctx[:entries][])
      entry = pctx[:entries][][index]
      pctx[:activate_id][] = entry.id # update pctx[:entry] and related observables
      pctx[:active_id][] = entry.id
      pctx[:active_index][] = index
    end
  end
  

  # Listen to this to get notified of changes in the entry.
  # Happens BEFORE pctx[:change], pctx[:change_to], but AFTER pctx[:change_from]
  pctx[:entry] = Observable{Union{Nothing, ImageDescriptor}}(nothing)

  # Listen to this to get notified of change events in the entry
  pctx[:change] = Observable{Tuple}((nothing, nothing))
  pctx[:change_from] = Observable{Union{Nothing, ImageDescriptor}}(nothing)
  pctx[:change_to] = Observable{Union{Nothing, ImageDescriptor}}(nothing)

  # Listen or notify on this observable to handle or send store-update queries
  pctx[:update] = Observable{Union{Nothing, ImageDescriptor}}(nothing)

  on(ctx[:update]) do _
    pctx[:update][] = pctx[:entry][]
  end

  on(pctx[:activate_id], update = true) do id
    entries = pctx[:entries][]

    index = findfirst(entry -> entry.id == id, entries)
    next = isnothing(index) ? nothing : entries[index]
    index = findfirst(entry -> entry.id == pctx[:recent_id][], entries)
    prev = isnothing(index) ? nothing : entries[index]

    pctx[:recent_id][] = id
    pctx[:change_from][] = prev
    pctx[:entry][] = next
    pctx[:change_to][] = next
    pctx[:change][] = (next, prev)
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

  # All dependencies set. Now select the correct index
  pctx[:select_index][] = store.active_index

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

# usage example of ImageStores:
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
