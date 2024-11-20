

using GLMakie

function julia_main()::Cint

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

  project = Project("TEST", paths)

  widget_project = ProjectWidget("Project")
  addwidget!(project, :project, widget_project)

  widget_image = ImageSelectorWidget("Image")
  addwidget!(project, :image, widget_image)

  widget_view = ChannelViewWidget(
    "Channel View",
    provider = :image,
  )
  addwidget!(project, :view, widget_view)

  widget_mask = ChannelViewMaskWidget(
    "",
    provider = :view,
  )
  addwidget!(project, :mask, widget_mask)

  widget_segment = SegmentWidget(
    "Segments",
    provider = :view,
  )

  addwidget!(project, :segment, widget_segment)

  # project = SarahsCellSegmenter.loadproject("test")

  ctx = initcontext(project)

  fig = Figure(size = (1000, 800), backgroundcolor = :lightgray)

  layout_project = GridLayout(fig[1,1], alignmode = Outside(15))

  plotwidget(
    project.widgets[1][2],
    layout_project,
    ctx[:widgets][:project];
    theme,
    frame = true
  )

  layout_image = GridLayout(fig[1,2], alignmode = Outside(15))
  plotwidget(
    project.widgets[2][2],
    layout_image,
    ctx[:widgets][:image];
    theme,
    frame = true
  )

  layout_view_mask =  GridLayout(fig[2,1:2], 1, 2)
  colgap!(layout_view_mask, 1, 5)

  layout_view = GridLayout(
    layout_view_mask[1,1],
    alignmode = Outside(15)
  )
  plotwidget(
    project.widgets[3][2],
    layout_view,
    ctx[:widgets][:view];
    theme,
    frame = true
  )

  layout_mask = GridLayout(
    layout_view_mask[1,2],
    alignmode = Outside(5, 15, 0, 0),
    tellheight = false
  )

  plotwidget(
    project.widgets[4][2],
    layout_mask,
    ctx[:widgets][:mask];
    theme,
    frame = true,
    framepadding = 5,
  )

  screen = display(fig)
  wait(screen)

  return 0
end

