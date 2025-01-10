
"""
Umbrella type for [`StructFormat`](@ref) and [`UnorderedStructFormat`](@ref).
"""
abstract type AbstractStructFormat <: AbstractMapFormat end

"""
    fieldnames(T::Type, ::AbstractStructFormat)

Return the field names of `T` when packing / unpacking in a struct format.

Defaults to `Base.fieldnames(T)`.
"""
fieldnames(T::Type, ::AbstractStructFormat) = Base.fieldnames(T)

"""
    fieldtypes(T::Type, ::AbstractStructFormat)

Return the field types of `T` when packing / unpacking in a struct format.

Defaults to `Base.fieldtypes(T)`.
"""
fieldtypes(T::Type, ::AbstractStructFormat) = Base.fieldtypes(T)

"""
    fieldformats(T::Type, ::AbstractStructFormat)

Return the field types of `T` when packing / unpacking in a struct format.
"""
function fieldformats(::Type{T}, fmt::AbstractStructFormat) where {T}
  return ntuple(_ -> DefaultFormat(), length(fieldnames(T, fmt)))
end

function pack(io::IO, value::T, fmt::AbstractStructFormat, rules::Rules) where {T}
  pairs = destruct(value, fmt, rules)
  Pack.writeheaderbytes(io, pairs, MapFormat())
  fmts = Pack.fieldformats(T, fmt)
  for (index, pair) in enumerate(pairs)
    fmt_val = fmts[index]
    pack(io, first(pair), StringFormat(), rules)
    pack(io, last(pair), fmt_val, rules)
  end
  return
end

"""
Format for packing structures.

Built upon the msgpack formats `fixmap`, `map 16`, `map 32`.
  
## Defaults
[`StructFormat`](@ref) is not used as default for any type. However, it should
be the first candidate when you want to pack custom structs. Use

    format(::Type{T}) = StructFormat()

or

    @pack T in StructFormat

to make [`StructFormat`](@ref) the default format for type `T`. If `T` is abstract,
use `{<: T}` to cover all subtypes.

## Packing
To support packing values of type `T` in [`StructFormat`](@ref), implement

    destruct(val::T, ::MapFormat)::R

where the returned value `ret::R` must implement `Base.length(ret)` (number of
entries) and must be iterable with key-value pairs as entries.

In contrast to [`MapFormat`](@ref), the keys are always stored in
[`StringFormat`](@ref) and the value formats are determined via
[`fieldformats`](@ref), which should return a tuple of formats for the value-entries
of the struct.

## Unpacking
To support unpacking values of type `T` packed in [`StructFormat`](@ref), 
implement
  
    construct(::Type{T}, pairs::Generator{T}, ::StructFormat)::T

or make sure that the constructor `T(values...)` is defined, where `values`
contains the value-entries of `pairs`.

The respective types and formats of the values are determined during unpacking
via [`fieldtypes`](@ref) and [`fieldformats`](@ref), which should return tuples
of types and formats. Additionally, [`fieldnames`](@ref) is queried to make sure
the keys encountered during unpacking are consistent with `T`.

!!! note "StructFormat vs. MapFormat"

    Both [`StructFormat`](@ref) and [`MapFormat`](@ref) can be used
    to pack custom structs. They perform comparably.

    - [`MapFormat`](@ref) is more flexible and can handle keys that are not
      symbols. In contrast, [`StructFormat`](@ref) requires static fieldtype, fieldname, and fieldformat information.
    
    - However, [`MapFormat`](@ref) will not counter-check key values during unpacking and can thus easily lead to corrupted data if applied on external msgpack binaries. Both
"""
struct StructFormat <: AbstractStructFormat end

function unpack(io::IO, ::Type{T}, fmt::StructFormat, rules::Rules)::T where {T}
  n = Pack.readheaderbytes(io, MapFormat())
  names = Pack.fieldnames(T, fmt)
  fmts = Pack.fieldformats(T, fmt)
  types = Pack.fieldtypes(T, fmt)
  @assert n == length(fmts) == length(types) """
  Unexpected number of fields encountered.
  """
  pairs = map(names, fmts, types) do name, fmt_val, type_val
    key = unpack(io, Symbol, StringFormat(), rules)
    if key != name 
      unpackerror("Encountered unexpected key :$key. Expected :$name.")
    end
    value = unpack(io, type_val, fmt_val, rules)
    return key=>value
  end
  return construct(T, pairs, fmt, rules)
end

"""
Modification of [`StructFormat`](@ref).

This map-based format automatically sorts entries according to
[`fieldnames`](@ref) during unpacking.

While the unpacking performance is deteriorated compared to
[`StructFormat`](@ref), this format makes it possible to load msgpack binaries
where the order of map-entries cannot be guaranteed.

By default, the constructor `T(values...)` is used when unpacking a type `T`
in [`UnorderedStructFormat`](@ref), where `values` denotes the value-entries
unpacked from the msgpack map. To use a keyword-argument based constructor, simply define

    construct(::Type{T}, pairs, ::UnorderedStructFormat) = T(; pairs...)
"""
struct UnorderedStructFormat <: AbstractStructFormat end

function unpack(io::IO, ::Type{T}, fmt::UnorderedStructFormat, rules ::Rules)::T where {T}
  n = Pack.readheaderbytes(io, MapFormat())
  names = Pack.fieldnames(T, fmt)
  fmts = Pack.fieldformats(T, fmt)
  types = Pack.fieldtypes(T, fmt)
  @assert n == length(fmts) == length(types) """
  Unexpected number of fields encountered.
  """
  pairs = Vector{Pair{Symbol}}(undef, n)
  for index in 1:n
    key = unpack(io, Symbol, StringFormat())
    index = findfirst(isequal(key), names)
    if isnothing(index)
      unpackerror("Encountered unexpected key :$key.")
    end
    fmt_val = fmts[index]
    type_val = types[index]
    value = unpack(io, type_val, fmt_val, rules)
    if isassigned(pairs, index)
      unpackerror("""
      Duplicated key :$key. This is not supported by UnorderedStructFormat.
      """)
    end
    pairs[index] = (key=>value)
  end
  return construct(T, pairs, fmt, rules)
end
