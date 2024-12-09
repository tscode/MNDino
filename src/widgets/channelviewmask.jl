
"""
Widget that provides basic comparison, drawing, and segmentation functionality
for `ChannelViewWidiget`s.
"""
struct ChannelViewMaskWidget <: Widget
  title::String
  parent::Symbol
  image_store::Symbol
  variable_store::Symbol
end

function ChannelViewMaskWidget(title = ""; parent, image_store, variable_store)
  return ChannelViewMaskWidget(title, parent, image_store, variable_store)
end

function initcontext(widget::ChannelViewMaskWidget, ctx)
  wctx = Dict{Union{Int, Symbol}, Any}()

  loadentries!(wctx, widget, [:title]; obs = true)
  loadentries!(
    wctx,
    widget,
    [:parent, :image_store, :variable_store];
    obs = false,
  )

  # Load the variable store. Segments (masks) S1 to Sn will be defined.
  vars = loadcontext(ctx, wctx[:variable_store])

  # Load the image store. The masks for each image will be stored
  # in the shelf.
  store = loadcontext(ctx, wctx[:image_store])
  shelf = addshelf!(store, :mask)

  # Derive entries from the parent channel view
  cctx = loadcontext(ctx, wctx[:parent])
  wctx[:mouse_position] = cctx[:mouse_position]
  wctx[:focused] = cctx[:focused]
  wctx[:nchannels] = cctx[:nchannels]
  wctx[:nmasks] = cctx[:nchannels]

  for index in 1:wctx[:nchannels]
    wctx[index] = Dict{Symbol, Any}()
    wctx[index][:data] = cctx[index][:data]
    wctx[index][:axis] = cctx[index][:axis]
    wctx[index][:size] = cctx[index][:size]
    wctx[index][:color] = cctx[index][:color]
    wctx[index][:crange] = cctx[index][:crange]
    wctx[index][:name] = cctx[index][:name]

    wctx[index][:mask] = lift(wctx[index][:size]) do sz
      mask = BitMatrix(undef, sz)
      mask .= false
      return mask
    end

    addvariable!(vars, "S$index", wctx[index][:mask])
  end


  update_store = prev -> begin
    if !haskey(shelf, prev.id)
      shelf[prev.id] = Dict{Int, BitMatrix}()
    end
    for index in 1:wctx[:nchannels]
      shelf[prev.id][index] = copy(wctx[index][:mask][])
    end
  end

  on(update_store, store[:update])
  on(update_store, store[:change_from])

  load_next = next -> begin
    for index in 1:wctx[:nchannels]
      if haskey(shelf, next.id)
        wctx[index][:mask][] = shelf[next.id][index]
      else
        sz = wctx[index][:size][]
        mask = BitMatrix(undef, sz)
        mask .= false
        wctx[index][:mask][] = mask
      end
    end
  end

  on(load_next, store[:change_to]; update = true)

  wctx[:pointer_on] = Observable(true)
  wctx[:mask_on] = Observable(true)
  wctx[:pen_on] = Observable(false)
  wctx[:segment_on] = Observable(false)
  wctx[:pen_size] = Observable(100)

  return wctx
end

gridlayoutoptions(widget::ChannelViewMaskWidget, wctx) = (size = (4, 1),)

function _pointer_interaction!(wctx)
  for index in 1:wctx[:nchannels]
    # Plot the position marker
    ax = wctx[index][:axis][]
    scatter!(
      ax,
      lift(p -> [p], wctx[:mouse_position]);
      markersize = 6,
      strokewidth = 1,
      color = :white,
      strokecolor = :black,
      visible = wctx[:pointer_on],
    )
  end
  return
end

function _mask_interaction!(wctx)
  for index in 1:wctx[:nchannels]
    ax = wctx[index][:axis][]
    mask = wctx[index][:mask]
    color = complement(wctx[index][:color])
    colormap = [:transparent, (color, 0.3)]

    Makie.image!(
      ax,
      mask;
      colormap = colormap,
      colorrange = (0, 1),
      visible = wctx[:mask_on],
    )
  end
  return
end

struct PenInteraction
  mask::Observable{BitMatrix}
  wctx::Dict
end

function Makie.process_interaction(pen::PenInteraction, event::MouseEvent, ax)
  mask = pen.mask[]

  r = round(Int, pen.wctx[:pen_size][] / 2.8)
  c = round.(Int, event.data)
  irange = max(c[1] - r, 1):min(c[1] + r, size(mask, 1))
  jrange = max(c[2] - r, 1):min(c[2] + r, size(mask, 2))

  left = [MouseEventTypes.leftdown, MouseEventTypes.leftdrag]
  right = [MouseEventTypes.rightdown, MouseEventTypes.rightdrag]

  mask_task = Threads.@spawn begin
    if event.type in left
      tmp = copy(mask)
      for i in irange, j in jrange
        under_pen = (c[1] - i)^2 + (c[2] - j)^2 < r^2
        tmp[i, j] = tmp[i, j] || under_pen
      end
    elseif event.type in right
      tmp = copy(mask)
      for i in irange, j in jrange
        under_pen = (c[1] - i)^2 + (c[2] - j)^2 < r^2
        tmp[i, j] = tmp[i, j] && !under_pen
      end
    else
      tmp = nothing
    end
    tmp
  end

  @async begin
    tmp = fetch(mask_task)
    if !isnothing(tmp)
      mask .= tmp
      @time notify(pen.mask)
    end
  end
  return
end

function Makie.process_interaction(pen::PenInteraction, event::ScrollEvent, ax)
  limits = ax.finallimits[]
  factor = maximum(limits.widths) * 0.04
  size_change = round(Int, event.y * factor)
  return pen.wctx[:pen_size][] = max(1, pen.wctx[:pen_size][] + size_change)
end

function _pen_interaction!(wctx)
  for index in 1:wctx[:nchannels]
    ax = wctx[index][:axis][]
    mask = wctx[index][:mask]

    visible = lift(wctx[:pen_on], wctx[:focused]) do pen, active
      return pen && active == index
    end

    Makie.scatter!(
      ax,
      lift(p -> [p], wctx[:mouse_position]);
      markersize = wctx[:pen_size],
      markerspace = :data,
      strokewidth = 0.75,
      color = (:white, 0.20),
      strokecolor = :white,
      visible = visible,
    )
    on(wctx[:pen_on]) do pen
      if pen
        Makie.deactivate_interaction!(ax, :scrollzoom)
        Makie.deactivate_interaction!(ax, :dragpan)
        Makie.activate_interaction!(ax, :pen)
      else
        Makie.deactivate_interaction!(ax, :pen)
        Makie.activate_interaction!(ax, :scrollzoom)
        Makie.activate_interaction!(ax, :dragpan)
      end
    end

    Makie.register_interaction!(ax, :pen, PenInteraction(mask, wctx))
    if !wctx[:pen_on][]
      Makie.deactivate_interaction!(ax, :pen)
    end
  end

  return
end

struct SegmentInteraction
  mask::Observable{BitMatrix}
  wctx::Dict
  seeds::Observable{Vector{Point2f}}
end

function Makie.process_interaction(
  seg::SegmentInteraction,
  event::ScrollEvent,
  ax,
)
  mask = seg.mask[]
  if event.y < 0
    ImageMorphology.erode!(mask; r = 1)
  else
    ImageMorphology.dilate!(mask; r = 1)
  end
  notify(seg.mask)
  return
end

function Makie.process_interaction(
  seg::SegmentInteraction,
  event::MouseEvent,
  ax,
)
  if event.type in [MouseEventTypes.leftdown]
    seg.seeds[] = [event.data]
  elseif event.type in [MouseEventTypes.leftup]
    seg.seeds[] = [seg.seeds[][1], event.data]
    seeds = map(seg.seeds[]) do seed
      return Tuple(round.(Int, seed))
    end

    index = seg.wctx[:focused][]
    data = seg.wctx[index][:data][]
    cmin, cmax = seg.wctx[index][:crange][]
    cdata = clamp.(data, cmin, cmax)

    segment_task = Threads.@spawn begin
      ImageSegmentation.seeded_region_growing(
        cdata,
        [CartesianIndex(seeds[i]) => i for i in 1:2],
      )
    end
    @async begin
      segments = fetch(segment_task)
      lmap = ImageSegmentation.labels_map(segments)
      seg.mask[] .|= lmap .== 1
      seg.seeds[] = Point2f[]
      notify(seg.mask)
    end
  end
end

function _segment_interaction!(wctx)
  for index in 1:wctx[:nchannels]
    ax = wctx[index][:axis][]
    mask = wctx[index][:mask]

    visible = lift(wctx[:segment_on], wctx[:focused]) do pen, active
      return pen && active == index
    end

    seeds = Observable(Point2f[])

    Makie.scatter!(
      ax,
      seeds;
      marker = :star4,
      markersize = 12,
      strokewidth = 0.5,
      color = complement(wctx[index][:color]),
      strokecolor = :black,
    )

    Makie.scatter!(
      ax,
      lift(p -> [p], wctx[:mouse_position]);
      marker = :star4,
      markersize = 20,
      strokewidth = 1.0,
      color = (:white, 0.00),
      strokecolor = :white,
      visible = visible,
    )
    on(wctx[:segment_on]) do seg
      if seg
        Makie.deactivate_interaction!(ax, :scrollzoom)
        Makie.deactivate_interaction!(ax, :dragpan)
        Makie.activate_interaction!(ax, :segment)
      else
        Makie.deactivate_interaction!(ax, :segment)
        Makie.activate_interaction!(ax, :scrollzoom)
        Makie.activate_interaction!(ax, :dragpan)
      end
    end

    Makie.register_interaction!(
      ax,
      :segment,
      SegmentInteraction(mask, wctx, seeds),
    )
    if !wctx[:segment_on][]
      Makie.deactivate_interaction!(ax, :segment)
    end
  end

  return
end

function _reset_interactions!(wctx)
  for index in 1:wctx[:nchannels]
    ax = wctx[index][:axis][]
    Makie.deactivate_interaction!(ax, :limitreset)
    Makie.register_interaction!(ax, :reset) do event::MouseEvent, ax
      if event.type == MouseEventTypes.leftdoubleclick
        reset_limits!(ax)
      elseif event.type == MouseEventTypes.rightdoubleclick
        wctx[index][:mask][] .= false
        notify(wctx[index][:mask])
      end
    end
  end
end

function _keyboard_control!(wctx)
  for index in 1:wctx[:nchannels]
    ax = wctx[index][:axis][]
    register_interaction!(ax, :keyboard) do _::KeysEvent, ax
      event = Makie.events(ax).keyboardbutton[]
      if event.key in [Keyboard.left_shift, Keyboard.right_shift]
        if event.action == Keyboard.press
          wctx[:segment_on][] = false
          wctx[:pen_on][] = true
        elseif event.action == Keyboard.release
          wctx[:pen_on][] = false
        end
      elseif event.key in [Keyboard.left_control, Keyboard.right_control]
        if event.action == Keyboard.press
          wctx[:pen_on][] = false
          wctx[:segment_on][] = true
        elseif event.action == Keyboard.release
          wctx[:segment_on][] = false
        end
      elseif event.key in [Keyboard.space]
        if event.action == Keyboard.press
          wctx[:mask_on][] = false
        elseif event.action == Keyboard.release
          wctx[:mask_on][] = true
        end
      end
    end
  end
end

function plotwidget(::ChannelViewMaskWidget, layout, wctx, theme)
  rowgap!(layout, 2, 20)

  ca = theme[:color_button_up]
  cb = theme[:color_button_down]
  _decide(a, b) = bool -> bool ? a : b

  pointer_button = Button(
    layout[1, 1];
    label = "P",
    fontsize = theme[:fontsize],
    buttoncolor = lift(_decide(cb, ca), wctx[:pointer_on]),
    labelcolor = lift(_decide(:white, :black), wctx[:pointer_on]),
  )
  mask_button = Button(
    layout[2, 1];
    label = "M",
    fontsize = theme[:fontsize],
    buttoncolor = lift(_decide(cb, ca), wctx[:mask_on]),
    labelcolor = lift(_decide(:white, :black), wctx[:mask_on]),
  )
  pen_button = Button(
    layout[3, 1];
    label = "D",
    fontsize = theme[:fontsize],
    buttoncolor = lift(_decide(cb, ca), wctx[:pen_on]),
    labelcolor = lift(_decide(:white, :black), wctx[:pen_on]),
  )
  segment_button = Button(
    layout[4, 1];
    label = "S",
    fontsize = theme[:fontsize],
    buttoncolor = lift(_decide(cb, ca), wctx[:segment_on]),
    labelcolor = lift(_decide(:white, :black), wctx[:segment_on]),
  )

  _pointer_interaction!(wctx)
  _mask_interaction!(wctx)
  _pen_interaction!(wctx)
  _segment_interaction!(wctx)

  _reset_interactions!(wctx)
  _keyboard_control!(wctx)

  on(pointer_button.clicks) do _
    return wctx[:pointer_on][] = !wctx[:pointer_on][]
  end

  on(mask_button.clicks) do _
    return wctx[:mask_on][] = !wctx[:mask_on][]
  end

  on(pen_button.clicks) do _
    pen_off = wctx[:pen_on][]
    if pen_off
      wctx[:pen_on][] = false
    else
      wctx[:segment_on][] = false
      wctx[:pen_on][] = true
    end
  end

  on(segment_button.clicks) do _
    segment_off = wctx[:segment_on][]
    if segment_off
      wctx[:segment_on][] = false
    else
      wctx[:pen_on][] = false
      wctx[:segment_on][] = true
    end
  end
end
