
struct Segment <: Widget
  mask::BitMatrix
  color::Color
  source::Int
end

struct SegmentsWidget <: Widget
  title::String
  segment_provider::Symbol
end

function SegmentsWidget(title; segment_provider)
  return SegmentsWidget(title, segment_provider)
end

function initcontext(widget::SegmentsWidget, ctx)
  wctx = Dict{Union{Symbol, Int}, Any}()

  loadentries!(wctx, widget; obs = false)
  mpctx = loadcontext(ctx, wctx[:segment_provider])

  wctx[:nmasks] = mpctx[:nmasks]
  wctx[:masks] = Dict{Int, Any}()

  for index in 1:wctx[:nmasks]
    wctx[:masks][index] = Dict{Symbol, Any}()
    wctx[:masks][index][:mask] = mpctx[index][:mask]
    wctx[:masks][index][:color] = mpctx[index][:color]
    wctx[:masks][index][:name] = mpctx[index][:name]
  end

  return wctx
end

function _segments_topline(layout, wctx, theme)
  Label(
    layout[1, :],
    wctx[:title];
    halign = :left,
    tellwidth = false,
    font = :bold,
    fontsize = theme[:titlesize],
  )
  return
end

function _segments_showsegments(layout, wctx, theme)
  ax = Axis(
    layout[2, 1];
    aspect = DataAspect(),
    yticklabelsvisible = false,
    yticksvisible = false,
    xticklabelsvisible = false,
    xticksvisible = false,
    yticklabelsize = theme[:ticksize],
    xticklabelsize = theme[:ticksize],
    panbutton = Makie.Mouse.left,
    height = 250,
    width = 250,
  )
  Makie.deregister_interaction!(ax, :rectanglezoom)
  Makie.deregister_interaction!(ax, :scrollzoom)
  Makie.deregister_interaction!(ax, :dragpan)

  for index in 1:wctx[:nmasks]
    Makie.image!(
      ax,
      wctx[:masks][index][:mask];
      colorrange = (0.0, 1.0),
      colormap = [(:black, 0.01), (0.8wctx[:masks][index][:color], 0.5)],
    )
  end

  elements = map(1:wctx[:nmasks]) do index
    return MarkerElement(;
      color = 0.8wctx[:masks][index][:color],
      marker = :rect,
      markersize = 20,
    )
  end
  labels = map(1:wctx[:nmasks]) do index
    return "S$index: " * wctx[:masks][index][:name]
  end

  return Legend(
    layout[2, 2],
    elements,
    labels;
    framevisible = false,
    valign = :top,
    labelsize = theme[:fontsize],
    labelfont = :bold,
    tellwidth = true,
  )
end

gridlayoutoptions(::SegmentsWidget, wctx) = (size = (2, 4),)

function plotwidget(::SegmentsWidget, layout, wctx, theme)
  _segments_topline(layout, wctx, theme)
  _segments_showsegments(layout, wctx, theme)
  return
end
