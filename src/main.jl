
using GLMakie
using GLMakie.GLFW
using Makie: project_point2

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
    # TODO: What about packing colors in the theme?
    # :color_button_down => Makie.COLOR_ACCENT[],
    # :color_button_up => RGBf(0.94, 0.94, 0.94),
  )
end

function default_paths()
  return ["data/Cell_with_dye.jpg"]
end

function runproject(project::Project; wait = false, size = (1200, 1000), dryrun = false)
  fig = Figure(; size, backgroundcolor = :lightgray)

  layout_project = GridLayout(fig[1, 1]; alignmode = Outside(15), valign = :top)
  layout_image = GridLayout(fig[1, 2]; alignmode = Outside(15), valign = :top)
  layout_view_mask = GridLayout(fig[2, 1:2], 1, 2)

  colgap!(layout_view_mask, 1, 5)

  layout_view = GridLayout(layout_view_mask[1, 1]; alignmode = Outside(15))

  layout_mask = GridLayout(
    layout_view_mask[1, 2];
    alignmode = Outside(5, 10, 0, 0),
    tellheight = false,
  )

  layout_segments_analysis = GridLayout(fig[3, 1:2], 1, 2)

  layout_segments =
    GridLayout(layout_segments_analysis[1, 1]; alignmode = Outside(15))

  layout_analysis = GridLayout(
    layout_segments_analysis[1, 2];
    alignmode = Outside(15),
    valign = :top,
  )

  layouts = (
    :project => layout_project,
    :selector => layout_image,
    :view => layout_view,
    :mask => layout_mask,
    :segments => layout_segments,
    :analysis => layout_analysis,
  )

  ctx = initproject(project, layouts; options = (:mask => (framepadding = 5,)))

  if !dryrun
    version = pkgversion(MNDino)
    GLMakie.activate!(; title = "MNDino v$version")
    screen = Base.display(fig)
    if wait
      Base.wait(screen)
      @info "MNDino is shutting down..."
    end
  end

  return ctx
end

function filterlist()
  images = map([ImarisFile, CommonImageFile, OmeTiffFile]) do F
    exts = map(ext -> ext[2:end], extensions(F))
    return join(exts, ",")
  end
  images = join(images, ";")
  return "*;dino;$images"
end

function openproject(; dryrun = false)
  paths = NativeFileDialog.pick_multi_file(; filterlist = filterlist())
  if isempty(paths)
    @info "No files have been selected"
    return
  elseif length(paths) == 1 && splitext(paths[1])[2] == ".dino"
    project = loadproject(paths[1])
    merge!(project.theme, merge(default_theme(), project.theme))
    @info "Project file $(paths[1]) has been loaded"
  elseif all(p -> fitsextension(p, ImarisFile), paths)
    project = newproject(; paths, dryrun)
    @info "New project with $(length(paths)) Imaris files is being created"
  elseif all(p -> fitsextension(p, CommonImageFile), paths)
    @info "New project with $(length(paths)) image files is being created"
    project = newproject(; paths, dryrun)
  elseif all(p -> fitsextension(p, OmeTiffFile), paths)
    @info "New project with $(length(paths)) OMETIFF files is being created"
    project = newproject(; paths, dryrun)
  else
    @warn "Some of the provided files are not valid image files. Exiting"
    project = nothing
  end

  return project
end

function newproject(;
  name = "New Project",
  theme = default_theme(),
  paths = default_paths(),
  dryrun = false,
)

  if !dryrun
    path_example = first(paths)
    @info """
    Starting channel configurator based on image
      $path_example
    """
    channels = channelconfigurator(loadimagefile(path_example))
  else
    channels = []
  end

  if isnothing(channels)
    @info "Channel configuration aborted."
    return nothing
  end
  
  project = Project(name; theme = theme)

  addprovider!(project, :images) do
    return ImageStore(paths)
  end

  addprovider!(project, :variables) do
    return VariableStore()
  end

  addprovider!(project, :project) do
    return ProjectWidget("Project")
  end

  addprovider!(project, :selector) do
    return ImageSelectorWidget("Image"; image_store = :images)
  end

  addprovider!(project, :view) do
    return ChannelViewWidget(
      "Channels";
      image_store = :images,
      variable_store = :variables,
      channels = channels,
    )
  end

  addprovider!(project, :mask) do
    return ChannelViewMaskWidget(;
      parent = :view,
      image_store = :images,
      variable_store = :variables,
    )
  end

  addprovider!(project, :segments) do
    return SegmentsWidget("Segments"; segment_provider = :mask)
  end

  addprovider!(project, :analysis) do
    return AnalysisWidget(
      "Analysis";
      image_store = :images,
      variable_store = :variables,
    )
  end

  return project
end

function main(;
  pick_files = true,
  wait = true,
  size = (1200, 1000),
  dryrun = false,
  kwargs...,
)
  @info "Running MNDino main function"
  if pick_files
    @info "Opening project file selection..."
    project = openproject(; dryrun)
  else
    project = newproject(; dryrun, kwargs...)
  end
  if !isnothing(project)
    @info "Initializing and running project..."
    runproject(project; wait, size)
  else
    @info "Discarding project"
  end
  return
end

function colorpicker(pos, color, default)
  ax = Axis(
    pos,
    limits = ((-1, 271), (0, 1)),
    height = 15,
    spinewidth = 0.75,
  )
  Makie.hidedecorations!(ax)
  # Makie.hidespines!(ax)
  Makie.deregister_interaction!(ax, :rectanglezoom)
  Makie.deregister_interaction!(ax, :dragpan)
  Makie.deregister_interaction!(ax, :scrollzoom)
  Makie.deregister_interaction!(ax, :limitreset)

  colors = map(0:270) do hue
    RGB{Float32}(HSV(hue, 0.75, 1))
  end
  colors = reshape(colors, :, 1)
  image!(ax, colors)

  hovered_hue = Observable(NaN)
  selected_hue = map(c -> [HSV(c).h], color)
  vlines!(ax, selected_hue, color = :black, linewidth = 3)
  vlines!(ax, selected_hue, color = :white, linewidth = 0.75)
  vlines!(ax, hovered_hue, color = :black, linewidth = 1)

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

function channelconfigurator(img::ImageFile)
  fig = Figure(size = (800, 500))
  layout = GridLayout(fig[1,1], default_rowgap = 6, default_colgap = 25)
  init_channels = channels(img)
  thumbnails = map(init_channels) do c
    zindex = zindexdefault(img)
    tindex = tindexdefault(img)
    data = imagedata(img, zindex, c.cindex, tindex)
    data = ImageTransformations.imresize(data, 256, 256)
    a, b = quantile(data, [0.001, 0.999])
    clamp.(data, a, b)
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
      layout[2, xindex],
      strokevisible = false,
      color = lift(c -> 0.4c, color),
    )
    Label(
      layout[2, xindex],
      "C$xindex",
      fontsize = 13,
      font = :bold,
      tellwidth = false,
      halign = :center,
      color = RGB(0.98, 0.98, 0.98),
      padding = (0, 0, 5, 5)
    )
    Label(
      layout[2, xindex],
      lift(c -> "c-index $c", cindex),
      fontsize = 12,
      tellwidth = false,
      halign = :right,
      color = RGBA(1, 1, 1, 0.8),
      padding = (0, 7, 5, 5),
    )

    # Name of the channel
    make_namebox = str -> Textbox(
      layout[3, xindex],
      stored_string = str,
      font = :bold,
      fontsize = 13,
      halign = :center,
      bordercolor = :transparent,
      textpadding = (3, 3, 3, 3),
      cornerradius = 0,
      tellwidth = false,
    )
    namebox = make_namebox(name)
    
    # Plot the thumbnail
    ax = Axis(layout[4, xindex], aspect = DataAspect())
    hidedecorations!(ax)
    hidespines!(ax)
    image!(ax, thumbnail, colormap = lift(c -> [:black, c], color))

    # Plot the color chooser
    picked_color = lift(identity, color)
    colorpicker(
      layout[5, xindex],
      picked_color,
      lift(i -> colors_default[i], cindex),
    )

    # Left / right buttons
    button_layout = GridLayout(layout[6, xindex], 1, 4, default_colgap = 5)
    button_left = Button(button_layout[1, 2], label = "◀", width = 40)
    button_right = Button(button_layout[1, 3], label = "▶", width = 40)

    # Map interactions to changes in names, colors, and order
    on(update) do _
      cindex[] = order[xindex]
      thumbnail[] = thumbnails[cindex[]]
      name[] = names[cindex[]]
      color[] = colors[cindex[]]
    end

    on(button_left.clicks) do _
      if !(xindex == 1)
        order[xindex-1:xindex] = order[[xindex, xindex-1]]
        notify(update)
      end
    end

    on(button_right.clicks) do _
      if !(xindex == length(order))
        order[xindex:xindex+1] = order[[xindex+1, xindex]]
        notify(update)
      end
    end

    on(picked_color) do c
      if !(c  == color[])
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

  Label(layout[1, :], "Channel Configuration", fontsize = 18, font = :bold)
  continue_button = Button(layout[1, :], label = "Continue", font = :bold, halign = :right)

  rowgap!(layout, 1, Fixed(30))
  rowgap!(layout, 2, Fixed(4))
  rowgap!(layout, 3, Fixed(4))
  rowsize!(layout, 4, Aspect(1.0, 1))

  screen = Base.display(fig)
  window = Makie.to_native(screen)

  abort = true
  on(continue_button.clicks) do _
    abort = false
    GLFW.SetWindowShouldClose(window, true)
  end
  
  Base.wait(screen)

  if abort
    return nothing
  else
    return map(order) do index
      @assert index == init_channels[index].cindex
      return Channel(
        init_channels[index].cindex,
        names[index],
        colors[index],
      )
    end
  end
end

function export_analysis(project::Project, output::String; script = nothing)
  if isnothing(script)
    path = project.providers[:analysis].script_path
    if isempty(path)
      @info """
      The given project has no associated script. \
      Please select a valid script file.
      """
      path = NativeFileDialog.pick_file()
      isempty(path) && error("No script file has been selected")
    end
    script = DinoScript(path)
  end
  names, data = runscript(
    script,
    project;
    image_store = :images,
    variable_store = :variables,
    variables = [:zindex],
  )
  open(output, "w") do io
    @info "Writing results to $output"
    println(io, join(names, ","))
    return writedlm(io, data, ',')
  end
end

function export_analysis(; script = nothing)
  @info "Select the project file to be analysed..."
  path = NativeFileDialog.pick_file(; filterlist = "dino;*")
  @info "Select analysis export file..."
  output = NativeFileDialog.save_file(; filterlist = "csv")
  if isnothing(path)
    @info "No file selected."
  else
    project = loadproject(path)
    export_analysis(project, output; script)
  end
end

