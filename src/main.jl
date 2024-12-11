

using GLMakie

function default_theme()
  return Dict(
    :titlesize => 16,
    :fontsize => 12,
    :ticksize => 10,
    :backgroundcolor => :white,
    :framecolor => :gray,
    :framepadding => 15,
    :cornerradius => 6,
    :rowgap => 7,
    :colgap => 10,
    :color_button_down => Makie.COLOR_ACCENT[],
    :color_button_up => RGBf(0.94, 0.94, 0.94),
  )
end

function default_paths()
  return [
    "data/H2bub488_MDC1568_POLS5647_mnbody27_2024-11-01.ims",
    "data/h4k20me1488_MDC1568_POLS5647_mnbody50_2024-11-01.ims",
  ]
end

function runproject(project :: Project; wait = false)
  fig = Figure(
    size = (1200, 800),
    backgroundcolor = :lightgray,
  )

  layout_project = GridLayout(fig[1,1], alignmode = Outside(15), valign = :top)
  layout_image = GridLayout(fig[1,2], alignmode = Outside(15), valign = :top)
  layout_view_mask =  GridLayout(fig[2,1:2], 1, 2)

  colgap!(layout_view_mask, 1, 5)

  layout_view = GridLayout(
    layout_view_mask[1,1],
    alignmode = Outside(15)
  )

  layout_mask = GridLayout(
    layout_view_mask[1,2],
    alignmode = Outside(5, 10, 0, 0),
    tellheight = false
  )

  layout_segments_analysis = GridLayout(fig[3, 1:2], 1, 2)

  layout_segments = GridLayout(
    layout_segments_analysis[1,1],
    alignmode = Outside(15)
  )

  layout_analysis = GridLayout(
    layout_segments_analysis[1,2],
    alignmode = Outside(15),
    valign = :top,
  )

  # rowgap!(fig.layout, 1, 110)
  # rowgap!(fig.layout, 2, 110)

  layouts = (
    :project => layout_project,
    :selector => layout_image,
    :view => layout_view,
    :mask => layout_mask,
    :segments => layout_segments,
    :analysis => layout_analysis,
  )

  ctx = initproject(
    project,
    layouts;
    options = (:mask => (framepadding = 5,))
  )

  version = pkgversion(MNDino)
  GLMakie.activate!(title = "MNDino v$version")
  screen = display(fig)
  if wait
    Base.wait(screen)
  end

  return ctx
end

function welcome()
  filterlist = "ims;dino"
  paths = NativeFileDialog.pick_multi_file(; filterlist)
  if isempty(paths)
    @info "No files have been selected"
    return
  elseif length(paths) == 1 && splitext(paths[1])[2] == ".dino"
    project = loadproject(paths[1])
    @info "Project file $(paths[1]) has been loaded"
  elseif all(p -> splitext(p)[2] == ".ims", paths)
    project = newproject(; paths)
    @info "New project with $(length(paths)) paths has been created"
  else
    project = nothing
    @warn "Some of the provided files are not valid image files. Exiting"
  end

  return project
end

function newproject(;
  name = "MNDino Project",
  theme = default_theme(),
  paths = default_paths(),
)

  project = Project(name, paths, theme = theme)

  addprovider!(project, :images) do 
    ImageStore(paths)
  end

  addprovider!(project, :variables) do 
    VariableStore()
  end

  addprovider!(project, :project) do 
    ProjectWidget("Project")
  end

  addprovider!(project, :selector) do 
    ImageSelectorWidget("Image", image_store = :images)
  end

  addprovider!(project, :view) do
    ChannelViewWidget(
      "Channel View",
      image_store = :images,
      variable_store = :variables
    )
  end

  addprovider!(project, :mask) do
    ChannelViewMaskWidget(
      parent = :view,
      image_store = :images,
      variable_store = :variables,
    )
  end

  addprovider!(project, :segments) do
    SegmentsWidget(
      "Segments",
      segment_provider = :mask,
    )
  end

  addprovider!(project, :analysis) do
    AnalysisWidget(
      "Analysis",
      image_store = :images,
      variable_store = :variables,
    )
  end

  return project
end

function main(; show_welcome = false, wait = true, kwargs...)
  if show_welcome
    project = welcome()
  else
    project = newproject(; kwargs...)
  end
  if !isnothing(project)
    runproject(project; wait)
  end
  return
end

