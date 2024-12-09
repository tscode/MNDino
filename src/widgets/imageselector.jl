
"""
Widget for the graphical selection of images from the project repository.
"""
struct ImageSelectorWidget <: Widget
  title::String
  selected::Int
  image_store::Symbol
end

function ImageSelectorWidget(title; image_store, selected = 1)
  return ImageSelectorWidget(title, selected, image_store)
end

function initcontext(widget::ImageSelectorWidget, ctx)
  wctx = Dict{Union{Symbol, Int}, Any}()

  loadentries!(wctx, widget, [:image_store], obs = false)
  loadentries!(wctx, widget, [:title, :selected], obs = true)

  store = loadcontext(ctx, wctx[:image_store])

  wctx[:paths] = lift(entries -> location.(entries), store[:entries])
  wctx[:path] = lift(location, store[:entry])
  wctx[:image] = lift(imagefile, store[:entry])
  wctx[:nimages] = lift(length, store[:entries])

  wctx[:meta] = lift(wctx[:image]) do image
    map(1:nchannels(image)) do index
      metadata(image, index)
    end
  end

  wctx[:nzlayers] = lift(nzlayers, wctx[:image])
  wctx[:nchannels] = lift(nchannels, wctx[:image])
  wctx[:size] = lift(m -> m[1].size[1:2], wctx[:meta])

   # This should be modified to modify the current store entry
  wctx[:select] = store[:select]

  # This is done for letting the current image selection survive saving / loading
  onany(store[:entry], store[:entries]) do entry, entries
    index = findfirst(isequal(entry), entries)
    wctx[:selected][] = isnothing(index) ? 1 : index
  end
  
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
    lift((i, n) -> "$i / $n", wctx[:selected], wctx[:nimages]),
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
    options = wctx[:paths],
    default = wctx[:path][],
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
    lift(string, wctx[:size]),
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
    index = path_menu.i_selected[]
    if index > 1
      path_menu.i_selected[] = index - 1
    end
  end

  on(next_file_button.clicks) do _
    index = path_menu.i_selected[]
    if index < length(wctx[:paths][])
      path_menu.i_selected[] = index + 1
    end
  end

  on(path_menu.i_selected) do selected
    wctx[:select][] = selected
  end

  return
end

