
struct AnalysisWidget <: Widget
  title::String
  script_path::String
  image_store::Symbol
  variable_store::Symbol
end

function AnalysisWidget(title; image_store, variable_store)
  return AnalysisWidget(title, "", image_store, variable_store)
end

function initcontext(widget::AnalysisWidget, ctx)
  wctx = Dict{Union{Symbol, Int}, Any}()

  loadentries!(
    wctx,
    widget,
    [:title, :image_store, :variable_store];
    obs = false,
  )
  loadentries!(wctx, widget, [:script_path]; obs = true)

  vars = loadcontext(ctx, wctx[:variable_store])
  store = loadcontext(ctx, wctx[:image_store])

  wctx[:load_error] = Observable{Union{String, Nothing}}(nothing)
  wctx[:eval_error] = Observable{Union{String, Nothing}}(nothing)

  wctx[:script] = Observable{Union{DinoScript, Nothing}}(nothing)
  wctx[:output] = Observable{Union{Dict, Nothing}}(nothing)

  # Notifying will trigger evaluation and store the result in output
  wctx[:evaluate] = Observable(nothing)

  # Whether each change should automatically trigger an evaluation
  wctx[:live] = Observable(true)

  # Store the export function that requires access to the global context
  wctx[:export] =
    () -> begin
      isnothing(wctx[:script][]) && return
      notify(ctx[:update])
      project = updateproject(ctx[:project], ctx)
      runscript(
        wctx[:script][],
        project;
        image_store = wctx[:image_store],
        variable_store = wctx[:variable_store],
        variables = [:zindex],
      )
    end

  # Script inputs
  inputs = Dict{Union{Symbol, Int}, Any}()
  inputobsf = []

  # React to changes of the script path
  on(wctx[:script_path]) do path
    isnothing(path) && return
    try
      wctx[:load_error][] = nothing
      wctx[:script][] = DinoScript(path)
    catch err
      wctx[:load_error][] = sprint(showerror, err)
      wctx[:script][] = nothing
      wctx[:output][] = nothing
    end
    return
  end

  # Check if the number of outputs can be displayed
  on(wctx[:script]; update = true) do script
    isnothing(script) && return
    if length(script.outputs) > 6
      @warn """
      Analysis widget cannot display more than 6 outputs. 
      """
      wctx[:load_error][] = "Cannot display more than 6 outputs."
    end
    return
  end

  # Load all inputs from the variable store
  on(wctx[:script]; update = true) do script
    isnothing(script) && return

    # Remove evaluation notifiers from (potential) previous script
    map(off, inputobsf)
    empty!(inputobsf)
    # Reset input dict
    empty!(inputs)

    for key in script.inputs
      if !haskey(vars, key)
        wctx[:load_error][] = "Requested variable $key does not exist."
        wctx[:script][] = nothing
        return
      end
    end

    for key in script.inputs
      inputs[key] = vars[key]
      obsf = on(inputs[key]) do _
        if wctx[:live][]
          notify(wctx[:evaluate])
        end
      end
      push!(inputobsf, obsf)
    end

    return
  end

  # Evaluate the outputs upon script change
  on(wctx[:script]; update = true) do script
    isnothing(script) && return
    notify(wctx[:evaluate])
    return
  end

  # Evaluate the script on the current input
  # async_latest: prevent evaluation requests from potentially overflowing
  on(Observables.async_latest(wctx[:evaluate])) do _
    # on(wctx[:evaluate]) do _
    script = wctx[:script][]
    isnothing(script) && return

    args = Dict(key => input[] for (key, input) in inputs)
    task = Threads.@spawn script(args)
    try
      wctx[:output][] = fetch(task)
      wctx[:eval_error][] = nothing
    catch err
      wctx[:output][] = nothing
      if err isa TaskFailedException
        wctx[:eval_error][] = sprint(showerror, err.task.exception)
      else
        wctx[:eval_error][] = sprint(showerror, err)
      end
    end
    return
  end

  return wctx
end

function _analysis_topline(layout, wctx, theme)
  layout = GridLayout(layout[1, :])
  Label(
    layout[1, 1],
    wctx[:title];
    halign = :left,
    tellwidth = false,
    font = :bold,
    fontsize = theme[:titlesize],
  )

  export_label = Label(layout[1, 2], ""; fontsize = theme[:fontsize])
  Label(layout[1, 3], "Auto Update"; fontsize = theme[:fontsize])
  live_toggle = Toggle(layout[1, 4]; height = 20, width = 40)

  update_button =
    Button(layout[1, 5]; label = "Update", fontsize = theme[:fontsize])

  export_button = Button(
    layout[1, 6];
    label = "Export...",
    fontsize = theme[:fontsize],
    font = :bold,
  )

  colgap!(layout, 3, 5)
  colgap!(layout, 4, 15)
  colgap!(layout, 5, 15)

  on(live_toggle.active; update = true) do live
    wctx[:live][] = live
    notify(wctx[:evaluate])
    return
  end

  on(update_button.clicks) do _
    notify(wctx[:evaluate])
    return
  end

  export_msg = (msg, color) -> begin
    @async begin
      export_label.color[] = color
      export_label.text[] = msg
      sleep(3)
      export_label.text[] = ""
    end
  end

  on(export_button.clicks) do _
    red = RGB(0.5, 0.2, 0.2)
    green = RGB(0.2, 0.4, 0.2)
    # @async begin
    begin
      if isnothing(wctx[:script][])
        export_msg("no script loaded", red)
        return
      end
      path = NativeFileDialog.save_file(filelist="csv")
      if path == ""
        export_msg("export aborted", red)
        return
      end
      try
        task = Threads.@spawn wctx[:export]()
        names, data = fetch(task)
        open(path, "w") do io
          println(io, join(names, ","))
          return writedlm(io, data, ',')
        end
        export_msg("export successful", green)
      catch err
        export_msg("export failed", red)
      end
    end
  end

  # TODO: Export button. Will probably work by internally saving and loading the
  # project and cycling through the images?

  return
end

function _analysis_script(layout, wctx, theme)
  layout = GridLayout(layout[2, :], 1, 3)

  path_label = Label(
    layout[1, 1],
    "No script loaded";
    color = (:black, 0.7),
    fontsize = theme[:fontsize],
  )

  msg_label = Label(
    layout[1, 2],
    "";
    color = :darkred,
    tellwidth = false,
    fontsize = theme[:fontsize],
    halign = :left,
  )

  load_button = Button(
    layout[1, 3];
    label = "Load script",
    fontsize = theme[:fontsize],
    halign = :right,
  )

  onerror = err -> begin
    if isnothing(err)
      msg_label.text[] = ""
    elseif length(err) > 100
      msg_label.text[] = err[1:100] * " ..."
    else
      msg_label.text[] = err
    end
  end

  on(onerror, wctx[:load_error])
  on(onerror, wctx[:eval_error])

  on(load_button.clicks) do _
    @async begin
      path = NativeFileDialog.pick_file()
      wctx[:script_path][] = path
    end
  end

  on(wctx[:script]) do script
    if isnothing(script)
      path_label.text[] = "No script loaded"
    else
      path = wctx[:script_path][]
      path_label.text[] = "Script: $path"
    end
  end
end

_output_to_string(s::String) = s
_output_to_string(v::Real) = string(Base.round(v; digits = 2))

function _output_to_string(v::AbstractArray{<:AbstractFloat, D}) where {D}
  m = round(mean(v); digits = 2)
  s = round(std(v); digits = 2)
  return "$m ± $s (Array, length $(length(v)))"
end

function _output_to_string(v)
  return "output not supported ($(typeof(v)))"
end

function _analysis_entries(layout, wctx, theme)
  names = []
  values = []
  xoffset = 2
  index = 0

  for yindex in 1:3, xindex in 1:4
    index += 1
    Label(
      layout[xindex + xoffset, (yindex - 1) * 4 + 1],
      "R$index:";
      fontsize = theme[:fontsize],
      font = :bold,
    )
    name = Label(
      layout[xindex + xoffset, (yindex - 1) * 4 + 2],
      " ";
      fontsize = theme[:fontsize],
      halign = :left,
    )
    Label(
      layout[xindex + xoffset, (yindex - 1) * 4 + 3],
      "=";
      fontsize = theme[:fontsize],
    )
    value = Label(
      layout[xindex + xoffset, (yindex - 1) * 4 + 4],
      " ";
      fontsize = theme[:fontsize],
      halign = :left,
      padding = (10, 10, 5, 5),
      tellwidth = false,
    )
    push!(values, value)
    push!(names, name)
  end

  # Script changes. Refresh all variable names.
  on(wctx[:script]) do script
    foreach(v -> v.text[] = " ", names)
    isnothing(script) && return
    for (index, out) in enumerate(script.outputs)
      if index < length(names)
        names[index].text[] = string(out[1])
      end
    end
  end

  # Output changed. Update the displayed values.
  on(wctx[:output]) do output
    if isnothing(output)
      foreach(v -> v.text[] = " ", values)
      return
    end
    script = wctx[:script][]
    for (index, out) in enumerate(script.outputs)
      if index < length(values)
        values[index].text[] = _output_to_string(output[out[1]])
      end
    end
  end

  return
end

gridlayoutoptions(::AnalysisWidget, wctx) = (size = (7, 12),)

function plotwidget(::AnalysisWidget, layout, wctx, theme)
  _analysis_topline(layout, wctx, theme)
  _analysis_script(layout, wctx, theme)

  # Box(layout[2, 3]; width = 0, strokewidth = 1, strokecolor = :lightgray)

  _analysis_entries(layout, wctx, theme)

  # rowgap!(layout, 1, 15)
  # colgap!(layout, 2, 30)
  # colgap!(layout, 3, 30)

  return
end
