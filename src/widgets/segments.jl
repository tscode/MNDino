
module ExecutionEnvironment
using Statistics
function remove(a, b)
  map(a, b) do x, y
    if x && y
      return false
    elseif x
      return true
    else
      return false
    end
  end
end
end

struct Segment <: Widget
  mask::BitMatrix
  color::Color
  source::Int
end

# TODO: What is called "Mask" in code is currently "Segment" out of code...
struct SegmentsWidget <: Widget
  title::String
  mask_provider::Symbol
  channel_provider::Symbol
  nexpressions::Int
  expressions::Vector{String}
  varnames::Vector{String}
end

function SegmentsWidget(
  title;
  nexpressions = 4,
  mask_provider,
  channel_provider,
)
  return SegmentsWidget(
    title,
    mask_provider,
    channel_provider,
    nexpressions,
    fill("", nexpressions),
    ["R$i" for i in 1:nexpressions],
  )
end

function initcontext(widget::SegmentsWidget, ctx)
  wctx = Dict{Union{Symbol, Int}, Any}()

  loadentries!(wctx, widget; obs = false)

  mpctx = loadcontext(ctx, wctx[:mask_provider])
  dpctx = loadcontext(ctx, wctx[:channel_provider])

  wctx[:nmasks] = mpctx[:nmasks]
  wctx[:nchannels] = dpctx[:nchannels]

  wctx[:masks] = Dict{Int, Any}()
  wctx[:channels] = Dict{Int, Any}()

  for index in 1:wctx[:nmasks]
    wctx[:masks][index] = Dict{Symbol, Any}()
    wctx[:masks][index][:mask] = mpctx[index][:mask]
    wctx[:masks][index][:color] = mpctx[index][:color]
    wctx[:masks][index][:name] = mpctx[index][:name]
  end

  for index in 1:wctx[:nchannels]
    wctx[:channels][index] = Dict{Symbol, Any}()
    wctx[:channels][index][:data] = dpctx[index][:raw][:data]
    wctx[:channels][index][:color] = dpctx[index][:color]
    wctx[:channels][index][:name] = dpctx[index][:name]
  end

  # Notifying this will trigger evaluation
  wctx[:evaluate] = Observable(nothing)

  # Prevent evaluation requests from overflowing
  wctx[:lazy_evaluate] = Observables.async_latest(wctx[:evaluate])

  # Whether each change should automatically trigger an evaluation
  wctx[:live] = Observable(true)

  return wctx
end

function _segmentanalysis_topline(layout, wctx, theme)
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
    return wctx[:live][] = live
  end

  on(update_button.clicks) do _
    return notify(wctx[:evaluate])
  end

  return
end

function _segmentanalysis_showsegments(layout, wctx, theme)
  ax = Axis(
    layout[2, 1];
    aspect = DataAspect(),
    yticklabelsvisible = false,
    yticksvisible = false,
    xticklabelsvisible = false,
    xticksvisible = false,
    yticklabelsize = theme[:ticksize],
    xticklabelsize = theme[:ticksize],
    panbutton = Makie.Mouse.left,
    height = 250,
    width = 250,
  )
  Makie.deregister_interaction!(ax, :rectanglezoom)
  Makie.deregister_interaction!(ax, :scrollzoom)
  Makie.deregister_interaction!(ax, :dragpan)

  for index in 1:wctx[:nmasks]
    Makie.image!(
      ax,
      wctx[:masks][index][:mask];
      colorrange = (0.0, 1.0),
      colormap = [(:black, 0.01), (0.8wctx[:masks][index][:color], 0.5)],
    )
  end

  elements = map(1:wctx[:nmasks]) do index
    return MarkerElement(;
      color = 0.8wctx[:masks][index][:color],
      marker = :rect,
      markersize = 20,
    )
  end
  labels = map(1:wctx[:nmasks]) do index
    return "S$index: " * wctx[:masks][index][:name]
  end

  return Legend(
    layout[2, 2],
    elements,
    labels;
    framevisible = false,
    valign = :top,
    labelsize = theme[:fontsize],
    labelfont = :bold,
  )
end

function _eval_expression(str, channels, masks, results)
  if isnothing(str)
    return
  end
  expr = Meta.parse(str)
  channel_defs = map(enumerate(channels)) do (index, channel)
    sym = Symbol("C$index")
    return :($sym = $channel)
  end
  mask_defs = map(enumerate(masks)) do (index, mask)
    sym = Symbol("S$index")
    return :($sym = $mask)
  end
  result_defs = map(enumerate(results)) do (index, result)
    sym = Symbol("R$index")
    return :($sym = $result)
  end
  body = Expr(
    :let,
    Expr(:block),
    Expr(:block, channel_defs..., mask_defs..., result_defs..., expr),
  )
  result = ExecutionEnvironment.eval(body)
  _check_result(result)
  return result
end

_sprint_value(v::Real) = string(Base.round(v; digits = 2))

function _sprint_value(v::AbstractArray)
  m = round(mean(v); digits = 2)
  s = round(std(v); digits = 2)
  return "$m ± $s (Array with $(length(v)) entries)"
end

_check_result(val) = error("result with type $(typeof(val)) invalid")
_check_result(::Nothing) = nothing
_check_result(::Real) = nothing
_check_result(::AbstractArray) = nothing
_check_result(::AbstractString) = nothing

function _segmentanalysis_expressions(layout, wctx, theme)
  sublayout = GridLayout(
    layout[2, 4],
    wctx[:nexpressions],
    5;
    valign = :top,
    default_rowgap = 5,
    default_colgap = 5,
  )
  colgap!(sublayout, 1, 10)
  colgap!(sublayout, 3, 15)
  colgap!(sublayout, 4, 15)

  inputs = []
  outputs = []
  names = []

  for index in 1:wctx[:nexpressions]
    Label(
      sublayout[index, 1],
      "R$index:";
      fontsize = theme[:fontsize],
      font = :bold,
    )
    name = Textbox(
      sublayout[index, 2];
      placeholder = "name (R$index)",
      fontsize = theme[:fontsize],
      font = :bold,
      halign = :left,
    )
    box = Textbox(
      sublayout[index, 3];
      placeholder = "expression to evaluate",
      fontsize = theme[:fontsize],
      halign = :left,
    )
    Label(sublayout[index, 4], "="; fontsize = theme[:fontsize])
    Box(
      sublayout[index, 5];
      color = (:black, 0.02),
      strokevisible = false,
      cornerradius = 6,
    )
    output = Label(
      sublayout[index, 5],
      "";
      fontsize = theme[:fontsize],
      halign = :left,
      padding = (10, 10, 5, 5),
      tellwidth = false,
    )
    push!(inputs, box)
    push!(outputs, output)
    push!(names, name)
  end

  masks = Observable(Vector(undef, wctx[:nmasks]))
  channels = Observable(Vector(undef, wctx[:nchannels]))

  nexpr = wctx[:nexpressions]
  results = Vector(undef, nexpr)
  errors = Vector(undef, nexpr)

  for index in 1:wctx[:nmasks]
    on(wctx[:masks][index][:mask]; update = true) do mask
      masks[][index] = mask
      return notify(masks)
    end
  end

  for index in 1:wctx[:nchannels]
    on(wctx[:channels][index][:data]; update = true) do data
      channels[][index] = data
      return notify(channels)
    end
  end

  onany(masks, channels, wctx[:live]) do _, _, live
    if live
      notify(wctx[:evaluate])
    end
  end

  for (index, name) in enumerate(names)
    on(name.stored_string) do str
      str = isnothing(str) ? "R$index" : str
      return wctx[:varnames][index] = str
    end
  end

  for (index, input) in enumerate(inputs)
    on(input.stored_string) do str
      notify(wctx[:evaluate])
      str = isnothing(str) ? "" : str
      return wctx[:expressions][index] = str
    end
  end

  on(wctx[:lazy_evaluate]) do _
    task = Threads.@spawn for index in 1:nexpr
      try
        value = _eval_expression(
          inputs[index].stored_string[],
          channels[],
          masks[],
          results[1:(index - 1)],
        )
        errors[index] = nothing
        results[index] = value
      catch err
        errors[index] = string(err)
        results[index] = nothing
      end
    end
    @async begin
      wait(task)
      for index in 1:nexpr
        if !isnothing(results[index])
          outputs[index].text[] = _sprint_value(results[index])
        else
          outputs[index].text[] = ""
        end
        if !isnothing(errors[index])
          inputs[index].boxcolor[] = RGBA(0.7, 0.2, 0.2, 0.3)
          outputs[index].text[] = errors[index]
        else
          inputs[index].boxcolor[] = RGB(1.0, 1.0, 1.0)
        end
      end
    end
  end

  return
end

gridlayoutoptions(::SegmentsWidget, wctx) = (size = (2, 4),)

function plotwidget(::SegmentsWidget, layout, wctx, theme)
  _segmentanalysis_topline(layout, wctx, theme)
  _segmentanalysis_showsegments(layout, wctx, theme)

  Box(layout[2, 3]; width = 0, strokewidth = 1, strokecolor = :lightgray)

  _segmentanalysis_expressions(layout, wctx, theme)

  rowgap!(layout, 1, 15)
  colgap!(layout, 2, 30)
  colgap!(layout, 3, 30)

  return
end
