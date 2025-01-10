
"""
Convenience format to unpack generic msgpack values.

Note that custom rules implemented via a [`Rules`](@ref) singleton are ignored
by [`AnyFormat`](@ref).

!!! note

    msgpack extensions and the date format are currently not supported by
    [`AnyFormat`](@ref).
"""
struct AnyFormat <: Format end

"""
    peekformat(io)

Peek at `io` and return the [`Format`](@ref) that best fits the detected msgpack
format.
"""
function peekformat(io)
  byte = peek(io)
  if isformatbyte(byte, NilFormat())
    NilFormat()
  elseif isformatbyte(byte, BoolFormat())
    BoolFormat()
  elseif isformatbyte(byte, SignedFormat())
    SignedFormat()
  elseif isformatbyte(byte, UnsignedFormat())
    UnsignedFormat()
  elseif isformatbyte(byte, FloatFormat())
    FloatFormat()
  elseif isformatbyte(byte, StringFormat())
    StringFormat()
  elseif isformatbyte(byte, BinaryFormat())
    BinaryFormat()
  elseif isformatbyte(byte, VectorFormat())
    VectorFormat()
  elseif isformatbyte(byte, MapFormat())
    MapFormat()
  else
    byteerror(byte, AnyFormat())
  end
end

pack(io::IO, value, ::AnyFormat) = pack(io, value)

function unpack(io::IO, ::AnyFormat, rules::Rules = FallbackRules())
  fmt = peekformat(io)
  # Non-default rules are ignored for AnyFormat
  return unpack(io, fmt, FallbackRules())
end

