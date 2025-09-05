
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

  wctx[:store] = store
  wctx[:path] = store[:path]
  wctx[:image] = store[:image]
  wctx[:paths] = store[:paths]
  wctx[:loading] = store[:loading]

  wctx[:active_index] = store[:active_index]
  wctx[:select_index] = store[:select_index]
  wctx[:select_prev] = store[:select_prev]
  wctx[:select_next] = store[:select_next]
  wctx[:last_index] = store[:last_index]

  return wctx
end

gridlayoutoptions(::ImageSelectorWidget, wctx) = (size = (5, 2),)


function _imageselector_topline(layout, yindex, wctx, theme)
  layout = GridLayout(layout[yindex, :])

  Label(
    layout[1, 1],
    wctx[:title],
    font = :bold,
    fontsize = theme[:titlesize],
    halign = :left,
  )

  # TODO: This currently does not work. The label is not changed
  # until the full view is updated.
  # How can I change this?
  text = lift(wctx[:loading]) do loading
    loading ? "Loading..." : " "
  end

  Label(
    layout[1, 2],
    text,
    fontsize = theme[:fontsize],
    halign = :center,
    color = :darkgreen,
    width = 50,
  )

  file_buttons_layout = GridLayout(layout[1, 3], 1, 3)
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

  on(prev_file_button.clicks) do _
    notify(wctx[:select_prev])
  end

  on(next_file_button.clicks) do _
    notify(wctx[:select_next])
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

function _imageselector_image(layout, yindex, wctx, theme)
  layout = GridLayout(layout[yindex, :], default_colgap = 5)

  path = wctx[:path][]
  if isnothing(path)
    default = nothing
  else
    default = "$(wctx[:active_index][]). " * basename(path)
  end

  path_menu = Menu(
    layout[1, 1],
    options = lift(wctx[:paths]) do paths
      map(ip -> "$(ip[1]). " * basename.(ip[2]), enumerate(paths))
    end,
    default = default,
    fontsize = theme[:fontsize],
    prompt = "Select image file..."
  )

  del_button = Button(
    layout[1, 2],
    label = "➖",
    fontsize = theme[:fontsize],
    font = :bold,
  )
  add_button = Button(
    layout[1, 3],
    label = "➕ Add...",
    fontsize = theme[:fontsize],
    font = :bold,
  )

  on(path_menu.i_selected) do index
    if wctx[:select_index][] != index
      wctx[:select_index][] = index
    end
  end

  on(wctx[:select_index]) do index
    if path_menu.i_selected[] != index
      path_menu.i_selected[] = max(index, 0)
    end
  end

  on(del_button.clicks) do _
    index = wctx[:active_index][]
    paths = isnothing(wctx[:path][]) ? [] : [wctx[:path][]]
    @info "Deleting $(length(paths)) images from project: $paths"

    wctx[:loading][] = true
    rmimages!(wctx[:store], paths)
    # Set the index to next image
    last_index = wctx[:last_index][]
    if index < last_index
      wctx[:select_index][] = index
    elseif last_index > 0
      wctx[:select_index][] = last_index
    end
    wctx[:loading][] = false
  end

  on(add_button.clicks) do _
    list = extensionstring(grouped = false)
    list = list * ";" * extensionstring(grouped = true)
    paths = NativeFileDialog.pick_multi_file(; filterlist = list)
    # TODO: Check channel compatibility!
    @info "Adding $(length(paths)) images to project: $paths"
    addimages!(wctx[:store], paths)
  end

  return
end

function plotwidget(::ImageSelectorWidget, layout, wctx, theme)
  _imageselector_topline(layout, 1, wctx, theme)
  _imageselector_image(layout, 2, wctx, theme)

  Label(
    layout[3, 1],
    "Resolution:",
    fontsize = theme[:fontsize],
    halign = :right,
  )

  Label(
    layout[3, 2],
    lift(wctx[:image]) do img
      isnothing(img) ? "-" : string(planesize(img)) # todo: variant!
    end,
    fontsize = theme[:fontsize],
    halign = :left,
    tellwidth = false,
  )

  Label(
    layout[4, 1],
    "Z-Layers:",
    fontsize = theme[:fontsize],
    halign = :right,
  )
  Label(
    layout[4, 2],
    lift(wctx[:image]) do img
      isnothing(img) ? "-" : string(nzlayers(img))
    end,
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
    lift(wctx[:image]) do img
      isnothing(img) ? "-" : string(nchannels(img))
    end,
    fontsize = theme[:fontsize],
    halign = :left,
    tellwidth = false,
  )

  return
end

