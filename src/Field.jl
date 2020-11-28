import Base: +, -, *, /, ^, ==, !=, repr, inv, log2, floor, rand

struct FieldMismatchException <: Exception end

struct Field
    order::Int16 #the order of the field
    reduction::BigInt #the reduction polynomial
    Field(m::Number, f::Number) = new(convert(Int16, m), convert(BigInt, f))
end

struct FieldPoint
    x::BigInt
    field::Field
    FieldPoint(x::Number, m::Number, f::Number) =
        FieldPoint(convert(BigInt, x), Field(m, f))
    FieldPoint(x::Number, field::Field) = new(convert(BigInt, x), field)
end

function copy(f::Field)
    return Field(f.order, f.reduction)
end

function copy(a::FieldPoint)
    return FieldPoint(a.x, a.field)
end

function repr(f::Field)
    return "Order: "*repr(f.order)*"\nReduction: "*repr(f.reduction)
end

function repr(a::FieldPoint)
    res = ""
    i = 0
    val = a.x
    while val > 0
        if val & BigInt(1) > BigInt(0)
            if i==0
                res = "1"
            elseif res==""
                res = "x^"*repr(i)
            else
                res = "x^"*repr(i)*" + "*res
            end
        end
        i += 1
        val >>>= BigInt(1)
    end
    return res
end

function ==(a::Field, b::Field)
    return a.order==b.order && a.reduction==b.reduction
end

function ==(a::FieldPoint, b::FieldPoint)
    return a.x==b.x && a.field==b.field
end

function !=(a::Field, b::Field)
    return a.order!=b.order || a.reduction!=b.reduction
end

function !=(a::FieldPoint, b::FieldPoint)
    return a.x!=b.x || a.field!=b.field
end

function +(a::FieldPoint, b::FieldPoint)
    if a.field!=b.field throw(FieldMismatchException()) end
    return FieldPoint(a.x ⊻ b.x, a.field)
end

function -(a::FieldPoint, b::FieldPoint)
    return a+b
end

function reduce(a::FieldPoint)
    #k = order(a) - a.field.order
    #i.e. k is the number of bits of a that need to be reduced
    k = bits(a.x) - a.field.order

    #reduction(x) = x^order + t(x)
    t = a.field.reduction ⊻ (BigInt(1) << a.field.order)
    #now shift t left, and the loop will slowly shift it back down again
    t <<= k

    result = a.x

    for i in k:-1:0
        if a.x & (BigInt(1) << (a.field.order+i)) != BigInt(0)
            result ⊻= t + (BigInt(1)<<(a.field.order+i))
        end
        t >>>= 1
    end

    return FieldPoint(result, a.field)
end

#left to right, shift and add
function *(a::FieldPoint, b::FieldPoint)
    if a.field!=b.field throw(FieldMismatchException()) end

    if a.x & BigInt(1) != BigInt(0)
        result = b.x
    else
        result = BigInt(0)
    end

    for i in 1:(a.field.order-1)
        if a.x & (BigInt(1)<<i) != BigInt(0)
            temp = reduce(FieldPoint(b.x << i, b.field))
            result ⊻= temp.x
        end
    end

    return reduce(FieldPoint(result, a.field))
end

#number of bits in the binary representation of this number
function bits(a::Number)
    return floor(Int, log2(a)) +1
end

function inv(a::FieldPoint)
    if a.x==0 throw(DivideError()) end

    u = a.x
    v = a.field.reduction
    g1 = BigInt(1)
    g2 = BigInt(0)

    while u!=BigInt(1)
        j = bits(u) - bits(v)
        if j<0
            (u, v) = (v, u)
            (g1, g2) = (g2, g1)
            j = -j
        end
        u ⊻= v << j
        g1 ⊻= g2 << j
    end
    return FieldPoint(g1, a.field)
end

function /(a::FieldPoint, b::FieldPoint)
    if a.field!=b.field throw(FieldMismatchException()) end
    return a * inv(b)
end

#add a zero between every digit of the original
function square(a::FieldPoint)
    result = BigInt(0)

    counter = BigInt(1)
    for i in 0:(a.field.order-1)
        if a.x & counter != BigInt(0)
            result += BigInt(1) << (i*2)
        end
        counter <<= 1
    end

    return reduce(FieldPoint(result, a.field))
end

#square and multiply method
function ^(a::FieldPoint, b::Int)
    result = FieldPoint(1, a.field)
    squaring = a

    while b>0
        if b & BigInt(1) == BigInt(1)
            result *= squaring
        end
        squaring = square(squaring)
        b >>>= 1
    end

    return result
end

function random(f::Field)
    range = BigInt(0):((BigInt(1)<<f.order)-BigInt(1))
    return FieldPoint(rand(range), f)
end

#sec1v2 2.3.6
function from_octet_string(s::String, f::Field)
    if length(s)!=floor(f.order / 8)*2 throw(ArgumentError("Octet string is of the incorrect length for this field.")) end
    #TODO
    return FieldPoint(value, f)
end

#sec2 v2, table 3:
const FIELD163 = Field(163, (BigInt(1)<<163) + BigInt(128+64+8+1))
const FIELD233 = Field(233, (BigInt(1)<<233) + (BigInt(1)<<74) + BigInt(1))
const FIELD239A = Field(239, (BigInt(1)<<239) + (BigInt(1)<<36) + BigInt(1))
const FIELD239B = Field(239, (BigInt(1)<<239) + (BigInt(1)<<158) + BigInt(1))
const FIELD283 = Field(283, (BigInt(1)<<283) + (BigInt(1)<<12) + BigInt(128+32+1))
const FIELD409 = Field(409, (BigInt(1)<<409) + (BigInt(1)<<87) + BigInt(1))
const FIELD571 = Field(571, (BigInt(1)<<571) + (BigInt(1)<<10) + BigInt(32+4+1))
