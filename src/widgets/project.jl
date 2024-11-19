
struct ProjectWidget <: Widget
  title::String
  path::String
end

function ProjectWidget(title; path = "")
  return ProjectWidget(
    title,
    path,
  )
end

function initcontext(widget::ProjectWidget, ctx)
  wctx = Dict{Symbol, Any}()
  # Require global context for saving the project to file
  wctx[:ctx] = ctx
  # Global entries
  loadentries!(wctx, ctx, [:name, :comment, :nimages])
  # Widget fields
  loadentries!(wctx, widget, obs = true)

  return wctx
end

gridlayoutoptions(::ProjectWidget, wctx) = (size = (4, 2),)

function plotwidget(::ProjectWidget, layout, wctx, theme)
  rowgap!(layout, 2, 10)

  Label(
    layout[1, :],
    lift((t, n) -> "$t: $n", wctx[:title], wctx[:name]),
    font = :bold,
    fontsize = theme[:widget_titlesize],
    halign = :left,
  )

  save_button = Button(
    layout[1, :],
    label = "⤓ Save",
    halign = :right,
    fontsize = theme[:widget_fontsize],
  )

  # save_confirmation = Label(
  #   layout[1, :],
  #   "",
  #   halign = :center,
  #   fontsize = theme[:widget_fontsize],
  #   font = :bold,
  #   color = :darkgreen,
  # )

  Label(
    layout[2, :],
    lift(n -> "Project with $n image files", wctx[:nimages]),
    fontsize = theme[:widget_fontsize],
    halign = :left,
    color = (:black, 0.7),
  )
  
  Label(
    layout[3, 1],
    "Path:",
    fontsize = theme[:widget_fontsize],
    halign = :right,
  )
  path_label = Label(
    layout[3, 2],
    isempty(wctx[:path][]) ? "<unsaved>" : wctx[:path][],
    fontsize = theme[:widget_fontsize],
    halign = :left,
  )

  Label(
    layout[4, 1],
    "Comment:",
    fontsize = theme[:widget_fontsize],
    halign = :right,
  )
  comment_box = Textbox(
    layout[4, 2],
    stored_string = isempty(wctx[:comment][]) ? nothing : wctx[:comment][],
    fontsize = theme[:widget_fontsize],
    halign = :right,
    reset_on_defocus = true,
    placeholder = " ",
    width = 300,
  )

  on(save_button.clicks) do _
    @async begin
      path = NativeFileDialog.save_file() 
      old_path = wctx[:path][]
      wctx[:path][] = path
      ctx = wctx[:ctx]
      project = updateproject(ctx[:project], ctx)
      try
        saveproject(project, path)
      catch err
        @error err
        path_label.text[] = "Saving failed"
        path_label.color = :darkred
        wctx[:path][] = old_path
        # _save_failed(save_confirmation)
        return
      end
      path_label.text[] = path
      path_label.color = :black
    end
    # _save_confirmed(save_confirmation)
    return
  end

  on(comment_box.stored_string) do comment
    wctx[:comment][] = comment
  end
end

# function _save_confirmed(label)
#   label.text[] = "File saved"
#   @async begin
#     sleep(2)
#     label.text[] = ""
#   end
# end

# function _save_failed(label)
#   color = label.color[]
#   label.text[] = "File not saved"
#   label.color[] = :darkred
#   @async begin
#     sleep(2)
#     label.text[] = ""
#     label.color[] = color
#   end
# end
