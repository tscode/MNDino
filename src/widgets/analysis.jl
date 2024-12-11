
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

  wctx[:script_error] = Observable{Union{String, Nothing}}(nothing)

  wctx[:script] = Observable{Union{DinoScript, Nothing}}(nothing)
  wctx[:outputs] = Observable{Union{Dict, Nothing}}(nothing)

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
      wctx[:script][] = DinoScript(path)
    catch err
      wctx[:script_error][] = sprint(showerror, err)
      wctx[:script][] = nothing
      wctx[:outputs][] = nothing
    end
    return
  end

  # Check if the number of outputs can be displayed
  on(wctx[:script]; update = true) do script
    isnothing(script) && return
    if length(script.outputs) > 15
      @warn """
      Analysis widget cannot display more than 15 outputs. 
      """
      wctx[:script_error][] = "Cannot display more than 15 outputs."
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
        wctx[:script_error][] = "Requested variable $key does not exist."
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
      wctx[:outputs][] = fetch(task)
    catch err
      wctx[:outputs][] = nothing
      if err isa TaskFailedException
        wctx[:script_error][] = sprint(showerror, err.task.exception)
      else
        wctx[:script_error][] = sprint(showerror, err)
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
  live_toggle =
    Toggle(layout[1, 4]; height = 20, width = 40, active = wctx[:live][])

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
      sleep(5)
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
      path = NativeFileDialog.save_file(; filterlist = "csv")
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
    color = RGB(0.5, 0.2, 0.2),
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

  on(wctx[:script_error]) do err
    @async begin
      if length(err) > 100
        msg_label.text[] = err[1:100] * " ..."
      else
        msg_label.text[] = err
      end
      sleep(5)
      msg_label.text[] = ""
    end
  end

  on(load_button.clicks) do _
    @async begin
      path = NativeFileDialog.pick_file()
      if !isempty(path)
        wctx[:script_path][] = path
      end
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

function _analysis_create_entry(layout, name, index, xindex, yindex, theme)
  output_label = Label(
    layout[xindex, yindex],
    "O$index:";
    fontsize = theme[:fontsize],
    font = :bold,
  )
  name_label = Label(
    layout[xindex, yindex + 1],
    string(name);
    fontsize = theme[:fontsize],
    halign = :left,
  )
  equal_label =
    Label(layout[xindex, yindex + 2], "="; fontsize = theme[:fontsize])
  value_label = Label(
    layout[xindex, yindex + 3],
    " ";
    fontsize = theme[:fontsize],
    halign = :left,
    padding = (0, 0, 5, 5),
    tellwidth = false,
  )
  blocks = [output_label, name_label, equal_label, value_label]
  return value_label, blocks
end

function _analysis_entries(layout, wctx, theme)
  value_labels = []
  objects = []
  obsfs = []

  on(wctx[:script]) do script
    foreach(l -> l.text[] = " ", value_labels)
    foreach(delete!, objects)
    foreach(off, obsfs)
    empty!(objects)
    empty!(obsfs)
    isnothing(script) && return

    noutputs = length(script.outputs)
    for index in 1:min(noutputs, 15)
      name = script.outputs[index][1]
      value_label, blocks = _analysis_create_entry(
        layout,
        name,
        index,
        (index-1) % 5 + 3,
        4div(index-1, 5) + 1,
        theme,
      )
      push!(value_labels, value_label)
      append!(objects, blocks)
      obsf = on(wctx[:outputs]) do outputs
        if isnothing(outputs)
          value_label.text[] = ""
        else
          value_label.text[] = _output_to_string(outputs[name])
        end
      end
      push!(obsfs, obsf)
    end
  end

  return
end

gridlayoutoptions(::AnalysisWidget, wctx) = (size = (8, 12),)

function plotwidget(::AnalysisWidget, layout, wctx, theme)
  _analysis_topline(layout, wctx, theme)
  _analysis_script(layout, wctx, theme)
  _analysis_entries(layout, wctx, theme)

  return
end
