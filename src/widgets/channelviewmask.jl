
"""
Storage for one mask per mask channel.
"""
struct MaskData <: Storable
  masks::OrderedDict{Int, Matrix{Bool}}
end

MaskData() = MaskData(OrderedDict{Int, Matrix{Bool}}())

"""
Widget that extends a [`ChannelViewWidget`] by adding mask drawing and
segmentation functionality.
"""
struct ChannelViewMaskWidget <: Widget
  title::String
  mask_channels::Vector{Channel}
  parent::Symbol
  image_store::Symbol
  variable_store::Symbol
end

function ChannelViewMaskWidget(
  title = "";
  parent,
  image_store,
  variable_store,
)
  return ChannelViewMaskWidget(
    title,
    [],
    parent,
    image_store,
    variable_store,
  )
end

# TODO: Support mask channels that are independent from image channels
function initcontext(widget::ChannelViewMaskWidget, ctx)
  wctx = Dict{Union{Int, Symbol}, Any}()

  loadentries!(wctx, widget, [:title]; obs = true)
  loadentries!(wctx, widget, [:mask_channels]; obs = false)
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
  shelf = addshelf!(store, :mask, MaskData)

  # Derive entries from the parent channel view
  cctx = loadcontext(ctx, wctx[:parent])

  # TODO: Actually use mask_channels
  if isempty(wctx[:mask_channels])
    wctx[:mask_channels] = cctx[:channels]
  end

  wctx[:nchannels] = cctx[:nchannels]
  wctx[:nmasks] = cctx[:nchannels]
  
  for index in 1:wctx[:nchannels]
    wctx[index] = Dict{Symbol, Any}()
    wctx[index][:data] = cctx[index][:data]
    wctx[index][:axis] = cctx[index][:axis]
    wctx[index][:color] = cctx[index][:color]
    wctx[index][:crange] = cctx[index][:crange]
    wctx[index][:name] = cctx[index][:name]

    mask = Matrix{Bool}(undef, size(cctx[index][:data][]))
    mask .= false
    wctx[index][:mask] = Observable(mask)

    addvariable!(vars, "S$index", wctx[index][:mask])
  end

  wctx[:mouse_position] = cctx[:mouse_position]
  wctx[:focused] = cctx[:focused]

  update_store = prev -> begin
    if isnothing(prev) # :update is triggered instead of :change_from
      prev = store[:entry][]
    end
    if !haskey(shelf, prev.id)
      shelf[prev.id] = MaskData()
    end
    for index in 1:wctx[:nchannels]
      shelf[prev.id].masks[index] = copy(wctx[index][:mask][])
    end
  end

  load_next = next -> begin
    for index in 1:wctx[:nchannels]
      if haskey(shelf, next.id)
        wctx[index][:mask][] = shelf[next.id].masks[index]
      else
        sz = planesize(imagefile(next))
        mask = Matrix{Bool}(undef, sz)
        mask .= false
        wctx[index][:mask][] = mask
      end
    end
  end

  on(update_store, store[:update])
  on(update_store, store[:change_from])
  on(load_next, store[:change_to]; update = true)

  wctx[:pointer_on] = Observable(true)
  wctx[:mask_on] = Observable(true)
  wctx[:pen_on] = Observable(false)
  wctx[:segment_on] = Observable(false)
  wctx[:pen_size] = Observable(100)

  on(wctx[:pointer_on]) do pointer
    @info "Setting option :pointer_on in channel view widget to $pointer"
  end
  on(wctx[:mask_on]) do mask
    @info "Setting option :mask_on in channel view widget to $mask"
  end
  on(wctx[:pen_on]) do pen
    @info "Setting option :pen_on in channel view widget to $pen"
  end
  on(wctx[:segment_on]) do segment
    @info "Setting option :segment_on in channel view widget to $segment"
  end
  on(wctx[:pen_size]) do size
    @info "Setting option :pen_size in channel view widget to $size"
  end

  # Internal resolution reduction for certain mask operations
  # and visualizations for a more fluid experience
  wctx[:downscaling] = Observable(2)

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
    color = lift(complement, wctx[index][:color])
    colormap = lift(c -> [:transparent, (c, 0.3)], color)

    mask_sz = lift(Base.size, mask, ignore_equal_values = true)
    mask_scaled = lift(mask_sz, wctx[:downscaling]) do sz, scaling
      sz_scaled = div.(sz, scaling, RoundUp)
      ImageTransformations.imresize(mask[], sz_scaled)
    end

    onany(mask, wctx[:mask_on]) do data, visible
      if visible
        ImageTransformations.imresize!(mask_scaled[], data)
        notify(mask_scaled)
      end
    end

    Makie.image!(
      ax,
      lift(sz -> (0, sz[1]), mask_sz),
      lift(sz -> (0, sz[2]), mask_sz),
      mask_scaled;
      colormap = colormap,
      colorrange = (0, 1),
      visible = wctx[:mask_on],
    )
  end
  return
end

struct PenInteraction
  mask::Observable{Matrix{Bool}}
  wctx::Dict
  update_mask::Observable{Nothing}
end

function PenInteraction(mask, wctx)
  update_mask = Observable{Nothing}(nothing)
  on(Observables.throttle(0.05, update_mask)) do _
    notify(mask)
  end
  PenInteraction(mask, wctx, update_mask)
end

function Makie.process_interaction(pen::PenInteraction, event::MouseEvent, ax)
  mask = pen.mask[]

  r = round(Int, pen.wctx[:pen_size][] / 2.8)
  c = round.(Int, event.data)
  irange = max(c[1] - r, 1):min(c[1] + r, size(mask, 1))
  jrange = max(c[2] - r, 1):min(c[2] + r, size(mask, 2))

  left = [MouseEventTypes.leftdown, MouseEventTypes.leftdrag]
  right = [MouseEventTypes.rightdown, MouseEventTypes.rightdrag]

  if event.type in left
    for i in irange, j in jrange
      under_pen = (c[1] - i)^2 + (c[2] - j)^2 < r^2
      mask[i, j] = mask[i, j] || under_pen
    end
    notify(pen.update_mask)
  elseif event.type in right
    for i in irange, j in jrange
      under_pen = (c[1] - i)^2 + (c[2] - j)^2 < r^2
      mask[i, j] = mask[i, j] && !under_pen
    end
    notify(pen.update_mask)
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
  mask::Observable{Matrix{Bool}}
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
    if isempty(seg.seeds[])
      # This sometimes happens when you click / double click
      # on a single points
      return
    end
    seg.seeds[] = [seg.seeds[][1], event.data]
    seeds = map(seg.seeds[]) do seed
      return Tuple(round.(Int, seed))
    end

    index = seg.wctx[:focused][]
    data = seg.wctx[index][:data][]
    cmin, cmax = seg.wctx[index][:crange][]

    segment_task = Threads.@spawn begin
      scaling = seg.wctx[:downscaling][]
      sz_scaled = div.(size(data), scaling, RoundUp)
      data_scaled = ImageTransformations.imresize(data, sz_scaled)
      seeds_scaled = map(1:2, seeds, sz_scaled) do i, seed, sz
        coords = clamp.(div.(seed, scaling, RoundUp), 1, sz)
        CartesianIndex(coords) => i
      end
      segments = ImageSegmentation.seeded_region_growing(
        clamp.(data_scaled, cmin, cmax),
        seeds_scaled,
      )
      mask_scaled = ImageSegmentation.labels_map(segments) .== 1
      if scaling > 1
        ImageTransformations.imresize(mask_scaled, size(data)) .>= 0.5
      else
        mask_scaled
      end
    end

    begin
      seg.mask[] .|= fetch(segment_task)
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
      color = lift(complement, wctx[index][:color]),
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

  ca = RGBf(0.94, 0.94, 0.94)
  cb = Makie.COLOR_ACCENT[]
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
