module Pack

# Pack currently uses the scoped values Pack.scope and Pack.whitelist
using Base.ScopedValues

# Interface and abstract type definitions
include("pack.jl")

# Auxiliary type for unpacking msgpack vector / map formats
include("generator.jl")

# Supported packing formats
include("coreformats.jl")
include("anyformat.jl")
include("dynamicformats.jl")
include("structformat.jl")
include("arrayformats.jl")
include("typedformat.jl")

# Supported julia types
include("basetypes.jl")

# Convenience @pack macro for structs
include("macro.jl")

export Format,
       DefaultFormat,
       AnyFormat,
       NilFormat,
       BoolFormat,
       SignedFormat,
       UnsignedFormat,
       StringFormat,
       BinaryFormat,
       AbstractVectorFormat,
       VectorFormat,
       DynamicVectorFormat,
       AbstractMapFormat,
       MapFormat,
       DynamicMapFormat,
       StructFormat,
       UnorderedStructFormat,
       ArrayFormat,
       BinVectorFormat,
       BinArrayFormat,
       TypedFormat

public Rules

public pack, unpack, construct, destruct, valuetype, valueformat, keytype, keyformat, fieldtypes, fieldnames, fieldformats
       
public whitelist, rules

end # module Pack
