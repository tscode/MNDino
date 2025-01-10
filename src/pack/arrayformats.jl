
"""
Format for arrays that remembers the array size.

Built upon [`VectorFormat`](@ref).

## Defaults
`ArrayFormat` is the default format for `AbstractArray`. Use

    format(::Type{T}) = ArrayFormat()

or

    @pack T in ArrayFormat

to make `ArrayFormat` the default format for type `T`. If `T` is abstract,
use `{<: T}` to cover all subtypes.

## Packing
To support packing values of type `T` in `ArrayFormat`, implement

    destruct(val::T, ::ArrayFormat)::R

where the returned value `ret::R` must define `size` and must be packable in
[`VectorFormat`](@ref).

## Unpacking
To support unpacking values of type `T` packed in `ArrayFormat`, implement

    construct(::Type{T}, ::ArrayValue{Generator{T}}, ::ArrayFormat)::T

or make sure that the constructor `T(val::ArrayValue{Generator{T}})` is defined
(see [`ArrayValue`](@ref) and [`Generator`](@ref)).
"""
struct ArrayFormat <: Format end

"""
Wrapper struct employed when unpacking a value in [`ArrayFormat`](@ref).

Contains the fields `size` and `data`, the latter of which is usually a
`Generator` after reconstruction via unpack.
"""
struct ArrayValue{T}
  datatype::Symbol
  size::NTuple{N, Int} where {N}
  data::T
end

format(::Type{<:ArrayValue}) = MapFormat()

function valueformat(::Type{<:ArrayValue}, state, ::MapFormat)
  return state == 3 ? VectorFormat() : DefaultFormat()
end

function pack(io::IO, value, ::ArrayFormat, rules::Rules)::Nothing
  val = destruct(value, ArrayFormat(), rules)
  datatype = Base.eltype(val) |> string |> Symbol
  return pack(io, ArrayValue(datatype, size(val), val), rules)
end

function unpack(io::IO, ::Type{T}, ::ArrayFormat, rules::Rules)::T where {T}
  val = unpack(io, ArrayValue{Generator{T}}, rules)
  return construct(T, val, ArrayFormat(), rules)
end

"""
Pack vectors in binary format.  

Built upon [`BinaryFormat`](@ref).

## Defaults
`BinVectorFormat` is the default format for `BitVector`. Use

    format(::Type{T}) = BinVectorFormat()

or

    @pack T in BinVectorFormat

to make `BinVectorFormat` the default format for type `T`. If `T` is abstract,
use `{<: T}` to cover all subtypes.

## Packing
To support packing values of type `T` in `BinVectorFormat`, implement

    destruct(val::T, ::BinVectorFormat)::R

where the returned value `ret::R` must be packable in [`BinaryFormat`](@ref).

## Unpacking
To support unpacking values of type `T` packed in `BinVectorFormat`, implement

    construct(::Type{T}, ::Vector{UInt8}, ::BinVectorFormat)::T

or make sure that the constructor `T(bytes::Vector{UInt8})` is defined.
"""
struct BinVectorFormat <: Format end

function pack(io::IO, value, ::BinVectorFormat, rules::Rules)::Nothing
  val = destruct(value, BinVectorFormat(), rules)
  return pack(io, val, BinaryFormat(), rules)
end

function unpack(io::IO, ::Type{T}, ::BinVectorFormat, rules::Rules)::T where {T}
  bytes = unpack(io, BinaryFormat(), rules)
  return construct(T, bytes, BinVectorFormat(), rules)
end

"""
Pack arrays in binary format.  

Built upon [`BinVectorFormat`](@ref).

## Defaults
`BinArrayFormat` is the default format for `BitArray{N}` for `N > 1`. Use

    format(::Type{T}) = BinArrayFormat()

or

    @pack T in BinArrayFormat

to make `BinVectorFormat` the default format for type `T`. If `T` is abstract,
use `{<: T}` to cover all subtypes.

## Packing
To support packing values of type `T` in `BinArrayFormat`, implement

    destruct(val::T, ::BinArrayFormat)::R

where the returned value `ret::R` must define `Base.size` and must be packable
in [`BinaryFormat`](@ref).

## Unpacking
To support unpacking values of type `T` packed in `BinArrayFormat`, implement

    construct(::Type{T}, ::BinArrayValue{Vector{UInt8}}, ::BinArrayFormat)::T

or make sure that the constructor `T(val::BinArrayValue{Vector{UInt8}})` is
defined (see [`BinArrayValue`(@ref)]).
"""
struct BinArrayFormat <: Format end

"""
Wrapper object for unpacking values in [`BinArrayFormat`](@ref).

Contains the fields `size` and `data`, the latter of which is a `Vector{UInt8}`
after reconstruction via unpack.
"""
struct BinArrayValue{T}
  datatype::Symbol  # Only metadata, not checked during construction of arrays
  size::NTuple{N, Int} where {N}
  data::T
end

format(::Type{<:BinArrayValue}) = MapFormat()

function valueformat(::Type{<:BinArrayValue}, state, ::MapFormat)
  return state == 3 ? BinaryFormat() : DefaultFormat()
end

function pack(io::IO, value, ::BinArrayFormat, rules::Rules)
  val = destruct(value, BinArrayFormat(), rules)
  datatype = Base.eltype(val) |> string |> Symbol
  pack(io, BinArrayValue(datatype, size(val), val), rules)
  return
end

function unpack(io::IO, ::Type{T}, ::BinArrayFormat, rules::Rules)::T where {T}
  val = unpack(io, BinArrayValue{Vector{UInt8}}, rules)
  return construct(T, val, BinArrayFormat(), rules)
end

