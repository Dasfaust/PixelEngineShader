#ifndef PIXELENGINE_INTEGER_HASH_INCLUDED
#define PIXELENGINE_INTEGER_HASH_INCLUDED

// An exact 32-bit integer hash. Every step is unsigned integer math, so the answer carries the same
// quality at index 3 and at index 999999, and it does not depend on the size of the number it reads:
// integer multiplication wraps exactly, and the mixing spreads every bit.
//
// A hash that multiplies its input by a large constant and keeps the fractional part has a mantissa
// budget. A 32-bit float carries 24 bits of mantissa, so a product near 1.6e6 has a step of about 0.1,
// and a product past 2^24 has a step of 1 or more. Past that step the fractional part a caller reads is
// coarse, many cells answer the same value, and a star field lands on its own lattice: a grid pattern
// shows up, and the sizes and colors that read the same degenerate roll come out in a few steps.
uint UintHash(uint x, uint y, uint z)
{
    uint p = x * 1013904223u + y * 1554868939u + z * 1430517047u;
    p = p ^ (p >> 16);
    p *= 2246822507u;
    p = p ^ (p >> 13);
    p *= 3266489909u;
    p = p ^ (p >> 16);
    return p;
}

// The hash in [0, 1). The 32 bits are read as the top bits of a float in [0, 1), so the value is
// uniform and the low bits a later multiply by 13.7 can use are real bits.
float Hash01(int2 lattice, int salt)
{
    uint h = UintHash((uint)lattice.x, (uint)lattice.y, (uint)salt);
    return h * (1.0 / 4294967296.0);
}

// Positive modulo on whole numbers, so a negative lattice index reads the same cell as the matching
// positive one. Count is the cell count across the field on each axis, so the noise period is the
// field's own width and height, and a slide that wraps past the field edge reads the cells it left.
int2 WrapLattice(int2 lattice, int2 count)
{
    return ((lattice % count) + count) % count;
}

#endif
