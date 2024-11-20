
"""
Context provider.

A context provider cultivates a manipulable context during the life time of the
program. Other providers might access all or some of its information.

It has to implement `initcontext`, to initialize a local context, and `update`,
to update the provider from a given context.

Providers that have a graphical UI representation that the user can interact
with are called `Widgets`.
"""
abstract type Provider end

"""
    initcontext(provider::Provider, ctx)

Create the local context of `provider` with temporary access to the global
context `ctx`.
"""
function initcontext end

"""
    update(::Provider, pctx)

Restore a provider from its local context `pctx`, which may have been updated
during the course of the program runtime.
"""
function update end

function update(provider::Provider, pctx)
  W = typeof(provider)
  args = map(fieldnames(W)) do key
    getvalue(pctx, key)
  end
  return W(args...)
end

function _obs_or_value(val, obs = nothing)
  if obs == true
    val = val isa Observable ? val : Observable(val)
  elseif obs == false
    val = val isa Observable ? val[] : val
  end
  return val
end

"""
    loadentry(obj, key [; obs])

Return the entry located at `key` from the object `obj`.
"""
function loadentry(dict::Dict, key; obs = nothing)
  val = get(dict, key) do
    @error "Could not load entry :$key from context."
    @show keys(dict)
    return nothing
  end
  return _obs_or_value(val, obs)
end

function loadentry(obj, key; obs = nothing)
  val = try getfield(obj, key)
  catch _
    @error "Could not load entry :$key from object."
    return nothing
  end
  return _obs_or_value(val, obs)
end

"""
    loadentries!(pctx, obj, keys [; obs])

Load all entries located at a key in the iterable `keys` from the object `obj`
into the local context `pctx`.
"""
function loadentries!(pctx, obj, keys; obs = nothing)
  for key in keys
    pctx[key] = loadentry(obj, key; obs)
  end
  return
end

"""
    loadentries!(pctx, obj [; obs])

Load all entries of the object `obj` into the local context `pctx`.
"""
function loadentries!(pctx, obj::O; obs = nothing) where {O}
  keys = obj isa Dict ? keys(obj) : fieldnames(O)
  loadentries!(pctx, obj, keys; obs)
  return
end

"""
    loadentry(ctx, provider, key [; obs])

Load the entry at location `key` from the local context of `provider`.
"""
function loadentry(ctx, provider::Symbol, key::Symbol; obs = nothing)
  if !haskey(ctx[:providers], provider)
    @error """
    Provider :$provider not found. Options: $(keys(ctx[:providers])).
    """
  end
  return loadentry(ctx[:providers][provider], key; obs)
end

"""
    loadentries!(pctx, ctx, provider, keys [; obs])

Load all entries located at a key in the iterable `keys` from the local context
of `provider` into the context `pctx`.
"""
function loadentries!(pctx, ctx, provider, keys; obs = nothing)
  for key in keys
    pctx[key] = loadentry(ctx, provider, key; obs)
  end
  return
end

"""
    loadcontext(ctx, provider)

Return the full context of the provider with key `provider`.
"""
function loadcontext(ctx, provider)
  return ctx[:providers][provider]
end


