
"""
Supertype for Widgets.
"""
abstract type Widget end

"""
    initcontext(widget::Widget, ctx)

Create the local context of `widget` with access to the global context `ctx`.
"""
function initcontext end

"""
    updatewidget(::Widget, wctx)

Restore a (potentially modified) widget from the provided widget context `wctx`.
"""
function updatewidget end

function updatewidget(widget::Widget, wctx)
  W = typeof(widget)
  args = map(fieldnames(W)) do key
    getvalue(wctx, key)
  end
  return W(args...)
end

"""
    gridlayoutoptions(::Widget)

Returns the grid layout options for the widget.
"""
function gridlayoutoptions end

"""
    plotwidget(::Widget, layout, wctx; theme, frame, outer)

Plot a widget with widget context `wctx` into the layout `layout`.
"""
function plotwidget end

function plotwidgetframe(
  layout,
  theme;
  outer = false,
  framepadding = theme[:widget_framepadding],
)
  position = outer ? layout[:, :, Outer()] : layout[:, :]
  Box(
    position,
    color = theme[:widget_backgroundcolor],
    strokecolor = theme[:widget_framecolor],
    cornerradius = theme[:widget_cornerradius],
    alignmode = Outside(-framepadding),
  )
  return
end

function plotwidget(
  widget::Widget,
  parent,
  wctx;
  theme,
  frame = true,
  kwargs...,
)
  options = gridlayoutoptions(widget, wctx)
  layout = GridLayout(parent[1, 1], options.size...)
  if frame != false
    outer = get(options, :outer, false)
    plotwidgetframe(layout, theme; outer, kwargs...)
  end
  rowgap!(layout, theme[:widget_rowgap])
  colgap!(layout, theme[:widget_colgap])

  return plotwidget(widget, layout, wctx, theme)
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

Load the entry at `key` from the object `obj`.
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
    loadentries!(wctx, obj [; obs])

Load all entries specified by the iterable `keys` from the object `obj` into the
local context `wctx`.
"""
function loadentries!(wctx, obj, keys; obs = nothing)
  for key in keys
    wctx[key] = loadentry(obj, key; obs)
  end
  return
end

"""
    loadentries!(wctx, obj, [; obs])

Load all entries from the object `obj` into the
local context `wctx`.
"""
function loadentries!(wctx, obj::O; obs = nothing) where {O}
  keys = obj isa Dict ? keys(obj) : fieldnames(O)
  loadentries!(wctx, obj, keys; obs)
  return
end

"""
    loadfromwidget(ctx, provider, key [; obs])

Load the entry at `key` from the widget context associated to `provider`.
"""
function loadfromwidget(ctx, provider::Symbol, key::Symbol; obs = nothing)
  if !haskey(ctx[:widgets], provider)
    @error """
    Provider :$provider not found. Options: $(keys(ctx[:widgets])).
    """
  end
  return loadentry(ctx[:widgets][provider], key; obs)
end

"""
    loadfromwidget!(wctx, ctx, widget_key, keys)

Load all entries specified by `keys` from the widget context associated to
`widget_key` into the context `wctx`.
"""
function loadfromwidget!(wctx, ctx, widget_key, keys; obs = nothing)
  for key in keys
    wctx[key] = loadfromwidget(ctx, widget_key, key; obs)
  end
  return
end

"""
    loadwidgetcontext(ctx, widget_key)

Return the full context of the widget with key `widget_key`.
"""
function loadwidgetcontext(ctx, widget_key)
  return ctx[:widgets][widget_key]
end
