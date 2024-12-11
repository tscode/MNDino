
struct ProjectWidget <: Widget
  title::String
  path::String
end

function ProjectWidget(title; path = "")
  return ProjectWidget(title, path)
end

function initcontext(widget::ProjectWidget, ctx)
  wctx = Dict{Symbol, Any}()

  wctx[:ctx] = ctx # required for saving the whole project
  loadentries!(wctx, ctx, [:name, :comment, :nimages, :update])
  loadentries!(wctx, widget, obs = true)

  return wctx
end

gridlayoutoptions(::ProjectWidget, wctx) = (size = (5, 2),)

function plotwidget(::ProjectWidget, layout, wctx, theme)
  rowgap!(layout, 2, 10)

  toplayout = GridLayout(layout[1, :], 1, 4)
  colgap!(toplayout, 1, 5)

  Label(
    toplayout[1, 1],
    lift(t -> "$t:", wctx[:title]),
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
  )

  save_button = Button(
    toplayout[1, 4],
    label = "Save...",
    halign = :right,
    fontsize = theme[:fontsize],
    font = :bold,
  )

  Label(
    layout[2, :],
    lift(n -> "Project with $n image files", wctx[:nimages]),
    fontsize = theme[:fontsize],
    halign = :left,
    color = (:black, 0.7),
  )
  
  Label(
    layout[3, 1],
    "Path:",
    fontsize = theme[:fontsize],
    halign = :right,
  )
  path = lift(wctx[:path]) do path
    length(path) > 75 ? "..." * path[end-75:end] : path
  end
  path_label = Label(
    layout[3, 2],
    isempty(path[]) ? "<unsaved>" : path[],
    fontsize = theme[:fontsize],
    halign = :left,
  )

  Label(
    layout[4, 1],
    "Comment:",
    fontsize = theme[:fontsize],
    halign = :right,
  )
  comment_box = Textbox(
    layout[4, 2],
    stored_string = isempty(wctx[:comment][]) ? nothing : wctx[:comment][],
    fontsize = theme[:fontsize],
    halign = :right,
    reset_on_defocus = true,
    placeholder = " ",
    width = 400,
  )

  on(project_name.stored_string) do str
    wctx[:name][] = isnothing(str) ? "" : str
  end

  on(save_button.clicks) do _
    @async begin
      path = NativeFileDialog.save_file(filterlist="dino")
      old_path = wctx[:path][]
      wctx[:path][] = path
      notify(wctx[:update])
      ctx = wctx[:ctx]
      project = updateproject(ctx[:project], wctx[:ctx])
      try
        saveproject(project, path)
      catch err
        @error err
        path_label.text[] = "Saving failed"
        path_label.color = :darkred
        wctx[:path][] = old_path
        return
      end
      path_label.text[] = path
      path_label.color = :black
    end
    return
  end

  on(comment_box.stored_string) do comment
    wctx[:comment][] = comment
  end
end
