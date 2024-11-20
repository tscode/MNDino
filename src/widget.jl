"""
A context provider that has a graphical representation.

Must implement `gridlayoutoptions` (due to a limitation in Makie's layout
system) and `plotwidget`.
"""
abstract type Widget <: Provider end

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


