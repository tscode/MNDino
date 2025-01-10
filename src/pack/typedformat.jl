
"""
Whitelist type.

A whitelist can be activated via assigning to the scoped value
[`Pack.whitelist`](@ref).
"""
abstract type Whitelist end

whitelisted(::Whitelist, ::Type) = false
whitelisted(types::Vector{Type}, T::Type) = any(S -> T <: S, types)

"""
Default whitelist object that permits any constructor.
"""
struct PermissiveWhitelist <: Whitelist end

whitelisted(::PermissiveWhitelist, ::Type) = true

"""
Scoped value that captures the active whitelist.

It can either be of type [`Whitelist`](@ref), configured via
[`whitelisted`](@ref), or a vector of accepted types.
"""
const whitelist = ScopedValue{Union{Whitelist, Vector{Type}}}(
  PermissiveWhitelist()
)

"""
    typeparamtype(T::Type, index , ::Format[, ::Rules])

Return the type of the `index`-th type parameter of `T`.

Defaults to `Any`.

This method is consulted when packing / unpacking types via [`TypeFormat`](@ref)
and [`TypedFormat`](@ref). It can be used to insert information about the type
parameters of `T`.
"""
typeparamtype(T::Type, index, ::Format) = Any

function typeparamtype(T::Type, index, fmt::Format, ::Rules)
  return typeparamtype(T, index, fmt)
end

"""
    typeparamformat(T::Type, index, fmt::Format [, rules::Rules])

Return the type param format of the `index`-th type parameter of `T`

Defaults to `TypedFormat()`.

This method is consulted when packing / unpacking types via [`TypeFormat`](@ref)
and [`TypedFormat`]. It can be used to insert information about the type
parameters of `T`.

This method is called by `valueformat(TypeParams{T}, fmt, index, rules)`.
"""
typeparamformat(::Type, index, ::Format) = TypedFormat()

function typeparamformat(T::Type, index, fmt::Format, ::Rules)
  return typeparamformat(T, index, fmt)
end

"""
Auxiliary structure that expresses the parameters of a parametric type in a
format friendly to serialization.
"""
struct TypeParams{T}
  params::Vector{Any}
end

format(::Type{<:TypeParams}) = VectorFormat()

function valuetype(::Type{TypeParams{T}}, index, fmt::Format, rules::Rules) where {T}
  return typeparamtype(T, index, fmt, rules)
end

function valueformat(::Type{TypeParams{T}}, index, fmt::Format, rules::Rules) where {T}
  return typeparamformat(T, index, fmt, rules)
end

destruct(t::TypeParams, ::VectorFormat) = t.params

function construct(::Type{TypeParams{T}}, vals, ::VectorFormat) where {T}
  return TypeParams{T}(collect(vals))
end

"""
    TypeParams()

Create an empty type parameter list.
"""
TypeParams() = TypeParams{Any}([])

"""
    TypeParams(T::Type)

Extract the type parameters of a given type `T` and return a `TypeParams` object.

!!! warning

    Currently, the following limitation holds: If `T` has more type parameters
    than are explicitly specified (`T = Array{Float32}`), the specified
    parameters must come first. For example, `TypeParams(T)` for
    `T = Array{F, 1} where {F}` will fail.
"""
function TypeParams(T::Type)
  params = nothing
  vars = []
  body = T
  while isnothing(params)
    if hasproperty(body, :parameters)
      params = collect(body.parameters)
    elseif hasproperty(body, :body) && hasproperty(body, :var)
      push!(vars, body.var)
      body = body.body
    else
      error("Failed to understand parameter structure of type $T.")
    end
  end
  for R in reverse(vars)
    @assert pop!(params) == R """
    Cannot extract type parameters from type $T.
    """
  end
  params = map(params) do param
    param isa Type ? TypeValue(param) : param
  end
  return TypeParams{T}(params)
end

"""
Auxiliary structure that expresses a type in a format friendly to serialization.
"""
struct TypeValue
  name::Symbol
  path::Vector{Symbol}
  params::TypeParams
end

format(::Type{TypeValue}) = DynamicMapFormat()
iterstate(::Type{TypeValue}, ::DynamicMapFormat) = []
iterstate(::Type{TypeValue}, state, entry, ::DynamicMapFormat) = push!(state, entry[2])

function valuetype(::Type{TypeValue}, state, ::DynamicMapFormat)
  index = length(state) + 1
  if index == 3 # derive the type T (without type parameters) from name and path
    T = composetype(TypeValue(state..., TypeParams()))
    TypeParams{T}
  else
    fieldtype(TypeValue, index)
  end
end

"""
Format that is used for packing types.

In order to pack and unpack a type `T::Type` in `TypeFormat`, you have to make
sure that `t = TypeValue(T)` and `composetype(t)` work as intended.
"""
struct TypeFormat <: Format end

function pack(io::IO, value, ::TypeFormat, rules::Rules)
  pack(io, TypeValue(value), DynamicMapFormat(), rules)
end

function unpack(io::IO, ::TypeFormat, rules::Rules)
  t = unpack(io, TypeValue, DynamicMapFormat(), rules)
  return composetype(t)
end

"""
    TypeValue(T::Type)

Create a `TypeValue` object from a given type `T`.

The resulting object can be packed / unpacked in [`MapFormat`](@ref) and can be
converted back to `T` via [`composetype`](@ref).
"""
function TypeValue(T::Type)
  name = Base.nameof(T)
  path = string(Base.parentmodule(T))
  path = Symbol.(split(path, "."))
  params = TypeParams(T)
  return TypeValue(name, path, params)
end

TypeValue(val) = TypeValue(typeof(val))

function composetype(value::TypeValue)::Type
  T = Main
  for m in value.path
    T = getfield(T, m)::Module
  end
  T = getfield(T, value.name)::Type
  params = composetypeparam.(value.params.params)
  return isempty(params) ? T : T{params...}
end

composetypeparam(value) = value 
composetypeparam(value::TypeValue) = composetype(value)
composetypeparam(str::String) = Symbol(str)
composetypeparam(t::Tuple) = composetypeparam.(t)

"""
Auxiliary structure that expresses a value and its type in a format friendly
to serialization.
"""
struct TypedValue{T, F}
  type::TypeValue
  value::Any
end

"""
  TypedValue{F}(val)

Create a `TypedValue` with value format `F()`.
"""
TypedValue{F}(val::T) where {F, T} = TypedValue{T, F}(TypeValue(val), val)

format(::Type{<: TypedValue}) = DynamicMapFormat()
iterstate(::Type{<: TypedValue}, ::DynamicMapFormat) = []
iterstate(::Type{<: TypedValue}, state, entry, ::DynamicMapFormat) = push!(state, entry[2])

function valueformat(::Type{TypedValue{T, F}}, state, ::DynamicMapFormat) where {T, F}
  return length(state) == 0 ? DefaultFormat() : F()
end

function valuetype(::Type{TypedValue{T, F}}, state, ::DynamicMapFormat) where {T, F}
  if length(state) == 0
    return TypeValue
  else
    S = composetype(state[1])
    @assert S <: T """
    Encountered the unexpected type $S when unpacking a typed value of type $T.
    """
    @assert whitelisted(whitelist[], S) """
    Packing or unpacking a typed value encountered type $T, which is not
    whitelisted under the current whitelist $(whitelist[]).
    
    If you expect and trust this type during unpacking, you can update the
    whitelist to enable support.
    """
    return S
  end
end

"""
Wrapper format for storing the value and type of an object.

If a value `val::T` can be packed in the format `F<:Format` and its type `T`
can be packed in [`TypeFormat`](@ref), then packing `val` in `TypedFormat{F}`
enables unpacking via `unpack(io, TypedFormat{F}())`, i.e., without knowledge
of `T`.
"""
struct TypedFormat{F <: Format} <: Format end

TypedFormat() = TypedFormat{DefaultFormat}()

function pack(io::IO, value, ::TypedFormat{F}, rules::Rules) where {F <: Format}
  pack(io, TypedValue{F}(value), DynamicMapFormat(), rules)
end

function unpack(io::IO, T::Type, ::TypedFormat{F}, rules::Rules) where {F <: Format}
  tval = unpack(io, TypedValue{T, F}, DynamicMapFormat(), rules)
  @assert tval.value isa T """
  Expected value type $T when unpacking typed value. Found $(typeof(tval.value)).
  """
  return tval.value
end

function unpack(io::IO, fmt::TypedFormat, rules::Rules = Pack.rules[])
  return unpack(io, Any, fmt, rules)
end

