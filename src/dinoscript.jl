
struct DinoScript
  path::String
  doc::String
  statistics::Vector{Pair{Symbol,String}}
  f::Function
  env::Module
end

function _generate_dinoscript_env()
  env = Module(:DinoScriptEnv)
  Core.eval(env, quote
    using Statistics
    using Random
    using LinearAlgebra
  end)
  return env
end

_dino_statistic_pair(sym::Symbol) = sym => ""
_dino_statistic_pair(str::String) = Symbol(str) => ""
_dino_statistic_pair(t::Tuple) = Symbol(t[1]) => string(t[2])
_dino_statistic_pair(t::Pair) = Symbol(t[1]) => string(t[2])

_dino_result(t) = Dict([k => v for (k, v) in t])

function DinoScript(path::String)
  code = read(path, String)
  code = Meta.parseall(code, filename=path)
  env = _generate_dinoscript_env()
  Core.eval(env, code)

  doc = try
    env.doc
  catch _
    ""
  end

  statistics = try
    env.statistics
  catch _
    error("Script '$path' does not define 'statistics'.")
  end
  @show statistics

  statistics = try
    [_dino_statistic_pair(s) for s in statistics]
  catch _
    error("Statistics declaration in script '$path' is malformed.")
  end

  f = try
    env.evaluate
  catch _
    error("Script '$path' does not define 'evaluate'.")
  end

  return DinoScript(path, doc, statistics, f, env)
end

function (script::DinoScript)(args...)
  result = try
    script.f(args...)
  catch err
    error("Script evaluation failed: $err.")
  end
  result = try
    _dino_result(result)
  catch
    error("Result format in script '$(script.path)' is malformed.")
  end
  for (name, _) in script.statistics
    if !haskey(result, name)
      error("Result in script '$(script.path)' misses statistic :$name.")
    end
  end
  return result
end
