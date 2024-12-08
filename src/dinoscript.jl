
"""
Script that acts on the data from a datastore and generates outputs.
"""
struct DinoScript
  path::String
  doc::String
  inputs::Vector{Symbol}
  outputs::Vector{Pair{Symbol,String}}
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

_dino_output_pair(sym::Symbol) = sym => ""
_dino_output_pair(str::String) = Symbol(str) => ""
_dino_output_pair(t::Tuple) = Symbol(t[1]) => string(t[2])
_dino_output_pair(t::Pair) = Symbol(t[1]) => string(t[2])

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

  inputs = try
    env.inputs
  catch _
    error("Script '$path' does not define 'inputs'.")
  end

  inputs = try
    [Symbol(input) for input in inputs]
  catch _
    error("Input declaration in script '$path' is malformed.")
  end

  outputs = try
    env.outputs
  catch _
    error("Script '$path' does not define 'outputs'.")
  end

  outputs = try
    [_dino_output_pair(s) for s in outputs]
  catch _
    error("Output declaration in script '$path' is malformed.")
  end

  f = try
    env.evaluate
  catch _
    error("Script '$path' does not define 'evaluate'.")
  end

  return DinoScript(path, doc, inputs, outputs, f, env)
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
  for (name, _) in script.outputs
    if !haskey(result, name)
      error("Result in script '$(script.path)' misses output :$name.")
    end
  end
  return result
end

function Base.show(io::IO, ::MIME"text/plain", ds::DinoScript)
  println(io, "DinoScript")
  println(io, " doc: ", ds.doc)
  println(io, " inputs: ", ds.inputs)
  print(io, " outputs:")
  for pair in ds.outputs
    print(io, "\n  ", pair)
  end
  return
end
