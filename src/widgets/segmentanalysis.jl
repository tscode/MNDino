

struct Segment <: Widget
  mask::BitMatrix
  color::Color
  source::Int
end

struct SegmentAnalysisWidget <: Widget
  title::String
  mask_provider::Symbol
end

function SegmentAnalysisWidget(title; mask_provider)
  return SegmentAnalysisWidget(
    title,
    mask_provider,
  )
end

function initcontext(widget::SegmentAnalysisWidget, ctx)
  wctx = Dict{Union{Symbol, Int}, Any}()

  loadentries!(wctx, widget, [:title], obs = true)
  loadentries!(wctx, widget, [:mask_provider], obs = false)

  pctx = loadcontext(ctx, wctx[:mask_provider])
  wctx[:nmasks] = pctx[:nmasks]

  for index in 1:wctx[:nmasks]
    wctx[index] = Dict{Symbol, Any}()
    wctx[index][:mask] = pctx[index][:mask]
    wctx[index][:color] = pctx[index][:color]
    wctx[index][:name] = pctx[index][:name]
  end

  return wctx
end


gridlayoutoptions(widget::SegmentAnalysisWidget, wctx) = (size=(2, 2),)

function plotwidget(widget::SegmentAnalysisWidget, layout, wctx, theme)

  rowgap!(layout, 1, 15)

  Label(
    layout[1, :],
    wctx[:title],
    halign = :left,
    tellwidth = false,
    font = :bold,
    fontsize = theme[:widget_titlesize],
  )

  ax = Axis(
    layout[2, 1],
    aspect = DataAspect(),
    yticklabelsvisible = false,
    yticksvisible = false,
    xticklabelsvisible = false,
    xticksvisible = false,
    yticklabelsize = theme[:widget_ticksize],
    xticklabelsize = theme[:widget_ticksize],
    panbutton=Makie.Mouse.left,
    height = 250,
    width = 250,
  )
  Makie.deregister_interaction!(ax, :rectanglezoom)
  Makie.deregister_interaction!(ax, :scrollzoom)
  Makie.deregister_interaction!(ax, :dragpan)

  for index in 1:wctx[:nmasks]
    Makie.image!(
      ax,
      wctx[index][:mask],
      colorrange = (0., 1.),
      colormap = [
        (:black, 0.01),
        (0.8wctx[index][:color], 0.5)
      ],
    )
  end

  elements = map(1:wctx[:nmasks]) do index
    return MarkerElement(
      color = 0.8wctx[index][:color],
      marker = :rect,
      markersize = 17,
      )
  end
  labels = map(1:wctx[:nmasks]) do index
    return wctx[index][:name]
  end

  Legend(
    layout[2, 2],
    elements,
    labels,
    "Segments",
    framevisible = false,
  )

  return
end
