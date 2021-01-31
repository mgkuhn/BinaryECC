#D is the degree of the reduction polynomial
#R is the reduction polynomial without the x^D term
"""
    FieldPoint{D,R}
Represents a point in the binary field which has order ``2^D`` and reduction polynomial

``x^D + x^{r_n} + \\cdots + x^{r_0}``

where ``R = r_n r_{n-1}\\ldots r_1 r_0`` in binary.

Types for points in the standard fields (taken from SEC 2, table 3)
 are available:
- FieldPoint113
- FieldPoint131
- FieldPoint163
- FieldPoint193
- FieldPoint233
- FieldPoint239
- FieldPoint283
- FieldPoint409
- FieldPoint571
"""
struct FieldPoint{D,R}
    value::StaticUInt
    FieldPoint{D,R}(value::Integer) where {D,R} = new(StaticUInt{ceil(Int,D/@wordsize()),@wordtype()}(value))
    FieldPoint{D,R}(value::StaticUInt) where {D,R} = new(value)
end

"""
    FieldPoint{D,R}(s::String) where {D,R}
Using the procedure set out in SEC 1 (version 2) 2.3.6,
this converts a hex string to a field element.
"""
function FieldPoint{D,R}(s::String) where {D,R}
    s = replace(s, " " => "")
    if length(s)!=ceil(D / 8)*2 throw(ArgumentError("Octet string is of the incorrect length for this field.")) end
    value = StaticUInt{ceil(Int,D/@wordsize()),@wordtype()}(s)
    return FieldPoint{D,R}(value)
end


"""
    ==(a::FieldPoint{D,R}, b::FieldPoint{D,R}) where {D,R}
Returns true if the points ``a`` and ``b`` from the same field are equal,
 and false otherwise.
"""
function ==(a::FieldPoint{D,R}, b::FieldPoint{D,R})::Bool where {D,R}
    return a.value==b.value
end

"""
    +(a::FieldPoint{D,R}, b::FieldPoint{D,R}) where {D,R}
Returns a new element (of the binary field represented by {D,R}) which is the result of ``a+b``.
"""
function +(a::FieldPoint{D,R}, b::FieldPoint{D,R})::FieldPoint{D,R} where {D,R}
    return FieldPoint{D,R}(a.value ⊻ b.value)
end

"""
    -(a::FieldPoint{D,R}, b::FieldPoint{D,R}) where {D,R}
Returns a new element (of the binary field represented by {D,R}) which is the result of ``a-b``.
"""
function -(a::FieldPoint{D,R}, b::FieldPoint{D,R})::FieldPoint{D,R} where {D,R}
    return a+b
end

function -(a::FieldPoint{D,R})::FieldPoint{D,R} where {D,R}
    return copy(a)
end

#note: this is the standard algorithm, but faster specialised versions of it are
#available for each of the standard fields (in Field_fastreduce.jl)
"""
    reduce(a::FieldPoint{D,R}) where {D,R}
Returns the least element ``b``, such that ``a \\equiv b \\pmod{R}``.
"""
function reduce(a::FieldPoint{D,R})::FieldPoint{D,R} where {D,R}
    #b will should always be such that a ≡ b (mod R)
    #the loop will modify it until it reaches the smallest value that makes that true
    b = copy(a.value)
    r = StaticUInt{128÷@wordsize(),@wordtype()}(R)

    #iterate over the excess bits of a, left to right
    for i in (length(b)*@wordsize()-1):-1:D
        if getbit(b, i)==1
            flipbit!(b, i)
            shiftedxor!(b, r, i-D)
        end
    end

    #remove excess blocks from b
    b = changelength(b, ceil(Int,D/@wordsize()))
    return FieldPoint{D,R}(b)
end

"""
    *(a::FieldPoint{D,R}, b::FieldPoint{D,R}) where {D,R}
Returns a new element (of the binary field represented by {D,R}) which is the
 result of ``a \\cdot b``.
"""
function *(a::FieldPoint{D,R}, b::FieldPoint{D,R})::FieldPoint{D,R} where {D,R}
    return window_comb_mult(a, b, 4)
end

"""
    right_to_left_mult(a::FieldPoint{D,R}, b::FieldPoint{D,R}) where {D,R}
Returns ``a \\cdot b`` using the right to left shift and add method.
"""
function right_to_left_mult(a::FieldPoint{D,R}, b::FieldPoint{D,R})::FieldPoint{D,R} where {D,R}
    if a.value==b.value return square(a) end

    #c needs to store a polynomial of degree 2D
    c = zero(StaticUInt{ceil(Int,2*D/@wordsize()),@wordtype()})

    for i in 0:(D-1)
        if getbit(a.value,i)==1
            shiftedxor!(c, b.value, i)
        end
    end

    return reduce(FieldPoint{D,R}(c))
end

"""
    threads_mult(a::FieldPoint{D,R}, b::FieldPoint{D,R}) where {D,R}
Returns ``a \\cdot b`` using the right to left shift and add method with multithreading.
"""
function threads_mult(a::FieldPoint{D,R}, b::FieldPoint{D,R})::FieldPoint{D,R} where {D,R}
    if a.value==b.value return square(a) end

    #cs needs to store polynomials of degree 2D
    cs = [zero(StaticUInt{ceil(Int,2*D/@wordsize()),@wordtype()}) for i=1:Threads.nthreads()]

    Threads.@threads for i in 0:(D-1)
        if getbit(a.value,i)==1
            t = Threads.threadid()
            cs[t] = shiftedxor(cs[t], b.value, i)
        end
    end

    return reduce(FieldPoint{D,R}(Base.reduce(⊻,cs)))
end

"""
    noreduce_mult(a::FieldPoint{D,R}, b::FieldPoint{D,R}) where {D,R}
Returns ``a \\cdot b`` using the right to left shift and add method,
without needing to call a reduction function.
"""
function noreduce_mult(a::FieldPoint{D,R}, b::FieldPoint{D,R})::FieldPoint{D,R} where {D,R}
    if a.value==b.value return square(a) end

    L = ceil(Int,D/@wordsize())
    shiftedb::StaticUInt{L,@wordtype()} = copy(b.value)
    c = zero(StaticUInt{L,@wordtype()})
    r = StaticUInt{128÷@wordsize(),@wordtype()}(R)

    for i in 0:(D-1)
        if getbit(a.value,i)==1
            xor!(c, shiftedb)
        end
        leftshift!(shiftedb, 1)
        if getbit(shiftedb, D)==1
            flipbit!(shiftedb, D)
            xor!(shiftedb, r)
        end
    end

    return FieldPoint{D,R}(c)
end

"""
    right_to_left_comb_mult(a::FieldPoint{D,R}, b::FieldPoint{D,R}) where {D,R}
Returns ``a \\cdot b`` using a right to left comb method
(described in Guide to Elliptic Curve Cryptography, algorithm 2.34).
"""
function right_to_left_comb_mult(a::FieldPoint{D,R}, b::FieldPoint{D,R})::FieldPoint{D,R} where {D,R}
    if a.value==b.value return square(a) end

    L = ceil(Int,D/@wordsize())

    #c needs to store polynomials of degree 2D
    c = zero(StaticUInt{2*L,@wordtype()})

    #b needs to store polynomials of degree D+wordsize
    bvalue = changelength(b.value, L+1)

    for k in 0:(@wordsize()-1)
        for j in 0:(L-1)
            if getbit(a.value, j*@wordsize() + k)==1
                shiftedxor!(c, bvalue, j*@wordsize())
            end
        end
        if k!=(@wordsize()-1) leftshift!(bvalue,1) end
    end

    return reduce(FieldPoint{D,R}(c))
end

"""
    left_to_right_comb_mult(a::FieldPoint{D,R}, b::FieldPoint{D,R}) where {D,R}
Returns ``a \\cdot b`` using a left to right comb method
(described in Guide to Elliptic Curve Cryptography, algorithm 2.35).
"""
function left_to_right_comb_mult(a::FieldPoint{D,R}, b::FieldPoint{D,R})::FieldPoint{D,R} where {D,R}
    if a.value==b.value return square(a) end

    L = ceil(Int,D/@wordsize())
    c = zero(StaticUInt{2*L,@wordtype()})

    for k in (@wordsize()-1):-1:0
        for j in 0:(L-1)
            if getbit(a.value, @wordsize()*j + k)==1
                shiftedxor!(c, b.value, j*@wordsize())
            end
        end
        if k!=0 leftshift!(c,1) end
    end

    return reduce(FieldPoint{D,R}(c))
end

"""
    window_comb_mult(a::FieldPoint{D,R}, b::FieldPoint{D,R}, window::Int) where {D,R}
Returns ``a \\cdot b`` using a left to right comb method windowing
(described in Guide to Elliptic Curve Cryptography, algorithm 2.36).

Performs best with a window size of 4.
"""
function window_comb_mult(a::FieldPoint{D,R}, b::FieldPoint{D,R}, window::Int)::FieldPoint{D,R} where {D,R}
    L = ceil(Int,D/@wordsize())
    Bu = [small_mult(b, u) for u=0:(1<<window -1)]
    c = zero(StaticUInt{2*L,@wordtype()})

    for k in ((@wordsize()÷window)-1):-1:0
        for j in 0:(length(a.value)-1)
            u = getbits(a.value, window*k + @wordsize()*j, window)
            shiftedxor!(c, Bu[u+1], j*@wordsize())
        end
        if k!=0
            leftshift!(c, window)
        end
    end

    return reduce(FieldPoint{D,R}(c))
end

#used for window_comb_mult
function small_mult(a::FieldPoint{D,R}, b::Int)::StaticUInt where {D,R}
    blen = 8*sizeof(b)
    maxlen = D + blen
    c = zero(StaticUInt{ceil(Int,maxlen/@wordsize()),@wordtype()})

    for i in 0:(blen-1)
        if (b>>i)&1==1
            shiftedxor!(c, a.value, i)
        end
    end

    return c
end

"""
    square(a::FieldPoint{D,R}) where {D,R}
Returns a new element (of the binary field represented by {D,R}) which is the
result of ``a^2``.
"""
function square(a::FieldPoint{D,R})::FieldPoint{D,R} where {D,R}
    return window_square(a, 4)
end

#adds a zero between every digit of the original
function standard_square(a::FieldPoint{D,R})::FieldPoint{D,R} where {D,R}
    b = zero(StaticUInt{ceil(Int,2*D/@wordsize()),@wordtype()})
    for i in 0:(D-1)
        if getbit(a.value,i)==1
            flipbit!(b, i*2)
        end
    end

    return reduce(FieldPoint{D,R}(b))
end

"""
    window_square(a::FieldPoint{D,R}, window::Int) where {D,R}
Returns ``a^2`` by inserting a zero between every bit in the original, using
the specified window size.
"""
function window_square(a::FieldPoint{D,R}, window::Int)::FieldPoint{D,R} where {D,R}
    b = zero(StaticUInt{ceil(Int,2*D/@wordsize()),@wordtype()})
    spread = [StaticUInt{1,@wordtype()}(spread_bits(i)) for i=0:(1<<window -1)]

    for i in 0:window:D-1
        u = getbits(a.value, i, window)
        shiftedxor!(b, spread[u+1], i*2)
    end

    return reduce(FieldPoint{D,R}(b))
end

#needed for window_square
function spread_bits(a::Int)::Int
    b = 0
    for i in 0:bits(a)
        if (a>>i)&1==1
            b ⊻= 1<<(2*i)
        end
    end
    return b
end

#uses a version of egcd to invert a
#Algorithm 2.48, Guide to Elliptic Curve Cryptography
"""
    inv(a::FieldPoint{D,R}) where {D,R}
Returns a new element ``b`` such that ``a b ≡ 1 \\pmod{f_R(x)}``
 (where ``f_R(x)`` is the reduction polynomial for the field).
"""
function inv(a::FieldPoint{D,R})::FieldPoint{D,R} where {D,R}
    if iszero(a.value) throw(DivideError()) end

    L = ceil(Int,D/@wordsize())
    u = a.value
    v = StaticUInt{L,@wordtype()}(R)
    flipbit!(v, D)
    g1 = one(StaticUInt{L,@wordtype()})
    g2 = zero(StaticUInt{L,@wordtype()})

    while !isone(u)
        j = bits(u) - bits(v)
        if j<0
            u, v = v, u
            g1, g2 = g2, g1
            j = -j
        end
        u = shiftedxor(u, v, j)
        g1 = shiftedxor(g1, g2, j)
    end
    return FieldPoint{D,R}(g1)
end

"""
    /(a::FieldPoint{D,R}, b::FieldPoint{D,R}) where {D,R}
Returns a new element (of the binary field represented by {D,R}) which is the
result of ``\\frac{a}{b}``.
"""
function /(a::FieldPoint{D,R}, b::FieldPoint{D,R})::FieldPoint{D,R} where {D,R}
    return a * inv(b)
end

#right to left, square and multiply method
"""
    ^(a::FieldPoint{D,R}, b::Integer) where {D,R}
Returns a new element (of the binary field represented by {D,R}) which is the
result of ``a^b``.
"""
function ^(a::FieldPoint{D,R}, b::Integer)::FieldPoint{D,R} where {D,R}
    c = one(typeof(a))
    squaring = a

    while b>0
        if b & 1 == 1
            c *= squaring
        end
        squaring *= squaring
        b >>>= 1
    end

    return c
end

"""
    random(::Type{FieldPoint{D,R}}) where {D,R}
Returns a random element of the specified field.
"""
function random(::Type{FieldPoint{D,R}})::FieldPoint{D,R} where {D,R}
    return FieldPoint{D,R}(random(StaticUInt{ceil(Int,D/@wordsize()),@wordtype()}, D-1))
end

"""
    iszero(a::FieldPoint)
Returns true if ``a`` is the zero element of the field represented by D and R,
 and false otherwise.
"""
function iszero(a::FieldPoint)::Bool
    return iszero(a.value)
end

"""
    zero(::Type{FieldPoint{D,R}}) where {D,R}
Returns the zero element of the specified field.
"""
function zero(::Type{FieldPoint{D,R}})::FieldPoint{D,R} where {D,R}
    return FieldPoint{D,R}(zero(StaticUInt{ceil(Int,D/@wordsize()),@wordtype()}))
end

"""
    isone(a::FieldPoint)
Returns true if ``a`` is equal to one, and false otherwise.
"""
function isone(a::FieldPoint)::Bool
    return isone(a.value)
end

"""
    one(::Type{FieldPoint{D,R}}) where {D,R}
Returns element 1 of the specified field.
"""
function one(::Type{FieldPoint{D,R}})::FieldPoint{D,R} where {D,R}
    return FieldPoint{D,R}(one(StaticUInt{ceil(Int,D/@wordsize()),@wordtype()}))
end

"""
    sqrt(a::FieldPoint{D,R}) where {D,R}
Returns ``b`` such that ``b^2 ≡ a \\pmod(R)``.
"""
function sqrt(a::FieldPoint{D,R})::FieldPoint{D,R} where {D,R}
    #a^{2^{D-1}}
    for i in 1:(D-1)
        a *= a
    end
    return a
end

"""
    convert(::Type{BigInt}, a::FieldPoint)
Converts the given field point to a number (of type BigInt), following the procedure
 set out in SEC 1 (version 2) 2.3.9.
"""
function convert(::Type{BigInt}, a::FieldPoint)::BigInt
    return convert(BigInt, a.value)
end

#sec2 v2 (and v1), table 3:
FieldPoint113 = FieldPoint{113, UInt16(512+1)} #v1 only
FieldPoint131 = FieldPoint{131, UInt16(256+8+4+1)} #v1 only
FieldPoint163 = FieldPoint{163, UInt16(128+64+8+1)}
FieldPoint193 = FieldPoint{193, (UInt16(1)<<15) + UInt16(1)} #v1 only
FieldPoint233 = FieldPoint{233, (UInt128(1)<<74) + UInt128(1)}
FieldPoint239 = FieldPoint{239, (UInt64(1)<<36) + UInt64(1)}
FieldPoint283 = FieldPoint{283, (UInt16(1)<<12) + UInt16(128+32+1)}
FieldPoint409 = FieldPoint{409, (UInt128(1)<<87) + UInt128(1)}
FieldPoint571 = FieldPoint{571, (UInt16(1)<<10) + UInt16(32+4+1)}
