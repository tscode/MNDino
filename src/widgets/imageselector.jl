
# TODO: include variant selection here?
# Would require a variant shelf. This would be possible if either
# - variants are always very simple (string -> int mappings)
# - variants become storables. Then they cannot be anonymous anymore
"""
Widget for the graphical selection of images from the project repository.
"""
struct ImageSelectorWidget <: Widget
  title::String
  image_store::Symbol
end

function ImageSelectorWidget(title; image_store)
  return ImageSelectorWidget(title, image_store)
end

function initcontext(widget::ImageSelectorWidget, ctx)
  wctx = Dict{Union{Symbol, Int}, Any}()

  loadentries!(wctx, widget, [:image_store], obs = false)
  loadentries!(wctx, widget, [:title], obs = true)

  store = loadcontext(ctx, wctx[:image_store])

  wctx[:path] = store[:path]
  wctx[:image] = store[:image]
  wctx[:paths] = store[:paths]

  wctx[:active_index] = store[:active_index]
  wctx[:select_index] = store[:select_index]
  wctx[:select_prev] = store[:select_prev]
  wctx[:select_next] = store[:select_next]

  wctx[:last_index] = lift(length, store[:entries])

  wctx[:meta] = lift(metadata, wctx[:image])
  wctx[:nzlayers] = lift(nzlayers, wctx[:image])
  wctx[:nchannels] = lift(nchannels, wctx[:image])
  wctx[:resolution] = lift(m -> m.resolution, wctx[:meta])

  return wctx
end

gridlayoutoptions(::ImageSelectorWidget, wctx) = (size = (5, 2),)

function plotwidget(::ImageSelectorWidget, layout, wctx, theme)
  Label(
    layout[1, :],
    wctx[:title],
    font = :bold,
    fontsize = theme[:titlesize],
    halign = :left,
  )

  file_buttons_layout = GridLayout(layout[1, 2], 1, 3)
  colgap!(file_buttons_layout, 1, 5)

  prev_file_button = Button(
    file_buttons_layout[1, 1],
    label = "▲ Previous",
    tellwidth = false,
    halign = :right,
    fontsize = theme[:fontsize],
  )
  next_file_button = Button(
    file_buttons_layout[1, 2],
    label = "▼ Next",
    halign = :left,
    fontsize = theme[:fontsize],
  )
  Label(
    file_buttons_layout[1, 3],
    lift((i, n) -> "$i / $n", wctx[:active_index], wctx[:last_index]),
    fontsize = theme[:fontsize],
    color = :gray,
    halign = :right,
  )

  Label(
    layout[2, 1],
    "File:",
    fontsize = theme[:fontsize],
    halign = :right,
  )
  path_menu = Menu(
    layout[2, 2],
    options = lift(p -> basename.(p), wctx[:paths]),
    default = basename(wctx[:path][]),
    fontsize = theme[:fontsize],
  )

  Label(
    layout[3, 1],
    "Z-Layers:",
    fontsize = theme[:fontsize],
    halign = :right,
  )
  Label(
    layout[3, 2],
    lift(string, wctx[:nzlayers]),
    fontsize = theme[:fontsize],
    halign = :left,
    tellwidth = false,
  )

  Label(
    layout[4, 1],
    "Resolution:",
    fontsize = theme[:fontsize],
    halign = :right,
  )
  Label(
    layout[4, 2],
    lift(m -> string(m.resolution), wctx[:meta]),
    fontsize = theme[:fontsize],
    halign = :left,
    tellwidth = false,
  )

  Label(
    layout[5, 1],
    "Channels:",
    fontsize = theme[:fontsize],
    halign = :right,
  )
  Label(
    layout[5, 2],
    lift(string, wctx[:nchannels]),
    fontsize = theme[:fontsize],
    halign = :left,
    tellwidth = false,
  )

  on(prev_file_button.clicks) do _
    @async notify(wctx[:select_prev])
  end

  on(next_file_button.clicks) do _
    @async notify(wctx[:select_next])
  end

  on(path_menu.i_selected) do index
    if wctx[:select_index][] != index
      @async wctx[:select_index][] = index
    end
  end

  on(wctx[:select_index]) do index
    if path_menu.i_selected[] != index
      path_menu.i_selected[] = index
    end
  end

  # Switch images by clicking left / right on the keyboard
  on(Makie.events(layout[1,1]).keyboardbutton) do event
    event.action != Keyboard.press && return
    if event.key == Keyboard.left
      notify(prev_file_button.clicks)
    elseif event.key == Keyboard.right
      notify(next_file_button.clicks)
    end
  end

  return
end

