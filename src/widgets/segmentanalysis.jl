

struct Segment <: Widget
  mask::BitMatrix
  color::Color
  source::Int
end

# TODO: What is called "Mask" in code is currently "Segment" out of code...
struct SegmentAnalysisWidget <: Widget
  title::String
  mask_provider::Symbol
  channel_provider::Symbol
  nexpressions::Int
  expressions::Vector{String}
end

function SegmentAnalysisWidget(title; nexpressions = 4, mask_provider, channel_provider)
  return SegmentAnalysisWidget(
    title,
    mask_provider,
    channel_provider,
    nexpressions,
    fill("", nexpressions),
  )
end

function initcontext(widget::SegmentAnalysisWidget, ctx)
  wctx = Dict{Union{Symbol, Int}, Any}()

  loadentries!(wctx, widget, obs = false)
  
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
  wctx[:lazy_evaluate] = Observables.async_latest(wctx[:evaluate], 1)

  # Whether each change should automatically trigger an evaluation
  wctx[:live] = Observable(true)

  return wctx
end

function _segmentanalysis_showsegments(layout, wctx, theme)
  ax = Axis(
    layout[2, 1],
    aspect = DataAspect(),
    yticklabelsvisible = false,
    yticksvisible = false,
    xticklabelsvisible = false,
    xticksvisible = false,
    yticklabelsize = theme[:widget_ticksize],
    xticklabelsize = theme[:widget_ticksize],
    panbutton=Makie.Mouse.left,
    height = 250,
    width = 250,
  )
  Makie.deregister_interaction!(ax, :rectanglezoom)
  Makie.deregister_interaction!(ax, :scrollzoom)
  Makie.deregister_interaction!(ax, :dragpan)

  for index in 1:wctx[:nmasks]
    Makie.image!(
      ax,
      wctx[:masks][index][:mask],
      colorrange = (0., 1.),
      colormap = [
        (:black, 0.01),
        (0.8wctx[:masks][index][:color], 0.5)
      ],
    )
  end

  elements = map(1:wctx[:nmasks]) do index
    return MarkerElement(
      color = 0.8wctx[:masks][index][:color],
      marker = :rect,
      markersize = 20,
      )
  end
  labels = map(1:wctx[:nmasks]) do index
    return "S$index: " * wctx[:masks][index][:name]
  end

  Legend(
    layout[2, 2],
    elements,
    labels,
    framevisible = false,
    valign = :top,
    fontsize = theme[:widget_fontsize],
  )
end

function _eval_expression(str, channels, masks, results)
  expr = Meta.parse(str)
  channel_defs = map(enumerate(channels)) do (index, channel)
    sym = Symbol("C$index")
    :($sym = $channel)
  end
  mask_defs = map(enumerate(masks)) do (index, mask)
    sym = Symbol("S$index")
    :($sym = $mask)
  end
  result_defs = map(enumerate(results)) do (index, result)
    sym = Symbol("R$index")
    :($sym = $result)
  end
  body = Expr(
    :let,
    Expr(:block),
    Expr(
      :block,
      channel_defs...,
      mask_defs...,
      result_defs...,
      expr,
    )
  )
  return eval(body)
end

_sprint_value(v::Real) = string(Base.round(v, digits = 2))

function _sprint_value(v::AbstractArray)
  m = round(mean(v), digits = 2)
  s = round(std(v), digits = 2)
  return "$m ± $s"
end

_check_result(val) = error("result of type $(typeof(val)) invalid")
_check_result(val::Real) = nothing
_check_result(val::AbstractArray) = nothing

function _segmentanalysis_expressions(layout, wctx, theme)
  grid = GridLayout(
    layout[2, 4],
    wctx[:nexpressions],
    4,
    valign = :top,
    default_rowgap = 5
  )

  masks = Observable(Vector(undef, wctx[:nmasks]))
  channels = Observable(Vector(undef, wctx[:nchannels]))
  results = Observable(Vector(undef, wctx[:nexpressions]))

  onany(masks, channels, results, wctx[:live]) do _, _, _, live
    if live
      notify(wctx[:evaluate])
    end
  end

  for index in 1:wctx[:nmasks]
    on(wctx[:masks][index][:mask], update = true) do mask
      masks[][index] = mask
      notify(masks)
    end
  end

  for index in 1:wctx[:nchannels]
    on(wctx[:channels][index][:data], update = true) do data
      channels[][index] = data
      notify(channels)
    end
  end

  for index in 1:wctx[:nexpressions]
    Label(
      grid[index, 1],
      "R$index:",
      fontsize = theme[:widget_fontsize],
    )
    expr_box = Textbox(
      grid[index, 2],
      placeholder = "expression to evaluate",
      fontsize = theme[:widget_fontsize],
      width = 300,
    )
    Label(
      grid[index, 3],
      "=",
      fontsize = theme[:widget_fontsize],
    )
    Box(
      grid[index, 4],
      color = (:black, 0.02),
      strokevisible = false,
      cornerradius = 6,
    )
    result_label = Label(
      grid[index, 4],
      "",
      fontsize = theme[:widget_fontsize],
      halign = :center,
      width = 125,
      padding = (10, 10, 5, 5)
    )

    value = Observable{Any}()
    error = Observable("")

    onany(wctx[:lazy_evaluate], expr_box.stored_string) do _, str
      if isnothing(str) return end
      eval_task = Threads.@spawn _eval_expression(
        str,
        channels[],
        masks[],
        results[][1:index - 1],
      )
      try
        val = fetch(eval_task)
        _check_result(val)
        results[][index] = val
        value[] = val
        error[] = ""
      catch err
        err = err.task.exception
        @error """
        Encountered error $err while evaluating expressions
        """
        value[] = nothing
        error[] = string(err)
      end
    end

    on(value) do val
      if !isnothing(val)
        result_label.text[] = _sprint_value(val)
      end
    end

    on(error) do err
      if !isempty(err)
        expr_box.boxcolor[] = RGBA(0.7, 0.2, 0.2, 0.3)
        result_label.text[] = err
      else
        expr_box.boxcolor[] = RGB(1.0, 1.0, 1.0)
      end
    end
  end
end

gridlayoutoptions(::SegmentAnalysisWidget, wctx) = (size=(2, 4),)

function plotwidget(::SegmentAnalysisWidget, layout, wctx, theme)

  rowgap!(layout, 1, 15)
  colgap!(layout, 2, 20)
  colgap!(layout, 3, 20)

  Label(
    layout[1, :],
    wctx[:title],
    halign = :left,
    tellwidth = false,
    font = :bold,
    fontsize = theme[:widget_titlesize],
  )
  eval_button = Button(
    layout[1, :],
    label = "Evaluate",
    halign = :right,
    fontsize = theme[:widget_fontsize],
  )

  on(eval_button.clicks) do _
    notify(wctx[:evaluate])
  end

  _segmentanalysis_showsegments(layout, wctx, theme)
  Box(layout[2, 3], width = 0, strokewidth = 1)
  _segmentanalysis_expressions(layout, wctx, theme)

  return
end
