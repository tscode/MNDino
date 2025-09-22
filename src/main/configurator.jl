
#
# Found this function here:
# https://discourse.julialang.org/t/trying-to-clear-a-layout-but-getting-stuck-at-nested-gridlayouts/123269/4
# 
function clear_layout!(layout::GridLayout)
  # Begin by removing the blocks from the recursive GridLayout structure
  items_to_remove = []
  for block in Makie.contents(layout)
    if typeof(block) == GridLayout
      clear_layout!(block)
    else
      push!(items_to_remove, block)
    end
  end
  foreach(delete!, items_to_remove)

  # Now remove the GridLayout substructure
  items_to_remove = []
  for wrapper in layout.content
    push!(items_to_remove, wrapper)
  end
  foreach(GridLayoutBase.remove_from_gridlayout!, items_to_remove)

  # Finally, trim so that the layout is 1 by 1.
  return Makie.trim!(layout)
end

# TODO: Make this a nice block, maybe suggest it for Makie?
function colorpicker(pos, color, default)
  ax = Axis(pos; limits = ((-1, 271), (0, 1)), height = 15, spinewidth = 0.75)
  Makie.hidedecorations!(ax)
  # Makie.hidespines!(ax)
  Makie.deregister_interaction!(ax, :rectanglezoom)
  Makie.deregister_interaction!(ax, :dragpan)
  Makie.deregister_interaction!(ax, :scrollzoom)
  Makie.deregister_interaction!(ax, :limitreset)

  colors = map(0:270) do hue
    return RGB{Float32}(HSV(hue, 0.75, 1))
  end
  colors = reshape(colors, :, 1)
  image!(ax, colors)

  hovered_hue = Observable(NaN)
  selected_hue = map(c -> [HSV(c).h], color)
  vlines!(ax, selected_hue; color = :black, linewidth = 3)
  vlines!(ax, selected_hue; color = :white, linewidth = 0.75)
  vlines!(ax, hovered_hue; color = :black, linewidth = 1)

  register_interaction!(ax, :color) do event::MouseEvent, ax
    if event.type == MouseEventTypes.over
      hovered_hue[] = event.data[1]
    elseif event.type == MouseEventTypes.out
      hovered_hue[] = NaN
    elseif event.type == MouseEventTypes.leftclick
      color[] = HSV(event.data[1], 1, 1)
    elseif event.type == MouseEventTypes.leftdoubleclick
      color[] = default[]
    end
  end
end

function runconfigurator(img::ImageFile, theme)
  fig = Figure(; size = (800, 500), backgroundcolor = :lightgray)

  Label(
    fig[1, 1],
    "Project Configuration",
    fontsize = 20,
    font = :bold,
    halign = :center,
    tellwidth = false,
    padding = 10,
  )

  channels = channelconfigurator(fig, fig[2, 1], img::ImageFile, theme)
  segments = segmentconfigurator(fig, fig[3, 1], img::ImageFile, theme)

  continue_button = Button(
    fig[4, 1];
    label = "Create Project",
    fontsize = 14,
    font = :bold,
    halign = :center,
    padding = (16, 16, 16, 16),
    tellwidth = false,
  )

  Box(fig[4, 1], color = :transparent, strokecolor = :transparent)

  rowgap!(fig.layout, 1, 24)


  screen = Base.display(fig)
  window = Makie.to_native(screen)

  abort = true
  on(continue_button.clicks) do _
    abort = false
    return GLFW.SetWindowShouldClose(window, true)
  end

  Base.wait(screen)

  if abort
    return nothing
  else
    return (; channels, segments)
  end
end

function segmentconfigurator(fig, pos, img, theme)
  layout = GridLayout(
    pos;
    default_rowgap = 20,
    default_colgap = 25,
    alignmode = Outside(15),
    valign = :top,
  )
  title_layout = GridLayout(
    layout[1, :];
    halign = :left,
    default_rowgap = 6,
    tellwidth = false,
  )
  body_layout = GridLayout(
    layout[2, :];
    halign = :left,
    default_rowgap = 6,
    default_colgap = 25,
  )

  segment_channels = channels(img)
  fname = basename(location(img))

  Label(
    title_layout[1, 1],
    "Segments";
    fontsize = 18,
    font = :bold,
    halign = :left,
    justification = :left,
    tellwidth = false,
  )
  Label(
    title_layout[2, 1],
    "Adapt the number, name, and color of available segments.";
    fontsize = 12,
    halign = :left,
    justification = :left,
    color = (:black, 0.7),
    tellwidth = false,
  )
  button_add = Button(
    title_layout[:, 2];
    label = "➕",
    fontsize = 14,
    width = 40,
    font = :bold,
    buttoncolor = :transparent,
  )
  button_del = Button(
    title_layout[:, 3];
    label = "➖",
    fontsize = 14,
    width = 40,
    font = :bold,
    buttoncolor = :transparent,
  )

  colgap!(title_layout, 2, 6)

  nsegments = Observable(length(segment_channels))

  on(button_add.clicks) do _
    return nsegments[] += 1
  end

  on(button_del.clicks) do _
    if nsegments[] > 1
      nsegments[] -= 1
    end
  end

  # Collect all observer functions, since we will have to
  # dynamically create or remove them when the number of segments changes
  obsfs = []

  on(nsegments; update = true) do nsegs
    foreach(off, obsfs)
    clear_layout!(body_layout)

    # Update segment_channels. If more channels are required,
    # initialize them with a random color. If fewer channels are required,
    # just resize the vector
    n = length(segment_channels)
    if n > nsegs
      resize!(segment_channels, nsegs)
    elseif n < nsegs
      for index in (n + 1):nsegs
        color = HSV(rand() * 270, 1, 1)
        push!(segment_channels, Channel(-1, "Segment $index", color))
      end
    end

    for mid in 1:nsegs
      name = Observable(segment_channels[mid].name)
      color = Observable(segment_channels[mid].color)

      Box(
        body_layout[1, mid];
        strokevisible = false,
        color = lift(c -> 0.4c, color),
      )
      Label(
        body_layout[1, mid],
        "S$mid";
        fontsize = 13,
        font = :bold,
        tellwidth = false,
        halign = :center,
        color = RGB(0.98, 0.98, 0.98),
        padding = (0, 0, 5, 5),
      )

      Textbox(
        body_layout[2, mid];
        stored_string = name,
        font = :bold,
        fontsize = 13,
        halign = :center,
        bordercolor = :gray,
        textpadding = (10, 10, 3, 3),
        cornerradius = 0,
        tellwidth = false,
      )
      colorpicker(body_layout[3, mid], color, Observable(color[]))

      f = onany(name, color) do name, color
        sc = segment_channels[mid]
        segment_channels[mid] = Channel(sc.cindex, name, color)
        return
      end
      append!(obsfs, f)
    end

    return
  end

  plotwidgetframe(layout, theme)

  return segment_channels
end

function channelconfigurator(fig, pos, img::ImageFile, theme)
  image_channels = channels(img)
  layout = GridLayout(
    pos;
    default_rowgap = 20,
    default_colgap = 25,
    alignmode = Outside(15),
  )
  title_layout = GridLayout(
    layout[1, :];
    halign = :left,
    default_rowgap = 6,
    tellwidth = false,
  )
  body_layout = GridLayout(
    layout[2, :];
    haling = :left,
    default_rowgap = 6,
    default_colgap = 25,
  )

  fname = basename(location(img))
  Label(
    title_layout[1, 1],
    "Channels";
    fontsize = 18,
    font = :bold,
    halign = :left,
    justification = :left,
  )
  Label(
    title_layout[2, 1],
    "Adapt the name, color, and order of the image channels.";
    fontsize = 12,
    halign = :left,
    justification = :left,
    color = (:black, 0.7),
    tellwidth = false,
  )

  thumbnails = map(image_channels) do c
    zindex = zindexdefault(img)
    tindex = tindexdefault(img)
    data = imagedata(img, zindex, c.cindex, tindex)
    sz = size(data)
    width = 256
    height = ceil(Int, width / sz[1] * sz[2])
    data = ImageTransformations.imresize(data, (width, height))
    a, b = quantile(data, [0.001, 0.999])
    return clamp.(data, a, b)
  end

  names = map(c -> c.name, image_channels)
  colors = map(c -> c.color, image_channels)
  colors_default = copy(colors)
  order = collect(1:length(image_channels))
  update = Observable(nothing)

  # We use one of the color boxes for column-width information to sidestep a Makie layouting bug (see below)
  box = nothing

  for xindex in 1:length(image_channels)
    thumbnail = Observable(thumbnails[xindex])
    name = Observable(names[xindex])
    color = Observable(colors[xindex])
    cindex = Observable(xindex)

    # We use this variable to 
    box = Box(
      body_layout[1, xindex];
      strokevisible = false,
      color = lift(c -> 0.4c, color),
    )
    Label(
      body_layout[1, xindex],
      "C$xindex";
      fontsize = 13,
      font = :bold,
      tellwidth = false,
      halign = :center,
      color = RGB(0.98, 0.98, 0.98),
      padding = (0, 0, 5, 5),
    )
    Label(
      body_layout[1, xindex],
      lift(c -> "c-index $c", cindex);
      fontsize = 12,
      tellwidth = false,
      halign = :right,
      color = RGBA(1, 1, 1, 0.8),
      padding = (0, 7, 5, 5),
    )

    # Name of the channel
    make_namebox =
      str -> Textbox(
        body_layout[2, xindex];
        stored_string = str,
        font = :bold,
        fontsize = 13,
        halign = :center,
        bordercolor = :gray,
        textpadding = (10, 10, 3, 3),
        cornerradius = 0,
        tellwidth = false,
      )
    namebox = make_namebox(name)

    # Plot the thumbnail
    ax = Axis(body_layout[3, xindex]; aspect = DataAspect())
    Makie.image!(ax, thumbnail; colormap = lift(c -> [:black, c], color))

    Makie.hidedecorations!(ax)
    Makie.hidespines!(ax)
    Makie.deregister_interaction!(ax, :rectanglezoom)
    Makie.deregister_interaction!(ax, :dragpan)
    Makie.deregister_interaction!(ax, :scrollzoom)
    Makie.deregister_interaction!(ax, :limitreset)

    # Plot the color chooser
    picked_color = lift(identity, color)
    colorpicker(
      body_layout[4, xindex],
      picked_color,
      lift(i -> colors_default[i], cindex),
    )

    # Left / right buttons
    button_layout = GridLayout(body_layout[5, xindex], 1, 4; default_colgap = 5)
    button_left = Button(
      button_layout[1, 2];
      label = "◀",
      width = 40,
      buttoncolor = :transparent,
    )
    button_right = Button(
      button_layout[1, 3];
      label = "▶",
      width = 40,
      buttoncolor = :transparent,
    )

    # Map interactions to changes in names, colors, and order
    on(update) do _
      cindex[] = order[xindex]
      thumbnail[] = thumbnails[cindex[]]
      name[] = names[cindex[]]
      return color[] = colors[cindex[]]
    end

    on(button_left.clicks) do _
      if !(xindex == 1)
        order[(xindex - 1):xindex] = order[[xindex, xindex - 1]]
        notify(update)
      end
    end

    on(button_right.clicks) do _
      if !(xindex == length(order))
        order[xindex:(xindex + 1)] = order[[xindex + 1, xindex]]
        notify(update)
      end
    end

    on(picked_color) do c
      if !(c == color[])
        colors[cindex[]] = c
        notify(update)
      end
    end

    on(name) do str
      delete!(namebox)
      namebox = make_namebox(str)
      on(namebox.stored_string) do str
        if !(str == name[])
          println("Updated name to $str")
          names[cindex[]] = str
          notify(update)
        end
      end
    end
  end

  # For some reason, setting the Aspect here would not work.
  # Makie then makes body_layout larger than layout, and the buttons are outside of the widget-box
  # 
  # rowsize!(body_layout, 3, Aspect(1, 1.0))
  # 
  # Instead, we manually set the size...
  on(fig.scene.viewport, update = true, priority = -100) do _
    sz = planesize(img)
    aspect = sz[1] / sz[2]
    bbox = box.layoutobservables.computedbbox[]
    rowsize!(body_layout, 3, bbox.widths[1] / aspect)
  end

  plotwidgetframe(layout, theme)

  configured_channels = map(order) do index
    @assert index == image_channels[index].cindex
    return Channel(image_channels[index].cindex, names[index], colors[index])
  end

  return configured_channels
end
