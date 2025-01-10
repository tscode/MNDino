
"""
    insert_rules!(ex, rex)

Add the trailing argument `::\$rex` to all toplevel function definitions in
the expression `ex`.
"""
inject_rules!(ex, ::Nothing) = nothing

function inject_rules!(ex, rex)
  if ex isa Expr
    if ex.head == :function
      if ex.args[1] isa Expr && ex.args[1].head == :where
        arguments = ex.args[1].args[1].args
      else
        arguments = ex.args[1].args
      end
      push!(arguments, Expr(:(::), rex))
    else
      foreach(arg -> inject_rules!(arg, rex), ex.args)
    end
  end
  return
end

"""
    insert_constraint!(ex, cex)

Add the where clause `where {\$cex}` to all toplevel function definitions
in `ex`.
"""
inject_constraint!(_, ::Nothing) = nothing

function inject_constraint!(ex, cex)
  if ex isa Expr
    if ex.head == :function
      if ex.args[1] isa Expr && ex.args[1].head == :where
        push!(ex.args[1].args, cex)
      else
        ex.args[1] = Expr(:where, ex.args[1], cex)
      end
    else
      foreach(arg -> inject_constraint!(arg, cex), ex.args)
    end
  end
  return
end


"""
    is_type_expr(ex)

Check weather the symbol or expression `ex` is a plausible type expression.

Allowed expressions are, for example, `A` (Symbol), `A.B`, or `A.B{C, D, E.F}`.
"""
function is_type_expr(ex, curly = true)
  if ex isa Symbol
    # T
    true
  elseif ex.head == :curly && curly
    # T{F, ...}
    # We are lenient here, because a precise specification of possible types
    # with arbitrary type parameters is hard
    true
  elseif ex.head == :.
    # A.T
    all(ex.args) do ex
      ex isa QuoteNode ? ex.value isa Symbol : is_type_expr(ex, false)
    end
  else
    false
  end
end

"""
    parse_rules_expr(ex)

Check if `ex` can be understood as rules expression and return it if it can.
"""
function parse_rules_expr(ex)
  return is_type_expr(ex) ? ex : nothing
end


"""
    parse_typetarget_expr(ex)

Parse the type target expression of the [`@pack`](@ref) macro.

A type target is either
- just a type expression `T`. Then `(type = :T, constraint = nothing)` is returned.
- a subtype selection `{S <: T}`. Then `(type = :S, constraint = :({S <: T}))` is returned.
- an anonymous subtype selection `{<: T}`. Then `(var = S, constraint = :({\$S <: T}))` is returned, where `S` is a generated symbol.

Returns `nothing` if parsing was unsuccessful.
"""
function parse_typetarget_expr(ex)
  len = ex isa Symbol ? 0 : length(ex.args)
  if is_type_expr(ex)
    # T
    return (type = ex, constraint = nothing)
    
  elseif len == 1 && ex.head == :braces
    ex = ex.args[1]
    len = ex isa Symbol ? 0 : length(ex.args)

    if len == 1 &&
       ex.head == :(<:) &&
       is_type_expr(ex.args[1])

      # {<: T}
      S = gensym(:S)
      pushfirst!(ex.args, S)
      return (type = S, constraint = ex)

    elseif len == 2 &&
           ex.head == :(<:) &&
           ex.args[1] isa Symbol &&
           is_type_expr(ex.args[2])

      # {S <: T}
      S = ex.args[1]
      return (type = S, constraint = ex)

    end
  end  
  return nothing
end

"""
    parse_informat_expr(ex)

Parse an expression of the form `T in F`, where `T` is a valid type target (see
[`parse_typetarget_expr`](@ref)) and `F` is a type expression that corresponds
to a format.
"""
function parse_informat_expr(ex)
  if !(ex isa Expr) || ex.head != :call
    return
  end
  len = length(ex.args)
  if len == 3 && ex.args[1] in [:in, :(=>)]
    target = parse_typetarget_expr(ex.args[2])
    format = parse_typetarget_expr(ex.args[3])
    if !isnothing(target) && !isnothing(format) && isnothing(format.constraint)
      return (; target, format = format.type)
    end
  end
  return nothing
end

function code_informat(target, format)
  return quote 
    function Pack.format(::Type{$(target.type)})
      return $format() 
    end
  end
end

"""
    parse_constructor_expr(ex)

Parse a constructor expression of the form `(a, b, ... ; c, d, ...)` or
`C(a, b, ...; c, d, ...)`.

Returns the named triple `(names = (a, b, ...), kwnames = (c, d, ...), and
constructor = :C)`. In a constructor-less expression, `constructor = nothing`.
"""
function parse_constructor_expr(ex)
  if !(ex isa Expr)
    return
  end
  if ex.head == :tuple
    # (a, b, ...; c, d...)
    constructor = nothing # no constructor expression
    if ex.args[1] isa Expr && ex.args[1].head == :parameters
      # (a, b, ...; c, d...)
      names = ex.args[2:end]
      kwnames = ex.args[1].args
    else
      # (a, b, ...)
      names = ex.args
      kwnames = Symbol[]
    end
  elseif ex.head == :block && length(ex.args) == 3
    # (a; b) (is not parsed as tuple and thus is extra case)
    constructor = nothing 
    names = [ex.args[1]]
    kwnames = [ex.args[3]]
  elseif ex.head == :call && ex.args[1] != :in
    # C(a, b, ...; c, d, ...) 
    constructor = ex.args[1]
    if ex.args[2] isa Expr && ex.args[2].head == :parameters
      # C(a, b, ...; c, d, ...)
      names = ex.args[3:end]
      kwnames = ex.args[2].args
    else
      names = ex.args[2:end]
      kwnames = Symbol[]
    end
  else
    return
  end
  # Make sure names and kwnames are actually lists of symbols
  if all(isa.(names, Symbol)) && all(isa.(kwnames, Symbol))
    names = Symbol[name for name in names]
    kwnames = Symbol[name for name in kwnames]
    return (; names, kwnames, constructor)
  end
  return
end

function code_constructor(target, names, kwnames, constructor)
  symbols = (names..., kwnames...)
  constructor = isnothing(constructor) ? target.type : constructor
  len = length(names)
  lenkw = length(kwnames)

  return quote
    function Pack.destruct(val::$(target.type), fmt::Pack.AbstractStructFormat)
      Iterators.map($symbols) do name
        name=>getfield(val, name)
      end
    end

    function Pack.construct(::Type{$(target.type)}, pairs::Vector, fmt::Pack.AbstractStructFormat)
      if length(pairs) != length($symbols) 
        unpackerror("Inconsistent number of arguments during unpacking.")
      end
      args = Iterators.map(last, @view(pairs[1:$len]))
      kwargs = @view(pairs[$len+1:end])
      $constructor(args...; kwargs...)
    end

    function Pack.construct(::Type{$(target.type)}, pairs::Tuple, fmt::Pack.AbstractStructFormat)
      if length(pairs) != length($symbols) 
        unpackerror("Inconsistent number of arguments during unpacking.")
      end
      args = map(last, pairs[1:$len])
      kwargs = pairs[$len+1:end]
      $constructor(args...; kwargs...)
    end
  end
end

"""
    parse_fieldformat_expr(ex)

Parse a single field format expression of the form `a in F` or `(a, b, ...)
in F`.

Returns a vector of pairs `[a=>F, b=>F, ...]`.
"""
function parse_fieldformat_expr(ex)
  len = ex isa Symbol ? 0 : length(ex.args)
  if len == 3 && ex.args[1] in [:in, :(=>)]
    fieldexpr = ex.args[2]
    if fieldexpr isa Symbol
      fields = [fieldexpr]
    elseif fieldexpr isa Expr &&
       fieldexpr.head == :tuple &&
       all(isa.(fieldexpr.args, Symbol))
      fields = fieldexpr.args
    else
      return
    end
    format = parse_typetarget_expr(ex.args[3])
    if !isnothing(format) && isnothing(format.constraint)
      return [field => format.type for field in fields]
    end
  end
  return
end

"""
    parse_fieldformats_expr(ex)

Parse a field format expression of the form `[a in Fa, b in Fb, ...]`, where `a`
and `b` correspond to keys and `Fa`, `Fb` to format types.
"""
function parse_fieldformats_expr(ex)
  if ex isa Expr && ex.head == :vect
    if isempty(ex.args)
      pairs = []
    else
      pairs = mapreduce(vcat, ex.args) do arg
        parse_fieldformat_expr(arg)
      end
    end
    return Dict(pairs)
  end
  return nothing
end

function code_fieldformats(target, fieldnames, formats)
  if isnothing(fieldnames)
    fieldnames = :(Base.fieldnames($(target.type)))
  end
  return quote
    function Pack.fieldnames(::Type{$(target.type)}, ::Pack.AbstractStructFormat)
      return $fieldnames
    end

    function Pack.fieldtypes(::Type{$(target.type)}, fmt::Pack.AbstractStructFormat)
      names = Pack.fieldnames($(target.type), fmt)
      return map(key -> Base.fieldtype($(target.type), key), names)
    end

    @generated function Pack.fieldformats(::Type{$(target.type)}, ::F) where {F <: Pack.AbstractStructFormat}
      names = Pack.fieldnames($(target.type), F())
      fexprs = map(names) do key
        F = Base.get($formats, key, :(Pack.DefaultFormat))
        Expr(:call, F)
      end
      formats = Expr(:tuple, fexprs...)
      return formats
    end
  end
end

"""
    consume_rules_argument(args)

Try to consume an optional rules type argument for the [`@pack`](@ref) macro.
Returns the consumed rule (if any) and the remaining arguments.
"""
function consume_rules_argument(args)
  if is_type_expr(args[1])
    args[1], args[2:end]
  else
    nothing, args
  end
end

"""
    consume_argument(f, args)

Try to consume an argument via the parsing function `f`. Returns the  output of
`f` (if any) and the remaining arguments.
"""
function consume_argument(f, args)
  if isempty(args)
    return (nothing, args)
  end
  ret = f(args[1])
  if isnothing(ret)
    return (nothing, args)
  else
    return (ret, args[2:end])
  end
end

function parse_packmacro_arguments(args)
  rules, args = consume_rules_argument(args)
  @assert !isempty(args) "Format argument is missing in @pack macro."
  informat, args = consume_argument(parse_informat_expr, args)
  @assert !isnothing(informat) "Macro format expression cannot be parsed."
  cons, args = consume_argument(parse_constructor_expr, args)
  formats, args = consume_argument(parse_fieldformats_expr, args)
  @assert isempty(args) "Invalid macro arguments: $args"
  return (;
    rules,
    informat,
    cons,
    formats,
  )
end

"""
    @pack T in F
    @pack {<: T} in F

Convenience syntax for `Pack.format(::Type{T}) = F()` respectively
`Pack.format(::Type{<: T}) = F()`.

---

    @pack R T in F
    @pack R {<: T} in F

Convenience syntax for `Pack.format(::Type{T}, R()) = F()` respectively `Pack.format(::Type{<: T}) = F()`. 

---

    @pack R informat (constructor args...) [field formats...]

Generic packing macro for struct formats.

The first expression `R <: Rules` is optional.
The definitions enacted by the macro will be restricted to the rules
object `R()`.

The second expression `informat` can be an expression of the form `T in F` or
`{<: T} in F` for a user specified type `T` and a given
format type `F <: Format`.

The (optional) constructor expression can take one of the forms

- `(a, ...; b, ...)`, which implies a constructor `T(val_a, ...; c = val_c, ...)`
  respectively `S(val_a, ...; c = val_c, ...)` where `{S <: T}` denotes a concrete
  subtype of `T`. The entries `a, b, ...` are expected to correspond to
  valid fieldnames of `T` (respectively `S`).
- `A(a, ...; b, ...)` for a custom constructor object / function `A`. Note that this call to `A` must return an object of type `T` (respectively `S`).

The (optional) field format expression is of the form `[a => Fa, b => Fb, ...]`,
where `a, b, ...` denote fieldnames and `Fa, Fb, ...` the corresponding field
format. For convenience, it is also possible to specify one format `F` for
several keys `a, b, ...` via the syntax `[(a, b, ...) in F]`.

!!! warning

    The constructor and field format customizations that this macro offers
    are only effectful for `StructFormat` and `UnorderedStructFormat`. Thus,
    it only works as intended if the specified format `F` is built upon one of these formats
    (e.g., `F = StructFormat` or `F = TypedFormat{UnorderedStructFormat}`).

## Examples

```julia
using Pack

struct A
  a :: Int
  b :: Vector{Float64}
  c :: Vector{Float64}
end

A(a, b) = A(a, b, rand(5))

@pack A in StructFormat (a, b) [b in BinVectorFormat]

A(a, b; c) = A(a, b, c)

@pack A in StructFormat (a, b; c) [(b, c) in BinVectorFormat]

myA(a) = A(a, [], [])

@pack A in StructFormat myA(a)
```
"""
macro pack(args...)
  r = parse_packmacro_arguments(args)
  
  target = r.informat.target
  format = r.informat.format
  statements = [code_informat(target, format).args...]

  if !isnothing(r.cons)
    names = r.cons.names
    kwnames = r.cons.kwnames
    constructor = r.cons.constructor
    block = code_constructor(target, names, kwnames, constructor)
    append!(statements, block.args)
  end

  if !isnothing(r.formats)
    if isnothing(r.cons)
      fieldnames = nothing
    else
      fieldnames = (r.cons.names..., r.cons.kwnames...)
    end
    block = code_fieldformats(target, fieldnames, r.formats)
    append!(statements, block.args)
  end
  
  block = Expr(:block, statements...)
  inject_rules!(block, r.rules)
  inject_constraint!(block, target.constraint)
  return esc(block)
end
