

struct Segment <: Widget
  data::BitMatrix
  color::Color
  source::Int
end

struct SegmentWidget <: Widget
  title::String
  provider::Symbol
  segments::Dict{String, Segment}
end

function SegmentWidget(title; provider)
  return SegmentWidget(
    title,
    provider,
    Dict{String, Segment}(),
  )
end


function initcontext(widget::SegmentWidget, ctx)
  wctx = Dict{Symbol, Any}()

  loadentries!(
    wctx,
    widget,
    [:title, :segments],
    obs = true
  )
  loadentries!(
    wctx,
    widget,
    [:provider],
    obs = false
  )
  # loadfromwidget!(
  #   wctx,
  #   ctx,
  #   wctx[:provider],
  #   [:axes],
  #   obs = false,
  # )

  wctx[:selected] = Observable{Union{Nothing, String}}(nothing)
  wctx[:segment] = Observable{Union{Nothing, Segment}}(nothing)
  wctx[:candidate] = Observable{Union{Nothing, Segment}}(nothing)

  old_selected = Ref{Union{Nothing, String}}(nothing)
  onany(wctx[:segments], wctx[:selected]) do segments, sel
  old_sel = old_selected[]
    # Save old (deselected) segment
    if sel != old_sel && old_sel in keys(segments)
      segments[old_sel] = wctx[:segment][]
    end
    # Load selected segment
    wctx[:segment][] = get(segments, sel, nothing)
    old_selected[] = sel
  end

  return wctx
end


# TODOOO
function plotwidget(widget::SegmentWidget, layout, wctx, theme)
end
