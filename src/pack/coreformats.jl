
"""
    isformatbyte(byte, format::Format)

Check if `byte` is compatible with `format`.
"""
function isformatbyte(byte, ::Format)
  return error("No format byte is specified for this core format")
end

"""
    byteerror(byte, format)

Throw an error indicating that `byte` is not compatible with `format`.
"""
function byteerror(byte, ::F) where {F <: Format}
  unpackerror("Invalid format byte $byte when unpacking value in format $F")
  return
end

"""
Core format for packing nil values.

Built upon the msgpack format `nil`.

## Defaults
[`NilFormat`](@ref) is the default format of `Nothing`. Use

    format(::Type{T}) = NilFormat()

or

    @pack T in NilFormat

to make [`NilFormat`](@ref) the default format for type `T`. If `T` is abstract,
use `{<: T}` to cover all subtypes.

## Packing
All types can be packed in [`NilFormat`](@ref).

## Unpacking
To support unpacking values of type `T` packed in [`NilFormat`](@ref), implement
  
    construct(::Type{T}, ::Nothing, ::NilFormat)::T

or make sure that the constructor `T()` is defined.
"""
struct NilFormat <: Format end

function isformatbyte(byte, ::NilFormat)
  return byte == 0xc0
end

function pack(io::IO, value, ::NilFormat, ::Rules)::Nothing
  write(io, 0xc0)
  return nothing
end

function unpack(io::IO, ::NilFormat, ::Rules)::Nothing
  byte = read(io, UInt8)
  if byte == 0xc0
    nothing
  else
    byteerror(byte, NilFormat())
  end
end

construct(::Type{T}, ::Nothing, ::NilFormat) where {T} = T()

"""
Core format for packing boolean values.

Built upon the msgpack format `boolean`.

## Defaults
[`BoolFormat`](@ref) is the default format of `Bool`. Use

    format(::Type{T}) = BoolFormat()

or

    @pack T in BoolFormat

to make [`BoolFormat`](@ref) the default format for type `T`. If `T` is
abstract, use `{<: T}` to cover all subtypes.

## Packing
To support packing values of type `T` in [`BoolFormat`](@ref), implement

    destruct(val::T, ::BoolFormat)::Bool

## Unpacking
To support unpacking values of type `T` packed in [`BoolFormat`](@ref),
implement
  
    construct(::Type{T}, ::Bool, ::BoolFormat)::T

or make sure that the constructor `T(::Bool)` is defined.
"""
struct BoolFormat <: Format end

function isformatbyte(byte, ::BoolFormat)
  return byte == 0xc2 || byte == 0xc3
end

function pack(io::IO, value, ::BoolFormat, ::Rules)::Nothing
  if destruct(value, BoolFormat())
    write(io, 0xc3)
  else
    write(io, 0xc2)
  end
  return nothing
end

function unpack(io::IO, ::BoolFormat, ::Rules)::Bool
  byte = read(io, UInt8)
  if byte == 0xc3
    true
  elseif byte == 0xc2
    false
  else
    byteerror(byte, BoolFormat())
  end
end

"""
Core format for packing signed integer values.

Built upon the msgpack formats `negative fixint`, `positive fixint`,
`signed 8`, `signed 16`, `signed 32`, `signed 64`.

## Defaults
[`SignedFormat`](@ref) is the default format of all subtypes of `Signed`. Use

    format(::Type{T}) = SignedFormat()

or

    @pack T in SignedFormat

to make [`SignedFormat`](@ref) the default format for type `T`. If `T` is
abstract, use `{<: T}` to cover all subtypes.

## Packing
To support packing values of type `T` in [`SignedFormat`](@ref), implement

    destruct(val::T, ::SignedFormat)::Signed

## Unpacking
To support unpacking values of type `T` packed in [`SignedFormat`](@ref),
implement

    construct(::Type{T}, ::Int64, ::SignedFormat)::T

or make sure that the constructor `T(::Int64)` is defined.
"""
struct SignedFormat <: Format end

function isformatbyte(byte, ::SignedFormat)
  return byte <= 0x7f ||  # positive fixint
         byte >= 0xe0 ||  # negative fixint
         0xd0 <= byte <= 0xd3 # signed 8 to 64
end

function pack(io::IO, value, ::SignedFormat, ::Rules)::Nothing
  x = destruct(value, SignedFormat())
  if -32 <= x < 0 # negative fixint
    write(io, reinterpret(UInt8, Int8(x)))
  elseif 0 <= x < 128 # positive fixint
    write(io, UInt8(x))
  elseif typemin(Int8) <= x <= typemax(Int8) # signed 8
    write(io, 0xd0)
    write(io, Int8(x))
  elseif typemin(Int16) <= x <= typemax(Int16) # signed 16
    write(io, 0xd1)
    write(io, Int16(x) |> hton)
  elseif typemin(Int32) <= x <= typemax(Int32) # signed 32
    write(io, 0xd2)
    write(io, Int32(x) |> hton)
  elseif typemin(Int64) <= x <= typemax(Int64) # signed 64
    write(io, 0xd3)
    write(io, Int64(x) |> hton)
  else
    ArgumentError("invalid signed integer $x") |> throw
  end
  return nothing
end

function unpack(io::IO, ::SignedFormat, ::Rules)::Int64
  byte = read(io, UInt8)
  if byte >= 0xe0 # negative fixint
    reinterpret(Int8, byte)
  elseif byte < 128 # positive fixint
    byte
  elseif byte == 0xd0 # signed 8
    read(io, Int8)
  elseif byte == 0xd1 # signed 16
    read(io, Int16) |> ntoh
  elseif byte == 0xd2 # signed 32
    read(io, Int32) |> ntoh
  elseif byte == 0xd3 # signed 64
    read(io, Int64) |> ntoh
  # For compability, also read unsigned values when signed is expected
  elseif byte == 0xcc # unsigned 8
    read(io, UInt8)
  elseif byte == 0xcd # unsigned 16
    read(io, UInt16) |> ntoh
  elseif byte == 0xce # unsigned 32
    read(io, UInt32) |> ntoh
  elseif byte == 0xcf # unsigned 64
    read(io, UInt64) |> ntoh
  else
    byteerror(byte, SignedFormat())
  end
end

destruct(value, ::SignedFormat) = Base.signed(value)

"""
Core format for packing unsigned integer values.

Built upon the msgpack formats `positive fixint`, `unsigned 8`, `unsigned
16`, `unsigned 32`, `unsigned 64`.

## Defaults
[`UnsignedFormat`](@ref) is the default format of all subtypes of `Unsigned`. Use

    format(::Type{T}) = UnsignedFormat()

or

    @pack T in UnsignedFormat

to make [`UnsignedFormat`](@ref) the default format for type `T`. If `T` is
abstract, use `{<: T}` to cover all subtypes.

## Packing
To support packing values of type `T` in [`UnsignedFormat`](@ref), implement

    destruct(val::T, ::UnsignedFormat)::Unsigned

## Unpacking
To support unpacking values of type `T` packed in [`UnsignedFormat`](@ref), 
implement
  
    construct(::Type{T}, ::UInt64, ::UnsignedFormat)::T

or make sure that the constructor `T(::UInt64)` is defined.
"""
struct UnsignedFormat <: Format end

function isformatbyte(byte, ::UnsignedFormat)
  return byte <= 0x7f ||  # positive fixint
         0xcc <= byte <= 0xcf # unsigned 8 to 64
end

function pack(io::IO, value, ::UnsignedFormat, ::Rules)::Nothing
  x = destruct(value, UnsignedFormat())
  if x < 128 # positive fixint
    write(io, UInt8(x))
  elseif x <= typemax(UInt8) # unsigned 8
    write(io, 0xcc)
    write(io, UInt8(x))
  elseif x <= typemax(UInt16) # unsigned 16
    write(io, 0xcd)
    write(io, UInt16(x) |> hton)
  elseif x <= typemax(UInt32) # unsigned 32
    write(io, 0xce)
    write(io, UInt32(x) |> hton)
  elseif x <= typemax(UInt64) # unsigned 64
    write(io, 0xcf)
    write(io, UInt64(x) |> hton)
  else
    ArgumentError("invalid unsigned integer $x") |> throw
  end
  return nothing
end

function unpack(io::IO, ::UnsignedFormat, ::Rules)::UInt64
  byte = read(io, UInt8)
  if byte < 128 # positive fixint
    byte
  elseif byte == 0xcc # unsigned 8
    read(io, UInt8)
  elseif byte == 0xcd # unsigned 16
    read(io, UInt16) |> ntoh
  elseif byte == 0xce # unsigned 32
    read(io, UInt32) |> ntoh
  elseif byte == 0xcf # unsigned 64
    read(io, UInt64) |> ntoh
  else
    byteerror(byte, UnsignedFormat())
  end
end

destruct(x, ::UnsignedFormat) = Base.unsigned(x)

"""
Core format for packing float values.

Built upon the msgpack formats `float 32`, `float 64`.

## Defaults
[`FloatFormat`](@ref) is the default format for `Float16`, `Float32`, and
`Float64`. Use

    format(::Type{T}) = FloatFormat()

or

    @pack T in FloatFormat

to make [`FloatFormat`](@ref) the default format for type `T`. If `T` is abstract, use
`{<: T}` to cover all subtypes.

## Packing
To support packing values of type `T` in [`FloatFormat`](@ref), implement

    destruct(val::T, ::FloatFormat)::Union{Float16, Float32, Float64}

## Unpacking
To support unpacking values of type `T` packed in [`FloatFormat`](@ref), 
implement
  
    construct(::Type{T}, ::Float64, ::FloatFormat)::T

or make sure that the constructor `T(::Float64)` is defined.
"""
struct FloatFormat <: Format end

function isformatbyte(byte, ::FloatFormat)
  return byte == 0xca || byte == 0xcb
end

function pack(io::IO, value, ::FloatFormat, ::Rules)::Nothing
  val = destruct(value, FloatFormat())
  if isa(val, Float16) || isa(val, Float32) # float 32
    write(io, 0xca)
    write(io, Float32(val) |> hton)
  else # float 64
    write(io, 0xcb)
    write(io, Float64(val) |> hton)
  end
  return nothing
end

function unpack(io::IO, ::FloatFormat, ::Rules)::Float64
  byte = read(io, UInt8)
  if byte == 0xca ## float 32
    read(io, Float32) |> ntoh
  elseif byte == 0xcb # float 64
    read(io, Float64) |> ntoh
  else
    byteerror(byte, FloatFormat())
  end
end

destruct(value, ::FloatFormat) = Base.float(value)

"""
Core format for packing string values.

Built upon the msgpack formats `fixstr`, `str 8`, `str 16`, `str 32`.

## Defaults
[`StringFormat`](@ref) is the default format for `Symbol` and all subtypes of
`AbstractString`. Use

    format(:: Type{T}) = StringFormat()

or

    @pack T in StringFormat

to make [`StringFormat`](@ref) the default format for type `T`. If `T` is
abstract, use `{<: T}` to cover all subtypes.

## Packing
To support packing values of type `T` in [`StringFormat`](@ref), implement

    destruct(val::T, ::StringFormat)::R

where the returned value `ret::R` must implement `sizeof(ret)` (number of
bytes) as well as `write(io, ret)`.

## Unpacking
To support unpacking values of type `T` packed in [`StringFormat`](@ref),
implement
  
    construct(:: Type{T}, ::String, ::StringFormat)::T

or make sure that `convert(T, ::String)` is defined.
"""
struct StringFormat <: Format end

function isformatbyte(byte, ::StringFormat)
  return 0xa0 <= byte <= 0xbf || # fixstr
         0xd9 <= byte <= 0xdb # str 8 to 32
end

function pack(io::IO, value, ::StringFormat, ::Rules)::Nothing
  str = destruct(value, StringFormat())
  n = sizeof(str)
  if n < 32 # fixstr format
    write(io, 0xa0 | UInt8(n))
  elseif n <= typemax(UInt8) # str 8 format
    write(io, 0xd9)
    write(io, UInt8(n))
  elseif n <= typemax(UInt16) # str 16 format
    write(io, 0xda)
    write(io, UInt16(n) |> hton)
  elseif n <= typemax(UInt32) # str 32 format
    write(io, 0xdb)
    write(io, UInt32(n) |> hton)
  else
    ArgumentError("Invalid string length $n") |> throw
  end
  write(io, str)
  return nothing
end

function unpack(io::IO, ::StringFormat, ::Rules)::String
  byte = read(io, UInt8)
  n = if 0xa0 <= byte <= 0xbf # fixstr  format
    byte & 0x1f
  elseif byte == 0xd9 # str 8 format
    read(io, UInt8)
  elseif byte == 0xda # str 16 format
    read(io, UInt16) |> ntoh
  elseif byte == 0xdb # str 32 format
    read(io, UInt32) |> ntoh
  else
    byteerror(byte, StringFormat())
  end
  return String(read(io, n))
end

# Default destruct / construct
destruct(value, ::StringFormat) = Base.string(value)
construct(::Type{T}, x, ::StringFormat) where {T} = convert(T, x)

"""
Core format for packing binary values.

Built upon the msgpack formats `bin 8`, `bin 16`, `bin 32`.

## Defaults
Use

    format(::Type{T}) = BinaryFormat()

or

    @pack T in BinaryFormat

to make [`BinaryFormat`](@ref) the default format for type `T`. If `T` is
abstract, use `{<: T}` to cover all subtypes.

## Packing
To support packing values of type `T` in [`BinaryFormat`](@ref), implement

    destruct(val::T, ::BinaryFormat)::R

where the returned value `ret::R` must implement `sizeof(ret)` (number of
bytes) as well as `write(io, ret)`.

## Unpacking
To support unpacking values of type `T` packed in [`BinaryFormat`](@ref), 
implement
  
    construct(::Type{T}, ::Vector{UInt8}, ::BinaryFormat)::T

or make sure that the constructor `T(::Vector{UInt8})` is defined.
"""
struct BinaryFormat <: Format end

function isformatbyte(byte, ::BinaryFormat)
  return 0xc4 <= byte <= 0xc6
end

function pack(io::IO, value, ::BinaryFormat, ::Rules)::Nothing
  bin = destruct(value, BinaryFormat())
  n = sizeof(bin)
  if n <= typemax(UInt8) # bin8
    write(io, 0xc4)
    write(io, UInt8(n))
  elseif n <= typemax(UInt16) # bin16
    write(io, 0xc5)
    write(io, UInt16(n) |> hton)
  elseif n <= typemax(UInt32) # bin32
    write(io, 0xc6)
    write(io, UInt32(n) |> hton)
  else
    ArgumentError("invalid binary length $n") |> throw
  end
  write(io, bin)
  return nothing
end

function unpack(io::IO, ::BinaryFormat, ::Rules)::Vector{UInt8}
  byte = read(io, UInt8)
  n = if byte == 0xc4 # bin8
    read(io, UInt8)
  elseif byte == 0xc5 # bin16
    read(io, UInt16) |> ntoh
  elseif byte == 0xc6 # bin32
    read(io, UInt32) |> ntoh
  else
    byteerror(byte, BinaryFormat())
  end
  return read(io, n)
end

"""
Core format for packing vector values.

Built upon the msgpack formats `fixarray`, `array 16`, `array 32`.

## Defaults
[`VectorFormat`](@ref) is the default format for subtypes of `Tuple` and
`AbstractVector`. Use

    format(::Type{T}) = VectorFormat()

or

    @pack T in VectorFormat

to make [`VectorFormat`](@ref) the default format for type `T`. If `T` is
abstract, use `{<: T}` to cover all subtypes.

## Packing
To support packing values of type `T` in [`VectorFormat`](@ref), implement

    destruct(val::T, ::VectorFormat)::R

where the returned value `ret::R` must implement `Base.length(ret)` (number
of entries) and must be iterable. The formats of the entries of `val` are
determined via [`valueformat`](@ref), where `state` is the linear index.

## Unpacking
To support unpacking values of type `T` packed in [`VectorFormat`](@ref), 
implement
  
    construct(::Type{T}, values::Generator{T}, ::VectorFormat)::T

or make sure that the constructor `T(values::Generator{T})` is defined (see
[`Generator`](@ref)). The respective types and formats of the entries of `values` are determined via [`valuetype`](@ref) and [`valueformat`](@ref),
where `state` is the linear index.

!!! warning

    During construction, all entries of the generator `values` have to be
    iterated over. Since `Generator{T}` wraps a lazy map that reads from the IO
    source to be unpacked, not conducting the iteration before the next object
    is processed will interfere with unpacking of subsequent values. For the
    same reason, you should not store the object `values` and access it at a
    later time.
"""
struct VectorFormat <: AbstractVectorFormat end

function isformatbyte(byte, ::VectorFormat)
  return 0x90 <= byte <= 0x9f || # fixarray
         byte == 0xdc || # array 16
         byte == 0xdd # array 32
end

function writeheaderbytes(io::IO, val, ::VectorFormat)
  n = length(val)
  if n < 16 # fixarray
    write(io, 0x90 | UInt8(n))
  elseif n <= typemax(UInt16) # array16
    write(io, 0xdc)
    write(io, UInt16(n) |> hton)
  elseif n <= typemax(UInt32) # array32
    write(io, 0xdd)
    write(io, UInt32(n) |> hton)
  else
    ArgumentError("invalid vector length $n") |> throw
  end
end

function readheaderbytes(io::IO, fmt::VectorFormat)::Int
  byte = read(io, UInt8)
  if byte & 0xf0 == 0x90 # fixarray
    return byte & 0x0f
  elseif byte == 0xdc # array 16
    return read(io, UInt16) |> ntoh
  elseif byte == 0xdd # array 32
    return read(io, UInt32) |> ntoh
  else
    byteerror(byte, fmt)
  end
end

function pack(io::IO, value::T, fmt::VectorFormat, rules::Rules) where {T}
  val = destruct(value, fmt, rules)
  writeheaderbytes(io, val, fmt)
  for (state, entry) in enumerate(val)
    fmt_val = valueformat(T, state, fmt, rules)
    pack(io, entry, fmt_val, rules)
  end
  return nothing
end

function unpack(io::IO, ::Type{T}, fmt::VectorFormat, rules::Rules)::T where {T}
  n = readheaderbytes(io, fmt)
  entries = Iterators.map(1:n) do state
    S = valuetype(T, state, fmt, rules)
    fmt_val = valueformat(T, state, fmt, rules)
    entry = unpack(io, S, fmt_val, rules)
    return entry
  end
  return construct(T, Generator{T}(entries), fmt, rules)
end

# Support for generic unpacking / AnyFormat
function unpack(io::IO, ::VectorFormat, rules::Rules)::Vector
  n = readheaderbytes(io, VectorFormat())
  values = map(1:n) do _
    return unpack(io, AnyFormat(), rules)
  end
  return values
end


"""
Core format for packing map / dictionary values.

Built upon the msgpack formats `fixmap`, `map 16`, `map 32`.

## Defaults
[`MapFormat`](@ref) is the default format for subtypes of `NamedTuple` and `Dict`. Use

    format(::Type{T}) = MapFormat()

or

    @pack T in MapFormat

to make [`MapFormat`](@ref) the default format for type `T`. If `T` is abstract,
use `{<: T}` to cover all subtypes.

## Packing
To support packing values of type `T` in [`MapFormat`](@ref), implement

    destruct(val::T, ::MapFormat)::R

where the returned value `ret::R` must implement `Base.length(ret)` (number of
entries) and must be iterable with key-value pairs as entries. The key / value
formats of the entries of `val` are determined via [`keyformat`](@ref) and
[`valueformat`](@ref), where `state` is the linear index.

## Unpacking
To support unpacking values of type `T` packed in [`MapFormat`](@ref), 
implement
  
    construct(::Type{T}, pairs::Generator{T}, ::MapFormat)::T

or make sure that the constructor `T(pairs::Generator{T})` is defined (see
[`Generator`](@ref)), where `pairs` will contain key-value pairs as
entries. The respective types and formats of the keys and values are determined
during unpacking via [`keytype`](@ref), [`valuetype`](@ref), [`keyformat`](@ref)
and [`valueformat`](@ref), where `state` is the linear index.

!!! warning

    During construction, all entries of the generator `pairs` have to be
    iterated over. Since `Generator{T}` wraps a lazy map that reads from the
    IO source to be unpacked, not conducting the iteration before the next
    object is processed will interfere with unpacking of subsequent values. For
    the same reason, you should not store the object `pairs` and access it at a
    later time.
"""
struct MapFormat <: AbstractMapFormat end

function isformatbyte(byte, ::MapFormat)
  return 0x80 <= byte <= 0x8f || # fixmap
         byte == 0xde || # map 16
         byte == 0xdf # map 32
end

function writeheaderbytes(io::IO, val, ::MapFormat)
  n = length(val)
  if n < 16 # fixmap
    write(io, 0x80 | UInt8(n))
  elseif n <= typemax(UInt16) # map 16
    write(io, 0xde)
    write(io, UInt16(n) |> hton)
  elseif n <= typemax(UInt32) # map 32
    write(io, 0xdf)
    write(io, UInt32(n) |> hton)
  else
    ArgumentError("invalid map length $n") |> throw
  end
end

function readheaderbytes(io::IO, fmt::MapFormat)::Int
  byte = read(io, UInt8)
  if byte & 0xf0 == 0x80
    return byte & 0x0f
  elseif byte == 0xde
    return read(io, UInt16) |> ntoh
  elseif byte == 0xdf
    return read(io, UInt32) |> ntoh
  else
    byteerror(byte, fmt)
  end
end

function pack(io::IO, value::T, fmt::MapFormat, rules::Rules) where {T}
  pairs = destruct(value, fmt, rules)
  writeheaderbytes(io, pairs, fmt)
  for (state, pair) in enumerate(pairs)
    fmt_key = keyformat(T, state, fmt, rules)
    fmt_val = valueformat(T, state, fmt, rules)
    pack(io, first(pair), fmt_key, rules)
    pack(io, last(pair), fmt_val, rules)
  end
  return
end

function unpack(io::IO, ::Type{T}, fmt::MapFormat, rules::Rules)::T where {T}
  n = readheaderbytes(io, fmt)
  pairs = Iterators.map(1:n) do state
    K = keytype(T, state, fmt, rules)
    V = valuetype(T, state, fmt, rules)
    fmt_key = keyformat(T, state, fmt, rules)
    fmt_val = valueformat(T, state, fmt, rules)
    key = unpack(io, K, fmt_key, rules)
    value = unpack(io, V, fmt_val, rules)
    return key=>value
  end
  return construct(T, Generator{T}(pairs), fmt, rules)
end

# Support for generic unpacking / AnyFormat
function unpack(io::IO, ::MapFormat, rules::Rules)::Dict
  n = readheaderbytes(io, MapFormat())
  pairs = Iterators.map(1:n) do _
    key = unpack(io, AnyFormat(), rules)
    value = unpack(io, AnyFormat(), rules)
    return (key, value)
  end
  return Dict(pairs)
end
