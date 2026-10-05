#ifndef PIXEL_ENGINE_BILINEAR_POINT_SAMPLING_INCLUDED
#define PIXEL_ENGINE_BILINEAR_POINT_SAMPLING_INCLUDED

// https://www.youtube.com/watch?v=d6tp43wZqps
float2 BilinearPointSamplingUV(float2 uv, float4 texelSize)
{
    float2 boxSize = clamp(fwidth(uv) * texelSize.zw, 1e-5, 1);
    float2 tx = uv * texelSize.zw - 0.5 * boxSize;
    float2 txOffset = smoothstep(1 - boxSize, 1, frac(tx));
    return (floor(tx) + 0.5 + txOffset) * texelSize.xy;
}

#endif