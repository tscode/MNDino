
"""
Abstract format type.

Formats determine the rules for packing and unpacking values via msgpack
primitives. They are supposed to be singleton types.

To add support for a new format `F <: Format`, define the corresponding
methods of [`pack`](@ref) and [`unpack`](@ref).

This package comes with a number of built-in formats. The following core formats
have low-level implementations that build upon one or more formats of the
msgpack specification:

- [`NilFormat`](@ref) (msgpack nil),
- [`BoolFormat`](@ref) (msgpack boolean),
- [`SignedFormat`](@ref) (msgpack negative / positive fixint, signed 8-64),
- [`UnsignedFormat`](@ref) (msgpack positive fixint, unsigned 8-64),
- [`StringFormat`](@ref) (msgpack fixstr, str 8-32),
- [`BinaryFormat`](@ref) (msgpack bin 16, bin 32).

For vector-like and map-like objects, several built-in formats with different
benefits and drawbacks are provided as subtypes of

- [`AbstractVectorFormat`](@ref) (msgpack fixarray, array 16, array 32),
- [`AbstractMapFormat`](@ref) (msgpack fixmap, map 16, map 32).

Additional convenience formats include

- [`ArrayFormat`](@ref) (store multidimensional arrays),
- [`BinVectorFormat`](@ref) (store vectors with bitstype elements efficiently),
- [`BinArrayFormat`](@ref) (store multidimensional bitstype arrays efficiently),
- [`TypedFormat`](@ref) (store values and their type for generic unpacking).
"""
abstract type Format end

"""
Umbrella type for [`VectorFormat`](@ref) and [`DynamicVectorFormat`](@ref).
"""
abstract type AbstractVectorFormat <: Format end

"""
Umbrella type for [`MapFormat`](@ref), [`DynamicMapFormat`](@ref), and
[`AbstractStructFormat`](@ref).
"""
abstract type AbstractMapFormat <: Format end

"""
Abstract rules type.

Rules are introduced to enforce custom behavior when packing and unpacking
values.

In particular, rules can influence which formats are assigned to types (via
[`format`](@ref)) or to fields of a struct (via [`valueformat`](@ref)).
They can also influence how objects are processed before packing and after
unpacking (via [`destruct`](@ref) and [`construct`(@ref)]).
"""
abstract type Rules end

"""
Rules object that directs packing / unpacking towards fallback implementations.

This is an auxiliary type and should not come into contact with users of the
package.

!!! warn

    Do not dispatch on `::FallbackRules` to provide global defaults.
    Always use [`Rules`](@ref)-free methods for this purpose.
    For example, use `format(::Type{MyType}) = ...` instead of
    `format(::Type{MyType}, ::FallbackRules) = ...` to set a default format
    for `MyType`.
"""
struct FallbackRules <: Rules end

"""
Scoped value that captures the active packing rules.
"""
const rules = ScopedValue{Rules}(FallbackRules())

"""
Error that is thrown when unpacking fails due to unexpected data.
"""
struct UnpackError <: Exception
  msg::String
end

"""
    unpackerror(msg)

Throw an [`UnpackError`](@ref) with message `msg`.
"""
unpackerror(msg) = throw(UnpackError(msg))

"""
    format(T::Type [, rules::Rules])::Format
    format(::T [, rules::Rules])::Format

Return the format associated to type `T` under `rules`.

The rules-free version of this method must be implemented in order for `pack(io,
value::T)` and `unpack(io, T)` to work. It is used as fallback for all rules.

See also [`Format`](@ref) and [`DefaultFormat`](@ref).
"""
function format(T::Type)
  return error("No default format specified for type $T")
end

# Support calling format on values
format(::T, args...) where {T} = format(T, args...)

# Specialize this method to select custom formats in your rules
format(T::Type, ::Rules) = format(T)

"""
    construct(T::Type, val, fmt::Format [, rules::Rules])::T

Postprocess a value `val` unpacked according to `fmt` and return an object
of type `T`. The type of `val` depends on the format `fmt` that was used for
unpacking.

Defaults to `T(val)` but can be overwritten for any combination of `T`, `fmt`,
and `rules`.
"""
construct(T::Type, val, ::Format) = T(val)

# Extend this function to use custom constructors in your rules
construct(T::Type, val, fmt::Format, ::Rules) = construct(T, val, fmt)

"""
    destruct(val::T, fmt::Format [, rules::Rules])

Preprocess a value `val` to prepare packing it in the format `fmt`.

Defaults to `val` but can be overwritten for any combination of `T`, `fmt`,
and `rules`.

Each format has specific requirements regarding the output of this method.
"""
destruct(val, ::Format) = val

# Extend this function to use custom destructors in your rules
destruct(val, fmt::Format, ::Rules) = destruct(val, fmt)

"""
    pack(value, [, rules::Rules])::Vector{UInt8}
    pack(value, [, fmt::Format, rules::Rules])::Vector{UInt8}
    pack(io::IO, args...)::Nothing

Create a binary msgpack representation of `value` according to the given format
`fmt`. If a stream `io` is passed, the representation is written into it.

If no format is provided, it is derived from the type of `value` via
`format(typeof(value), rules)`. The rules default to the value hold by
[`Pack.rules`](@ref).

If both a format and rules are provided, `fmt` is used for packing `value`
while `rules` is passed along to deeper packing related calls.
"""
function pack(io::IO, value::T, rules::Rules = Pack.rules[])::Nothing where {T}
  return pack(io, value, format(T, rules), rules)
end

function pack(io::IO, value::T, fmt::Format)::Nothing where {T}
  return pack(io, value, fmt, Pack.rules[])
end

function pack(value::T, args...)::Vector{UInt8} where {T}
  @assert !(T <: IO) """
  Cannot call pack with the provided arguments.
  """
  io = IOBuffer(; write = true, read = false)
  pack(io, value, args...)
  return take!(io)
end

"""
    unpack(bytes::Vector{UInt8}, T::Type [, rules::Rules])::T
    unpack(bytes::Vector{UInt8}, T::Type [, fmt::Format, rules::Rules])::T
    unpack(io::IO, T::Type, args...)::T

Unpack a binary msgpack representation of a value of type `T` in format `fmt`
from a byte vector `bytes` or a stream `io`. The returned value is guaranteed to
be of type `T`.

If no format is provided, it is derived from `T` via `format(T, rules)`.
The rules default to the value hold by [`Pack.rules`](@ref).
"""
function unpack(io::IO, ::Type{T}, rules::Rules = Pack.rules[])::T where {T}
  return unpack(io, T, format(T, rules), rules)
end

function unpack(io::IO, ::Type{T}, fmt::Format, rules::Rules = Pack.rules[]) where {T}
  val = unpack(io, fmt, rules)
  return construct(T, val, fmt, rules)
end

function unpack(::IO, fmt::Format, rules::Rules = Pack.rules[])
  unpackerror("Generic unpacking in format $fmt not supported")
  return
end

function unpack(bytes::Vector{UInt8}, args...)
  io = IOBuffer(bytes; write = false, read = true)
  return unpack(io, args...)
end

"""
    unpack(bytes::Vector{UInt8})::Any
    unpack(io::IO)::Any
  
Unpack a binary msgpack value via the special format [`AnyFormat`](@ref).
The returned value can be of any type.
"""
unpack(io::IO) = unpack(io, AnyFormat())

"""
Special format that serves as lazy placeholder for `format(T)` in
situations where the type `T` is not yet known.

!!! warning

    Never define `format(T)` for a type `T` in terms of `DefaultFormat`.
    This will lead to indefinite recursion.
"""
struct DefaultFormat <: Format end

pack(io::IO, val, ::DefaultFormat, rules::Rules) = pack(io, val, rules)

function unpack(io::IO, ::Type{T}, ::DefaultFormat, rules::Rules) where {T}
  return unpack(io, T, rules)
end

"""
    keytype(T::Type, state, fmt::Format [, rules::Rules])::Type

Return the type of the key at iteration state `state` when saving the entries
of `T` in format `fmt`.

This method is called when unpacking values in [`AbstractMapFormat`](@ref).
"""
keytype(::Type, state, ::Format) = Symbol # default to support generic structs
keytype(T::Type, state, fmt::Format, ::Rules) = keytype(T, state, fmt)

"""
    keyformat(T::Type, state, fmt::Format [, rules::Rules])::Format

Return the format of the key at iteration state `state` when saving the entries
of `T` in format `fmt`.

This method is called when packing or unpacking values in
[`AbstractMapFormat`](@ref).
"""
keyformat(::Type, state, ::Format) = DefaultFormat()
keyformat(T::Type, state, fmt::Format, ::Rules) = keyformat(T, state, fmt)

"""
    valuetype(T::Type, fmt::Format, state [, rules::Rules])::Type

Return the type of the value at iteration state `state` when saving the entries
of `T` in format `fmt`.

This method is used when unpacking values in [`AbstractVectorFormat`](@ref) and
[`AbstractMapFormat`](@ref).
"""
valuetype(T::Type, state, ::Format) = Base.fieldtype(T, state)
valuetype(T::Type, state, fmt::Format, ::Rules) = valuetype(T, state, fmt)

"""
    valueformat(T::Type, state, fmt::Format [, rules::Rules])::Format

Return the format of the value at iteration state `state` when saving the
entries of `T` in format `fmt`.

This method is used when packing or unpacking values in
[`AbstractVectorFormat`](@ref) and [`AbstractMapFormat`](@ref).
"""
valueformat(::Type, state, ::Format) = DefaultFormat()
valueformat(T::Type, state, fmt::Format, ::Rules) = valueformat(T, state, fmt)

