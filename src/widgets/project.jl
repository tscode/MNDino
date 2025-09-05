
struct ProjectWidget <: Widget
  title::String
  path::String
end

ProjectWidget(title; path = "") = ProjectWidget(title, path)

function initcontext(widget::ProjectWidget, ctx)
  wctx = Dict{Symbol, Any}()

  wctx[:ctx] = ctx # required for saving the whole project
  loadentries!(wctx, ctx, [:name, :comment, :update, :version, :date])
  loadentries!(wctx, widget; obs = true)

  return wctx
end

gridlayoutoptions(::ProjectWidget, wctx) = (size = (5, 2),)

function plotwidget(::ProjectWidget, layout, wctx, theme)
  rowgap!(layout, 2, 10)

  toplayout = GridLayout(layout[1, :], 1, 5)
  colgap!(toplayout, 1, 5)
  colgap!(toplayout, 4, 5)

  Label(
    toplayout[1, 1],
    lift(t -> "$t:", wctx[:title]);
    font = :bold,
    fontsize = theme[:titlesize],
    halign = :left,
    tellwidth = true,
  )

  project_name = Textbox(
    toplayout[1, 2];
    placeholder = "project name",
    stored_string = wctx[:name][],
    font = :bold,
    fontsize = theme[:titlesize],
    halign = :left,
    bordercolor = :transparent,
    cornerradius = 0,
    textpadding = (5, 5, 5, 5),
  )

  save_label = Label(
    toplayout[1, 3],
    " ";
    halign = :right,
    fontsize = theme[:fontsize],
    tellwidth = false,
  )

  save_button = Button(
    toplayout[1, 4];
    label = "Save",
    halign = :right,
    fontsize = theme[:fontsize],
    font = :bold,
  )

  saveas_button = Button(
    toplayout[1, 5];
    label = "Save as...",
    halign = :right,
    fontsize = theme[:fontsize],
    font = :bold,
  )

  Label(
    layout[2, :],
    "Created at $(wctx[:date]) ($(wctx[:version]))",
    fontsize = theme[:fontsize],
    halign = :left,
    color = (:black, 0.7),
  )

  Label(layout[3, 1], "Path:"; fontsize = theme[:fontsize], halign = :right)
 
  path_str = lift(wctx[:path]) do path
    if isempty(path)
      return "<unsaved>"
    else
      return length(path) > 75 ? "..." * path[(end - 75):end] : path
    end
  end

  path_label = Label(
    layout[3, 2],
    path_str;
    fontsize = theme[:fontsize],
    halign = :left,
  )

  Label(layout[4, 1], "Comment:"; fontsize = theme[:fontsize], halign = :right)

  comment_box = Textbox(
    layout[4, 2];
    stored_string = isempty(wctx[:comment][]) ? nothing : wctx[:comment][],
    fontsize = theme[:fontsize],
    halign = :right,
    reset_on_defocus = true,
    placeholder = " ",
    width = 400,
  )

  on(project_name.stored_string) do str
    return wctx[:name][] = isnothing(str) ? "" : str
  end

  path = Ref(wctx[:path][])

  on(save_button.clicks) do _
    if isempty(path[])
      @warn "Saving aborted: No file selected"
      fadelabel(save_label, "No file selected", colorant"darkgray")
      return
    end
    try
      notify(wctx[:update])
      wctx[:path][] = path[]
      project = updateproject(wctx[:ctx][:project], wctx[:ctx])
      saveproject(project, path[])
      fadelabel(save_label, "Project saved", colorant"darkgreen")
      @info "Project saved as $(path[])"
    catch err
      wctx[:path][] = ""
      if err isa Base.IOError
        @warn "Saving failed: Cannot write to file"
        fadelabel(save_label, "Cannot write to file", colorant"darkred")
      else
        @warn "Saving failed: $err"
        fadelabel(save_label, "Saving failed", colorant"darkred")
      end
    end
  end

  on(saveas_button.clicks) do _
    @async begin
      path[] = NativeFileDialog.save_file(; filterlist = "dino")
      notify(save_button.clicks)
    end
    return
  end

  on(comment_box.stored_string) do comment
    return wctx[:comment][] = comment
  end

  # Save by clicking ctrl+s
  events = Makie.events(layout[1,1])
  on(events.keyboardbutton) do event
    event.action != Keyboard.press && return

    scene = Makie.get_scene(layout[1, 1])
    lctrl = Keyboard.left_control
    rctrl = Keyboard.right_control

    if event.key == Keyboard.s &&
      (ispressed(scene, lctrl) || ispressed(scene, rctrl))
      if path[] == ""
        notify(saveas_button.clicks)
      else
        notify(save_button.clicks)
      end
    end
  end
end
