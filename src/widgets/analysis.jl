

struct AnalysisWidget <: Widget
  title::String
  script_path::String
  variable_store::Symbol
end

function AnalysisWidget(title; variable_store)
  return AnalysisWidget(title, "", variable_store)
end

# function _analysis_data_loaded(inputs, pctxs)
#   return all(eachindex(pctxs)) do pindex
#     all(pctxs[pindex][:data_keys]) do key
#       haskey(inputs[pindex], key)
#     end
#   end
# end

function initcontext(widget::AnalysisWidget, ctx)
  wctx = Dict{Union{Symbol, Int}, Any}()

  loadentries!(wctx, widget, [:title, :variable_store]; obs = false)
  loadentries!(wctx, widget, [:script_path]; obs = true)

  variables = loadcontext(ctx, wctx[:variable_store])

  wctx[:load_error] = Observable{Union{String, Nothing}}(nothing)
  wctx[:eval_error] = Observable{Union{String, Nothing}}(nothing)

  wctx[:script] = Observable{Union{DinoScript, Nothing}}(nothing)
  wctx[:output] = Observable{Union{Dict, Nothing}}(nothing)

  # Notifying will trigger evaluation and store the result in wctx[:output]
  wctx[:evaluate] = Observable(nothing)

  # Whether each change should automatically trigger an evaluation
  wctx[:live] = Observable(true)

  # Script inputs
  inputs = Dict{Union{Symbol, Int}, Any}()
  inputobsf = []

  # React to changes of the script path
  on(wctx[:script_path]) do path
    try
      wctx[:load_error][] = nothing
      wctx[:script][] = DinoScript(path)
    catch err
      wctx[:load_error][] = string(err)
      wctx[:script][] = nothing
    end
    return
  end

  # Check if the number of outputs can be displayed
  on(wctx[:script], update = true) do script
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
  on(wctx[:script], update = true) do script
    isnothing(script) && return

    # Remove evaluation notifiers from (potential) previous script
    map(off, inputobsf)
    empty!(inputobsf)
    # Reset input dict
    empty!(inputs)
    
    for key in script.inputs
      if !haskey(variables, key)
        wctx[:load_error][] = "Requested variable $key does not exist."
        wctx[:script][] = nothing
        return
      end
    end

    for key in script.inputs
      inputs[key] = variables[key]
      obsf = on(inputs[key]) do
        if wctx[:live][]
          notify(wctx[:evaluate])
        end
      end
      push!(inputobsf, obsf)
    end

    return
  end

  # Evaluate the outputs upon script change
  on(wctx[:script], update = true) do script
    isnothing(script) && return
    notify(wctx[:evaluate])
    return
  end

  # Evaluate the script on the current input
  # async_latest: prevent evaluation requests from potentially overflowing
  on(Observables.async_latest(wctx[:evaluate])) do _
    script = wctx[:script][]
    isnothing(script) && return

    args = Dict(key => input[] for (key, input) in inputs)
    task = Threads.@spawn script(args...)
    try
      wctx[:output][] = fetch(task)
      wctx[:eval_error][] = nothing
    catch err
      wctx[:output][] = nothing
      wctx[:eval_error][] = string(err.exception)
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

  return
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

function _analysis_scripts(layout, wctx, theme)
  layout = GridLayout(layout[2, :], 1, 3)

  path_label = Label(
    layout[1, 1],
    "";
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

  onerror = err -> msg_label.text[] = isnothing(err) ? "" : err
  on(onerror, wctx[:load_error])
  on(onerror, wctx[:eval_error])
  on(load_button.clicks) do _
    @async begin
      path = NativeFileDialog.pick_file()
      path_label.text[] = "Script '$path' loaded"
      wctx[:script_path][] = path
    end
  end
end

function _analysis_entries(layout, wctx, theme)
  # colgap!(layout, 1, 10)
  # colgap!(layout, 3, 15)
  # colgap!(layout, 4, 15)
  names = []
  values = []

  for xindex in 1:wctx[:ncolumns], yindex in 1:wctx[:nrows]
    index = xindex + wctx[:nrows] * (yindex - 1)
    Label(
      layout[xindex + 1, (yindex - 1) * 4 + 1],
      "R$index:";
      fontsize = theme[:fontsize],
      font = :bold,
    )
    name = Label(
      layout[xindex + 1, (yindex - 1) * 4 + 2];
      fontsize = theme[:fontsize],
      halign = :right,
    )
    Label(
      layout[xindex + 1, (yindex - 1) * 4 + 3],
      "=";
      fontsize = theme[:fontsize],
    )
    value = Label(
      layout[xindex + 1, (yindex - 1) * 4 + 4],
      "";
      fontsize = theme[:fontsize],
      halign = :left,
      padding = (10, 10, 5, 5),
      tellwidth = false,
    )
    push!(values, value)
    push!(names, name)
  end

  on(wctx[:script]) do script
    for (index, name) in enumerate(script.outputs)
      if index < length(names)
        names[index].text[] = string(name)
      end
    end
  end

  on(wctx[:outputs]) do outputs
    if isnothing(outputs)
      foreach(v -> v.text[] = "", values)
      return
    end
    for (index, out) in enumerate(outputs)
      if index < length(values)
        values[index].text[] = _output_to_string(out[2])
      end
    end
  end

  return
end

gridlayoutoptions(::AnalysisWidget, wctx) = (size = (3, 4),)

function plotwidget(::AnalysisWidget, layout, wctx, theme)
  _analysis_topline(layout, wctx, theme)
  _analysis_script(layout, wctx, theme)

  # Box(layout[2, 3]; width = 0, strokewidth = 1, strokecolor = :lightgray)

  # _analysis_entries(layout, wctx, theme)

  # rowgap!(layout, 1, 15)
  # colgap!(layout, 2, 30)
  # colgap!(layout, 3, 30)

  return
end
