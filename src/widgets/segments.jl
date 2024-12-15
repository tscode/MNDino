
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
      colormap = lift(
        c -> [(:black, 0.01), (0.8c, 0.5)],
        wctx[:masks][index][:color],
      ),
    )
  end

  sublayout = GridLayout(layout[2, 2], 3wctx[:nmasks], 1)
  for index in 1:wctx[:nmasks]
    mask = wctx[:masks][index][:mask]
    Label(
      sublayout[3index - 2, 1],
      lift(n -> "S$index: " * n, wctx[:masks][index][:name]);
      font = :bold,
      fontsize = theme[:fontsize],
      color = lift(c -> 0.6c, wctx[:masks][index][:color]),
      halign = :left,
    )
    Label(
      sublayout[3index - 1, 1],
      lift(m -> "pixels: " * string(count(m)), mask);
      fontsize = theme[:ticksize],
      color = (:black, 0.7),
      halign = :left,
    )
    fraction = m -> string(round(100mean(m); digits = 2))
    Label(
      sublayout[3index, 1],
      lift(m -> "fraction: " * fraction(m) * "%", mask);
      fontsize = theme[:ticksize],
      color = (:black, 0.7),
      halign = :left,
    )
    rowgap!(sublayout, 3index - 2, 5)
    rowgap!(sublayout, 3index - 1, 5)
  end

  return
end

gridlayoutoptions(::SegmentsWidget, wctx) = (size = (2, 2),)

function plotwidget(::SegmentsWidget, layout, wctx, theme)
  _segments_topline(layout, wctx, theme)
  _segments_showsegments(layout, wctx, theme)
  colgap!(layout, 15)
  return
end
