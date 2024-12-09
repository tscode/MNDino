
"""
A global variable store that is populated at runtime.

Stores no permanent information. Other providers can register variables they
want to make publically available, e.g., to be used as inputs in dino scripts
employed by `AnalysisWidget`.
"""
struct VariableStore <: Provider end

function addvariable!(vars, key, obs)
  key = key isa String ? Symbol(key) : key
  if haskey(vars, key)
    @error """
    The variable :$key is already defined.
    """
  else
    vars[key] = obs
  end
  return
end

function initcontext(store::VariableStore, ctx)
  vsctx = Dict{Union{Symbol, Int}, Any}()
  return vsctx
end
