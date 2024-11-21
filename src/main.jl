

using GLMakie

function main(; wait = false)

  paths = [
    "data/H2bub488_MDC1568_POLS5647_mnbody27_2024-11-01.ims",
    "data/h4k20me1488_MDC1568_POLS5647_mnbody50_2024-11-01.ims",
  ]

  theme = Dict(
    :widget_titlesize => 16,
    :widget_fontsize => 12,
    :widget_ticksize => 10,
    :widget_backgroundcolor => :white,
    :widget_framecolor => :gray,
    :widget_framepadding => 15,
    :widget_cornerradius => 6,
    :widget_rowgap => 7,
    :widget_colgap => 10,
    :color_button_down => Makie.COLOR_ACCENT[],
    :color_button_up => RGBf(0.94, 0.94, 0.94),
  )

  project = Project("TEST", paths, theme = theme)

  store = ImageStore(paths)

  widget_project = ProjectWidget("Project")
  widget_image = ImageSelectorWidget("Image", store_provider = :store)
  widget_view = ChannelViewWidget("Channel View", store_provider = :store)
  widget_mask = ChannelViewMaskWidget(parent = :view, store_provider = :store)
  # widget_segment = SegmentWidget(
  #   "Segments",
  #   provider = :view,
  # )

  addprovider!(project, :store, store)
  addprovider!(project, :project, widget_project)
  addprovider!(project, :image, widget_image)
  addprovider!(project, :view, widget_view)
  addprovider!(project, :mask, widget_mask)

  ctx = initcontext(project)

  fig = Figure(size = (1000, 800), backgroundcolor = :lightgray)

  layout_project = GridLayout(fig[1,1], alignmode = Outside(15))
  layout_image = GridLayout(fig[1,2], alignmode = Outside(15))
  layout_view_mask =  GridLayout(fig[2,1:2], 1, 2)

  colgap!(layout_view_mask, 1, 5)

  layout_view = GridLayout(
    layout_view_mask[1,1],
    alignmode = Outside(15)
  )

  layout_mask = GridLayout(
    layout_view_mask[1,2],
    alignmode = Outside(5, 15, 0, 0),
    tellheight = false
  )

  layouts = (
    :project => layout_project,
    :image => layout_image,
    :view => layout_view,
    :mask => layout_mask,
  )

  runproject(project, layouts; options = (:mask => (framepadding = 5,)))

  screen = display(fig)
  if wait
    Base.wait(screen)
  end

  return ctx
end

