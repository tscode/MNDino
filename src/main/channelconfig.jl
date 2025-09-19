
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

function runchannelconfigurator(img::ImageFile, theme)
  fig = Figure(; size = (800, 500), backgroundcolor = :lightgray)
  channels = channelconfigurator(fig[1, 1], img::ImageFile, theme)
  mask_channels = segmentconfigurator(fig[2, 1], img::ImageFile, theme)

  continue_button = Button(
    fig[3, 1];
    label = "Create Project",
    font = :bold,
    halign = :right,
    tellwidth = false,
  )

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
    return channels
  end
end

function segmentconfigurator(pos, img, theme)
  layout = GridLayout(
    pos;
    default_rowgap = 6,
    default_colgap = 25,
    alignmode = Outside(15),
    valign = :top,
  )
  init_channels = channels(img)

  title_layout = GridLayout(layout[1, :], halign = :left, default_rowgap = 10, tellwidth = false)
  fname = basename(location(img))
  Label(
    title_layout[1, 1],
    "Segment Configuration";
    fontsize = 18,
    font = :bold,
    halign = :left,
    justification = :left,
  )
  Label(
    title_layout[2, 1],
    "This segment preset was extracted from '$fname'.\n\
    Adapt it to your needs before creating the project.";
    fontsize = 12,
    halign = :left,
    justification = :left,
    color = (:black, 0.7),
    tellwidth = false,
  )

  # rowgap!(layout, 1, Fixed(30))
  # rowgap!(layout, 2, Fixed(4))
  # rowgap!(layout, 3, Fixed(4))
  # rowsize!(layout, 4, Aspect(1.0, 1))

  plotwidgetframe(layout, theme)

  return
end

function channelconfigurator(pos, img::ImageFile, theme)
  init_channels = channels(img)
  layout = GridLayout(
    pos;
    default_rowgap = 6,
    default_colgap = 25,
    alignmode = Outside(15),
    valign = :top,
  )

  thumbnails = map(init_channels) do c
    zindex = zindexdefault(img)
    tindex = tindexdefault(img)
    data = imagedata(img, zindex, c.cindex, tindex)
    data = ImageTransformations.imresize(data, 256, 256)
    a, b = quantile(data, [0.001, 0.999])
    return clamp.(data, a, b)
  end

  names = map(c -> c.name, init_channels)
  colors = map(c -> c.color, init_channels)
  colors_default = copy(colors)
  order = collect(1:length(init_channels))
  update = Observable(nothing)

  for xindex in 1:length(init_channels)
    thumbnail = Observable(thumbnails[xindex])
    name = Observable(names[xindex])
    color = Observable(colors[xindex])
    cindex = Observable(xindex)

    Box(
      layout[2, xindex];
      strokevisible = false,
      color = lift(c -> 0.4c, color),
    )
    Label(
      layout[2, xindex],
      "C$xindex";
      fontsize = 13,
      font = :bold,
      tellwidth = false,
      halign = :center,
      color = RGB(0.98, 0.98, 0.98),
      padding = (0, 0, 5, 5),
    )
    Label(
      layout[2, xindex],
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
        layout[3, xindex];
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
    ax = Axis(layout[4, xindex]; aspect = DataAspect())
    image!(ax, thumbnail; colormap = lift(c -> [:black, c], color))

    Makie.hidedecorations!(ax)
    Makie.hidespines!(ax)
    Makie.deregister_interaction!(ax, :rectanglezoom)
    Makie.deregister_interaction!(ax, :dragpan)
    Makie.deregister_interaction!(ax, :scrollzoom)
    Makie.deregister_interaction!(ax, :limitreset)

    # Plot the color chooser
    picked_color = lift(identity, color)
    colorpicker(
      layout[5, xindex],
      picked_color,
      lift(i -> colors_default[i], cindex),
    )

    # Left / right buttons
    button_layout = GridLayout(layout[6, xindex], 1, 4; default_colgap = 5)
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

  title_layout = GridLayout(layout[1, :]; halign = :left, default_rowgap = 12)
  fname = basename(location(img))
  Label(
    title_layout[1, 1],
    "Channel Configuration";
    fontsize = 18,
    font = :bold,
    halign = :left,
    justification = :left,
  )
  Label(
    title_layout[2, 1],
    "This preset was extracted from '$fname'.\n\
    It will be applied to all images. \
    Adapt it to your needs before creating the project.";
    fontsize = 12,
    halign = :left,
    justification = :left,
    color = (:black, 0.7),
    tellwidth = false,
  )

  rowgap!(layout, 1, Fixed(30))
  rowsize!(layout, 4, Aspect(1.0, 1))

  plotwidgetframe(layout, theme)

  configured_channels = map(order) do index
    @assert index == init_channels[index].cindex
    return Channel(init_channels[index].cindex, names[index], colors[index])
  end

  return configured_channels
end
