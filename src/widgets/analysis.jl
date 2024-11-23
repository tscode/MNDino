
struct DinoScript
  path::String
  names::Vector{Pair{Symbol, String}}
  f::Function
end

"""
Common environment that all scripts derive from.
"""
function _generate_dinoscript_env()
  env = Module()
  Core.eval(env, quote
    using Statistics
    using Random
    using LinearAlgebra
  end)
  return env
end

function _load_dinoscript(path::String)
  code = read(path, String)
  code = Meta.parse(code, filename = path)
  env = _generate_dinoscript_env()
  Core.eval(env, code)
  names = try env.variables
  catch err
    error("Dinoscript '$path' does not define 'names'.")
  end
  f = try env.evaluate
  catch err
    error("Dinoscript '$path' does not define 'evaluate'.")
  end
  return (; path, names, f)
end

function _apply_dinoscript(script::DinoScript, args...)
  result = script.f(args...)
end

struct ChannelMaskAnalysisWidget <: Widget
  title::String
  scripts::Vector{String}
end


