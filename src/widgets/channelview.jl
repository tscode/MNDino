
# TODO: This plane selection struct should be renamed to something more sensible.
struct View <: Storable
  zindex::Int
  tindex::Int
end

# TODO: Rename this to ChannelWidget
struct ChannelViewWidget <: Widget
  title::String
  filter::Filter
  channels::Vector{Channel}
  image_store::Symbol
  variable_store::Symbol
end

function ChannelViewWidget(
  title::String;
  image_store,
  variable_store,
  channels = [],
  filter = NoFilter(),
)
  return ChannelViewWidget(title, filter, channels, image_store, variable_store)
end

function _viewdefault(image)
  return View(zindexdefault(image), tindexdefault(image))
end

function initcontext(widget::ChannelViewWidget, ctx)
  wctx = Dict{Union{Symbol, Int}, Any}()

  loadentries!(wctx, widget, [:title, :filter => Filter]; obs = true)

  loadentries!(
    wctx,
    widget,
    [:channels, :image_store, :variable_store];
    obs = false,
  )

  # Load the variable store. 2D channel views C1 to Cn will be defined.
  vars = loadcontext(ctx, wctx[:variable_store])

  # Load the image store. z-layer selections for each
  # image will be stored in the shelf
  store = loadcontext(ctx, wctx[:image_store])
  loadentries!(wctx, store, [:entry, :image])
  shelf = addshelf!(store, :channelview, View)

  wctx[:nzlayers] = lift(wctx[:image]) do img
    isnothing(img) ? 1 : nzlayers(img)
  end

  wctx[:view] = Observable(View(1, 1))
  if !isnothing(wctx[:image][])
    wctx[:view][] = _viewdefault(wctx[:image][])
  end

  wctx[:zindex] = lift(getvalue(:zindex), wctx[:view])
  wctx[:tindex] = lift(getvalue(:tindex), wctx[:view])

  addvariable!(vars, :zindex, wctx[:zindex])
  addvariable!(vars, :tindex, wctx[:tindex])

  wctx[:mouse_position] = Observable(Point2f(NaN, NaN))
  wctx[:focused] = Observable(-1; ignore_equal_values = true)
  wctx[:reset_clipping] = Observable(nothing)

  # Automatically derive channels from first image if not provided
  if isempty(wctx[:channels])
    @assert !isempty(store[:entries][]) """
    Cannot initialize channel view context: No channel information provided. 
    """
    img = imagefile(first(store[:entries][]))
    wctx[:channels] = channels(img)
  end
  wctx[:nchannels] = length(wctx[:channels])

  # Entries for each channel
  for (index, c) in enumerate(wctx[:channels])
    wctx[index] = Dict{Symbol, Any}()

    wctx[index][:name] = Observable(c.name)
    wctx[index][:color] = Observable(c.color)

    data = lift(wctx[:view]) do view
      img = wctx[:image][]
      variant = (;) # TODO: The variant will eventually come from the selection widget?
      if isnothing(img)
        # dummy data if no image is selected
        return fill(NaN32, 1, 1)
      elseif c.cindex > nchannels(img)
        return zeros(Float32, planesize(img; variant...))
      else
        return Float32.(
          imagedata(img, view.zindex, c.cindex, view.tindex; variant...)
        )
      end
    end
    data_f = lift((f, data) -> f(data), wctx[:filter], data)

    wctx[index][:data] = data_f
    wctx[index][:size] = lift(size, data_f; ignore_equal_values = true)
    wctx[index][:extrema] = lift(extrema, data_f)

    wctx[index][:crange] = Observable(wctx[index][:extrema][])
    wctx[index][:axis] = Observable{Any}(nothing)
    wctx[index][:mouse_value] = lift(wctx[:mouse_position]) do pos
      return _value_at(data_f[], pos)
    end

    wctx[index][:raw] = Dict{Symbol, Any}()
    wctx[index][:raw][:data] = data
    wctx[index][:raw][:size] = lift(size, data)
    wctx[index][:raw][:extrema] = lift(extrema, data)

    addvariable!(vars, Symbol("C$index"), data)

    onany(wctx[index][:name], wctx[index][:color]) do name, color
      return wctx[:channels][index] = Channel(c.cindex, name, color)
    end
  end

  # React if the selected image changes
  # on(store[:change]) do (next, prev)
  # end

  on(store[:change]) do (_, prev)
    if !isnothing(prev)
      shelf[prev.id] = View(wctx[:zindex][], wctx[:tindex][])
    end
  end

  on(store[:entry]) do next
    if !isnothing(next)
      wctx[:view][] = get(shelf, next.id) do
        return _viewdefault(imagefile(next))
      end
    else
      wctx[:view][] = View(1, 1)
    end
  end

  on(store[:update]) do _
    entry = store[:entry][]
    if !isnothing(entry)
      shelf[entry.id] = View(wctx[:zindex][], wctx[:tindex][])
    end
  end

  on(wctx[:image]) do img
    if !isnothing(img) && nchannels(img) != wctx[:nchannels]
      @error """
      The number of channels changed when an image was selected.
      The channel view widget currently cannot handle this.
      For proper functionality, you should remove this image from the project.
      """
    end
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

function _channelview_filename(layout, yindex, wctx, theme)
  name = lift(wctx[:entry]) do entry
    isnothing(entry) ? "no image selected" : basename(entry.path)
  end
  Label(
    layout[yindex, :],
    name;
    fontsize = theme[:fontsize],
    color = (:black, 0.7),
    halign = :left,
  )
  return
end

function _channelview_topline(layout, yindex, wctx, theme)
  layout = GridLayout(layout[yindex, :])
  Label(
    layout[1, 1],
    wctx[:title];
    halign = :left,
    tellwidth = true,
    font = :bold,
    fontsize = theme[:titlesize],
  )

  filter_menu = Menu(
    layout[1, 3];
    options = ["GaussFilter"], #, "MedianFilter", "LaplaceFilter"],
    default = "GaussFilter",
    fontsize = theme[:fontsize],
    width = 100,
  )

  sublayout = GridLayout(layout[1, 4]; default_rowgap = 0)

  filter_slider =
    Slider(sublayout[2, 1]; range = 1:5, tellheight = false, width = 75)
  Label(
    sublayout[1, 1],
    lift(r -> "radius $r", filter_slider.value);
    fontsize = 12,
    padding = (0, 0, 0, 0),
    tellheight = false,
    tellwidth = false,
  )

  filter_toggle = Toggle(layout[1, 5]; height = 20)
  filter_indicator = Label(
    layout[1, 6],
    "";
    font = :bold,
    fontsize = theme[:fontsize],
    width = 100,
    halign = :right,
    justification = :center,
  )
  reset_button = Button(
    layout[1, 8];
    label = "↺ Reset",
    halign = :right,
    font = :bold,
    fontsize = theme[:fontsize],
  )

  on(reset_button.clicks) do _
    notify(wctx[:reset_clipping])
    if !isnothing(wctx[:image][])
      wctx[:view][] = _viewdefault(wctx[:image][])
    end
    set_close_to!(filter_slider, 1)
    return filter_toggle.active[] = false
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

  on(wctx[:filter]; update = true) do filter
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
    cindex = wctx[:channels][index].cindex
    name = wctx[index][:name]
    color = wctx[index][:color]
    sublayout = GridLayout(layout[yindex, index], 2, 3)
    rowgap!(sublayout, 1, 4)
    Box(
      sublayout[1, :];
      strokevisible = false,
      color = lift(c -> 0.4c, color),
    )
    Label(
      sublayout[1, :],
      "C$index";
      font = :bold,
      fontsize = theme[:fontsize] + 1,
      halign = :center,
      color = RGB(0.98, 0.98, 0.98),
      padding = (0, 0, 5, 5),
    )
    Label(
      sublayout[1, :],
      "c-index $cindex";
      fontsize = theme[:fontsize],
      halign = :right,
      color = RGBA(1, 1, 1, 0.8),
      padding = (0, 7, 5, 5),
    )
    name_textbox = Textbox(
      sublayout[2, :];
      stored_string = name,
      fontsize = theme[:fontsize] + 1,
      halign = :center,
      bordercolor = :transparent,
      textpadding = (3, 3, 3, 3),
      cornerradius = 0,
    )
    on(name_textbox.stored_string) do name
      if wctx[index][:name][] != name
        wctx[index][:name][] = name
      end
    end
  end
  return
end

function _channelview_histograms(layout, yindex, wctx, theme)
  nchannels = wctx[:nchannels]

  axes = map(1:nchannels) do index
    limits = lift(wctx[index][:extrema]) do minmax
      if any(isnan, minmax)
        minmax = (0f0, 1f0)
      elseif minmax[1] == minmax[2] # prevent degenerate axis limits
        minmax = (minmax[1] - 1.0f-5, minmax[2] + 1.0f-5)
      end
      return (minmax, (0, nothing))
    end

    color = lift(wctx[index][:data]) do data
      any(isnan, data) ? (:transparent) : (:black)
    end

    values = lift(wctx[index][:data]) do data
      any(isnan, data) ? Float32[0, 1] : reshape(data, :)
    end

    ax = Axis(layout[yindex, index]; limits)

    onany(wctx[index][:data]) do _
      return reset_limits!(ax)
    end

    deregister_interaction!(ax, :rectanglezoom)
    deregister_interaction!(ax, :scrollzoom)
    deregister_interaction!(ax, :dragpan)
    hidedecorations!(ax)
    hidespines!(ax, :t, :l, :r)

    hist!(
      ax,
      values;
      bins = 128,
      color,
    )
    vlines!(
      ax,
      lift(collect, wctx[index][:crange]);
      linewidth = 1.25,
      color = lift(c -> 0.7c, wctx[index][:color]),
    )
    vlines!(
      ax,
      lift(v -> [v], wctx[index][:mouse_value]);
      linewidth = 1,
      color = lift(c -> 0.6c, wctx[index][:color]),
      alpha = 0.75,
    )

    return ax
  end

  return
end

function _channelview_sliders(layout, yindex, wctx, theme)
  for index in 1:wctx[:nchannels]
    slider = IntervalSlider(
      layout[yindex, index];
      range = LinRange(0, 1, 128),
      tellheight = true,
      color_inactive = RGB(0.9, 0.9, 0.9),
      color_active = lift(c -> 0.5c, wctx[index][:color]),
      color_active_dimmed = lift(c -> (0.5c, 0.25), wctx[index][:color]),
    )
    on(wctx[:reset_clipping]) do _
      return set_close_to!(slider, 0, 1)
    end
    onany(slider.interval, wctx[index][:extrema]) do interval, minmax
      min = (minmax[2] - minmax[1]) * interval[1] + minmax[1]
      max = (minmax[2] - minmax[1]) * interval[2] + minmax[1]
      return wctx[index][:crange][] = (min, max)
    end
  end
  return
end

function _channelview_slices(layout, yindex, wctx, theme)
  axes = map(1:wctx[:nchannels]) do index
    ax = Axis(
      layout[yindex, index];
      aspect = DataAspect(),
      yticklabelsvisible = index == 1,
      yticksvisible = index == 1,
      yticklabelsize = theme[:ticksize],
      xticklabelsize = theme[:ticksize],
      panbutton = Makie.Mouse.left,
    )
    Makie.deregister_interaction!(ax, :rectanglezoom)
    Makie.deregister_interaction!(ax, :dragpan)
    Makie.register_interaction!(ax, :dragpan, DragPan(0.2))

    Makie.image!(
      ax,
      wctx[index][:data];
      colorrange = wctx[index][:crange],
      colormap = lift(c -> [:black, c], wctx[index][:color]),
    )
    onany(wctx[:entry], wctx[index][:size]) do _, sz
      ax.limits[] = ((0, sz[1]), (0, sz[2]))
      return
    end
    wctx[index][:axis][] = ax
    return ax
  end
  linkaxes!(axes...)
  return
end

function _channelview_mouseposition!(wctx)
  events =
    [MouseEventTypes.over, MouseEventTypes.leftdrag, MouseEventTypes.rightdrag]
  for index in 1:wctx[:nchannels]
    ax = wctx[index][:axis][]
    register_interaction!(ax, :channelview) do event::MouseEvent, ax
      if event.type in events
        wctx[:mouse_position][] = event.data
        wctx[:focused][] = index
      elseif event.type == MouseEventTypes.out
        wctx[:mouse_position][] = Point2f(NaN, NaN)
        wctx[:focused][] = -1
      end
    end
  end
  return
end

function _channelview_values(layout, yindex, wctx, theme)

  for index in 1:wctx[:nchannels]
    Label(
      layout[yindex, index],
      lift(v -> string(round(v[1])), wctx[index][:extrema]);
      color = (:black, 0.75),
      halign = :left,
      fontsize = theme[:ticksize],
      tellwidth = false,
    )
    Label(
      layout[yindex, index],
      lift(v -> string(round(v[2])), wctx[index][:extrema]);
      color = (:black, 0.75),
      halign = :right,
      fontsize = theme[:ticksize],
      tellwidth = false,
    )
    # TODO: The update of value in the label causes a LOT of GC.
    # Throttling helps, but this should probably be handled more efficiently
    # in Makie?
    mouse_value = Observables.throttle(0.25, wctx[index][:mouse_value]) 
    value = lift(mouse_value) do val
      return isnan(val) ? "" : string(round(val))
    end
    Label(
      layout[yindex, index],
      value;
      color = (:black, 1.0),
      halign = :center,
      fontsize = theme[:ticksize],
      tellwidth = false,
    )
  end
  return
end

function _channelview_zselector(layout, xindex, wctx, theme)
  sublayout = GridLayout(layout[xindex:end, end], 5, 1; default_rowgap = 7)
  rowgap!(sublayout, 4, 3)
  colsize!(sublayout, 1, 25)
  Label(
    sublayout[1, 1],
    "z-index";
    rotation = -90 / 180 * pi,
    fontsize = theme[:ticksize],
  )
  Label(
    sublayout[2, 1],
    lift(string, wctx[:zindex]);
    rotation = -90 / 180 * pi,
    fontsize = theme[:ticksize],
  )
  slider = Slider(
    sublayout[3, 1];
    horizontal = false,
    range = lift(nz -> 1:nz, wctx[:nzlayers]),
    startvalue = wctx[:zindex][],
  )
  up_button = Button(
    sublayout[4, 1];
    label = "▲",
    padding = (6, 6, 4, 4),
    fontsize = theme[:fontsize],
  )
  down_button = Button(
    sublayout[5, 1];
    label = "▼",
    padding = (6, 6, 4, 4),
    fontsize = theme[:fontsize],
  )
  on(slider.value) do zindex
    if wctx[:view][].zindex != zindex
      wctx[:view][] = View(zindex, wctx[:tindex][])
    end
  end
  on(down_button.clicks) do _
    return set_close_to!(slider, slider.value[] - 1)
  end
  on(up_button.clicks) do _
    return set_close_to!(slider, slider.value[] + 1)
  end
  on(wctx[:zindex]) do zindex
    if zindex != slider.value
      set_close_to!(slider, zindex)
    end
  end

  # Switch Z-layers by clicking up / down on the keyboard
  on(Makie.events(layout[1, 1]).keyboardbutton) do event
    event.action != Keyboard.press && return
    if event.key == Keyboard.down
      notify(down_button.clicks)
    elseif event.key == Keyboard.up
      notify(up_button.clicks)
    end
  end

  return
end

function gridlayoutoptions(widget::ChannelViewWidget, wctx)
  width = wctx[:nchannels] + 1
  size = (7, width)
  return (size = size, outer = true)
end

function plotwidget(widget::ChannelViewWidget, layout, wctx, theme)
  _channelview_topline(layout, 1, wctx, theme)
  _channelview_filename(layout, 2, wctx, theme)

  _channelview_names(layout, 3, wctx, theme)
  _channelview_sliders(layout, 4, wctx, theme)
  _channelview_histograms(layout, 5, wctx, theme)
  _channelview_values(layout, 6, wctx, theme)
  _channelview_slices(layout, 7, wctx, theme)
  _channelview_zselector(layout, 3, wctx, theme)
  _channelview_mouseposition!(wctx)

  rowsize!(layout, 5, Fixed(25))
  # colsize!(layout, 1, Aspect(7, 1.0))
  rowgap!(layout, 2, 15)
  rowgap!(layout, 5, 5)
  rowgap!(layout, 6, 5)

  return
end
