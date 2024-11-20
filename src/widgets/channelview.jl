
"""
Metadata object for an image channel.

Stores the index of the channel in the image, the channel name, and an optional
channel color.
"""
struct ChannelSpec
  index::Int
  name::String
  color::Color
end

struct View2D
  zindex::Int
  variant::NamedTuple
end

struct ChannelViewWidget <: Widget
  title::String
  filter::Filter
  channels::Vector{ChannelSpec}
  default_view::Union{View2D, Nothing}
  provider::Symbol
  views::Dict{String, View2D}
end

function ChannelViewWidget(
  title::String;
  provider,
  channels = [],
  filter = NoFilter(),
  default_view = nothing,
)
  return ChannelViewWidget(
    title,
    filter,
    channels,
    default_view,
    provider,
    Dict{String, View2D}(),
  )
end

# function _subsample(data, s)
#   if any(size(data) .% 2^(s-1) .!= 0)
#     @warn """
#     Subsampling currently only works if image size is divisible by 2^(s-1).
#     """
#     return data
#   end
#   sz = div.(size(data), 2^(s-1))
#   return ImageTransformations.imresize(data, sz)
# end

function _derive_channel_specs(image; variant = nothing)
  return map(1:nchannels(image)) do cindex
    meta = metadata(image, cindex; variant)
    ChannelSpec(cindex, meta.name, meta.color)
  end
end

function _derive_default_view(image)
  return View2D(
    defaultzindex(image),
    defaultvariant(image),
  )
end

function initcontext(widget::ChannelViewWidget, ctx)
  wctx = Dict{Union{Symbol, Int}, Any}()

  loadentries!(
    wctx,
    widget,
    [:title, :filter, :default_view],
    obs = true,
  )
  # TODO: find a consistent way to load generic observables
  wctx[:filter] = Observable{Filter}(wctx[:filter][])

  loadentries!(
    wctx,
    widget,
    [:channels, :views, :provider],
    obs = false,
  )

  loadentries!(
    wctx,
    ctx,
    wctx[:provider],
    [:path, :image]
  )

  # Automatically derive channels from first image if not provided
  if isempty(wctx[:channels])
    image = wctx[:image][]
    wctx[:channels] = _derive_channel_specs(image)
  end

  wctx[:nchannels] = length(wctx[:channels])

  old_path = Ref(wctx[:path][])
  wctx[:view] = lift(wctx[:path]) do path
    # Change old view
    if path != old_path[]
      updated_view = View2D(
        getvalue(wctx, :zindex),
        getvalue(wctx, :variant),
      )
      wctx[:views][old_path[]] = updated_view
      old_path[] = path
    end

    # Create / load new view
    if haskey(wctx[:views], path)
      view = wctx[:views][path]
    else
      view = getvalue(wctx, :default_view)
      if isnothing(view)
        view = _derive_default_view(wctx[:image][])
      end
    end
    return view
  end

  wctx[:zindex] = lift(getvalue(:zindex), wctx[:view])
  wctx[:variant] = lift(getvalue(:variant), wctx[:view])
  wctx[:nzlayers] = lift(nzlayers, wctx[:image])

  wctx[:mouse_position] = Observable(Point2f(NaN, NaN))
  wctx[:active_index] = Observable(-1, ignore_equal_values = true)
  wctx[:reset_clipping] = Observable(nothing)

  # Entries for each channel
  for c in wctx[:channels]
    wctx[c.index] = Dict{Symbol, Any}()

    wctx[c.index][:name] = c.name
    wctx[c.index][:color] = c.color

    data = lift(wctx[:image], wctx[:view]) do img, view
      # TODO: this is currently inefficient, since both
      # :image and :view are updated each time the path changes
      return Float32.(imagedata(
        img,
        c.index,
        view.zindex;
        view.variant...
      ))
    end
    data_f = lift((f, data) -> f(data),  wctx[:filter], data)

    wctx[c.index][:data] = data_f
    wctx[c.index][:size] = lift(
      size,
      data_f,
      ignore_equal_values = true
    )
    wctx[c.index][:extrema] = lift(extrema, data_f)

    wctx[c.index][:crange] = Observable(wctx[c.index][:extrema][])
    wctx[c.index][:axis] = Observable{Any}(nothing)
    wctx[c.index][:mouse_value] = lift(wctx[:mouse_position]) do pos
      _value_at(data_f[], pos)
    end

    wctx[c.index][:raw] = Dict{Symbol, Any}()
    wctx[c.index][:raw][:data] = data
    wctx[c.index][:raw][:size] = lift(size, data)
    wctx[c.index][:raw][:extrema] = lift(extrema, data)
  end

  return wctx
end

function _value_at(data, pos)
  if all(isfinite, pos)
    pos = clamp.(round.(Int, pos), 1, size(data))
    value = data[pos...]
  else
    value = NaN
  end
  return value
end

function _channelview_topline(layout, yindex, wctx, theme)
  layout = GridLayout(layout[yindex, :])
  Label(
    layout[1, 1],
    wctx[:title],
    halign = :left,
    tellwidth = false,
    font = :bold,
    fontsize = theme[:widget_titlesize],
  )

  filter_menu = Menu(
    layout[1, 3],
    options = ["GaussFilter"], #, "MedianFilter", "LaplaceFilter"],
    default = "GaussFilter",
    fontsize = theme[:widget_fontsize],
    width = 100,
  )

  sublayout = GridLayout(layout[1, 4], default_rowgap = 0)
  
  filter_slider = Slider(
    sublayout[2, 1],
    range = 1:5,
    tellheight = false,
    width = 75,
  )
  Label(
    sublayout[1, 1],
    lift(r -> "radius $r", filter_slider.value),
    fontsize = 12,
    padding = (0, 0, 0, 0),
    tellheight = false,
    tellwidth = false,
  )

  filter_toggle = Toggle(
    layout[1, 5],
    height = 20,
    width = 40,
  )
  filter_indicator = Label(
    layout[1, 6],
    "",
    font = :bold,
    fontsize = theme[:widget_fontsize],
    width = 100,
    halign = :right,
    justification = :center,
  )
  reset_button = Button(
    layout[1, 8],
    label = "↺ Reset",
    halign = :right,
    font = :bold,
    fontsize = theme[:widget_fontsize],
  )

  on(reset_button.clicks) do _
    notify(wctx[:reset_clipping])
    view = wctx[:default_view][]
    if isnothing(view)
      view = _derive_default_view(wctx[:image][])
    end
    wctx[:view][] = view
    set_close_to!(filter_slider, 1)
    filter_toggle.active[] = false
  end

  onany(
    filter_menu.selection,
    filter_slider.value,
    filter_toggle.active,
  ) do sel, radius, active
    if sel == "GaussFilter" && active
      wctx[:filter][] = GaussFilter(radius)
    elseif sel == "MedianFilter" && active
      wctx[:filter][] = MedianFilter(radius)
    elseif sel == "LaplaceFilter" && active
      wctx[:filter][] = LaplaceFilter()
    elseif active
      @warn "Filter $sel does not exist"
    else
      wctx[:filter][] = NoFilter()
    end
  end

  on(wctx[:filter], update = true) do filter
    if filter == NoFilter()
      filter_indicator.text[] = "FILTER OFF"
      filter_indicator.color[] = RGBf(0.3, 0.3, 0.3)
    else
      filter_indicator.text[] = "FILTER ON"
      filter_indicator.color[] = RGBf(0.2, 0.4, 0.3)
    end
    return
  end
  
  return
end

function _channelview_names(layout, yindex, wctx, theme)
  for index in 1:wctx[:nchannels]
    cindex = wctx[:channels][index].index
    name = wctx[:channels][index].name
    color = wctx[:channels][index].color
    Box(
      layout[yindex, index],
      strokevisible = false,
      color = 0.4color,
    )
    Label(
      layout[yindex, index],
      "C$cindex: $name",
      font = :bold,
      fontsize = theme[:widget_fontsize],
      tellwidth = false,
      halign = :center,
      color = RGB(0.98, 0.98, 0.98),
      padding = (0, 0, 5, 5),
    )
  end
  return
end

function _channelview_histograms(layout, yindex, wctx, theme)
  nchannels = wctx[:nchannels]

  axes = map(1:nchannels) do index
    limits = lift(wctx[index][:extrema]) do minmax
      return (minmax, (0, nothing))
    end
    values = lift(wctx[index][:data]) do data
      return reshape(data, :)
    end

    ax = Axis(
      layout[yindex, index];
      limits,
    )
    deregister_interaction!(ax, :rectanglezoom)
    deregister_interaction!(ax, :scrollzoom)
    deregister_interaction!(ax, :dragpan)
    hidedecorations!(ax)
    hidespines!(ax, :t, :l, :r)
    hist!(
      ax,
      values;
      bins = 128,
      color = :black,
    )
    vlines!(
      ax,
      lift(collect, wctx[index][:crange]),
      linewidth = 1.25,
      color = 0.7wctx[index][:color],
    )
    vlines!(
      ax,
      lift(v -> [v], wctx[index][:mouse_value]),
      linewidth = 1,
      color = 0.6wctx[index][:color],
      alpha = 0.75,
    )
    onany(wctx[index][:data]) do _
      reset_limits!(ax)
    end
    return ax
  end

  return
end

function _channelview_sliders(layout, yindex, wctx, theme)
  for index in 1:wctx[:nchannels]
    slider = IntervalSlider(
      layout[yindex, index],
      range = LinRange(0, 1, 128),
      tellheight = true,
      color_inactive = RGB(0.9, 0.9, 0.9),
      color_active = 0.5wctx[index][:color],
      color_active_dimmed = (0.5wctx[index][:color], 0.25),
    )
    on(wctx[:reset_clipping]) do _
      set_close_to!(slider, 0, 1)
    end
    onany(
      slider.interval,
      wctx[index][:extrema]
    ) do interval, minmax
      min = (minmax[2] - minmax[1]) * interval[1] + minmax[1]
      max = (minmax[2] - minmax[1]) * interval[2] + minmax[1]
      wctx[index][:crange][] = (min, max)
    end
  end
  return
end

function _channelview_slices(layout, yindex, wctx, theme)
  axes = map(1:wctx[:nchannels]) do index
    Box(
      layout[yindex, index],
      color = (:black, 0.05),
      strokevisible = false,
    )
    ax = Axis(
      layout[yindex, index],
      aspect = DataAspect(),
      yticklabelsvisible = index == 1,
      yticksvisible = index == 1,
      yticklabelsize = theme[:widget_ticksize],
      xticklabelsize = theme[:widget_ticksize],
      panbutton=Makie.Mouse.left,
    )
    deregister_interaction!(ax, :rectanglezoom)
    deregister_interaction!(ax, :dragpan)
    register_interaction!(ax, :dragpan, DragPan(0.2))

    Makie.image!(
      ax,
      wctx[index][:data],
      colorrange = wctx[index][:crange],
      colormap = [:black, wctx[index][:color]],
    )
    onany(wctx[:path], wctx[index][:size]) do _, _
      reset_limits!(ax)
    end
    wctx[index][:axis][] = ax
    return ax
  end
  linkaxes!(axes...)
  return
end

function _channelview_mouseposition!(wctx)
  events = [
    MouseEventTypes.over,
    MouseEventTypes.leftdrag,
    MouseEventTypes.rightdrag,
  ]
  for index in 1:wctx[:nchannels]
    ax = wctx[index][:axis][]
    register_interaction!(ax, :channelview) do event::MouseEvent, ax
      if event.type in events 
        wctx[:mouse_position][] = event.data
        wctx[:active_index][] = index
      elseif event.type == MouseEventTypes.out
        wctx[:mouse_position][] = Point2f(NaN, NaN)
        wctx[:active_index][] = -1
      end
    end
  end
  return
end

function _channelview_values(layout, yindex, wctx, theme)
  for index in 1:wctx[:nchannels]
    Label(
      layout[yindex, index],
      lift(v -> string(round(v[1])), wctx[index][:extrema]),
      color = (:black, 0.75),
      halign = :left,
      fontsize = theme[:widget_ticksize],
      tellwidth = false,
    )
    Label(
      layout[yindex, index],
      lift(v -> string(round(v[2])), wctx[index][:extrema]),
      color = (:black, 0.75),
      halign = :right,
      fontsize = theme[:widget_ticksize],
      tellwidth = false,
    )
    value = lift(wctx[index][:mouse_value]) do val
      return isnan(val) ? "" : string(round(val))
    end
    Label(
      layout[yindex, index],
      value,
      color = (:black, 1.0),
      halign = :center,
      fontsize = theme[:widget_ticksize],
      tellwidth = false,
    )
  end
  return
end

function _channelview_zselector(layout, xindex, wctx, theme)
  sublayout = GridLayout(
    layout[xindex:end, end],
    5,
    1,
    default_rowgap = 7,
  )
  rowgap!(sublayout, 4, 3)
  colsize!(sublayout, 1, 25)
  Label(
    sublayout[1, 1],
    "z-index",
    rotation = -90 / 180 * pi,
    fontsize = theme[:widget_ticksize],
  )
  Label(
    sublayout[2, 1],
    lift(string, wctx[:zindex]),
    rotation = -90 / 180 * pi,
    # color = :darkgray,
    fontsize = theme[:widget_fontsize],
  )
  slider = Slider(
    sublayout[3, 1],
    horizontal = false,
    range = lift(nz -> 1:nz, wctx[:nzlayers]),
    startvalue = wctx[:zindex][],
  )
  up_button = Button(
    sublayout[4, 1],
    label = "▲",
    padding = (6, 6, 4, 4),
    fontsize = theme[:widget_fontsize],
  )
  down_button = Button(
    sublayout[5, 1],
    label = "▼",
    padding = (6, 6, 4, 4),
    fontsize = theme[:widget_fontsize],
  )
  on(slider.value) do zindex
    if wctx[:view][].zindex != zindex
      wctx[:view][] = View2D(zindex, wctx[:variant][])
    end
  end
  on(down_button.clicks) do _
    set_close_to!(slider, slider.value[] - 1)
  end
  on(up_button.clicks) do _
    set_close_to!(slider, slider.value[] + 1)
  end
  on(wctx[:zindex]) do zindex
    if zindex != slider.value
      set_close_to!(slider, zindex)
    end
  end
  return
end

function gridlayoutoptions(widget::ChannelViewWidget, wctx)
  width = wctx[:nchannels] + 1
  size = (6, width)
  return (size = size, outer = true)
end

function plotwidget(widget::ChannelViewWidget, layout, wctx, theme)
  _channelview_topline(layout, 1, wctx, theme)
  _channelview_names(layout, 2, wctx, theme)
  _channelview_sliders(layout, 3, wctx, theme)
  _channelview_histograms(layout, 4, wctx, theme)
  _channelview_values(layout, 5, wctx, theme)
  _channelview_slices(layout, 6, wctx, theme)
  _channelview_zselector(layout, 2, wctx, theme)
  _channelview_mouseposition!(wctx)

  rowsize!(layout, 4, Fixed(50))
  rowsize!(layout, 6, Aspect(1, 1.0))

  rowgap!(layout, 1, 15)

  rowgap!(layout, 4, 5)
  rowgap!(layout, 5, 5)
  return
end
