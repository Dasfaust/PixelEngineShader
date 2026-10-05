#ifndef PIXEL_ENGINE_COLOR_OPERATIONS_INCLUDED
#define PIXEL_ENGINE_COLOR_OPERATIONS_INCLUDED

float3 RGBToXYZ(float3 rgb)
{
    rgb = pow(rgb, 2.2);
    
    float3x3 mat = float3x3(
        0.4124564, 0.3575761, 0.1804375,
        0.2126729, 0.7151522, 0.0721750,
        0.0193339, 0.1191920, 0.9503041
    );
    return mul(mat, rgb);
}

float3 XYZToLab(float3 xyz)
{
    xyz /= float3(0.90547, 1.0, 1.08883);
    
    float3 f = xyz > 0.008856 ? pow(xyz, 1.0 / 3.0) : (7.787 * xyz + 16.0 / 116.0);
    
    float l = 116.0 * f.y - 16.0;
    float a = 500.0 * (f.x - f.y);
    float b = 200.0 * (f.y - f.z);
    
    return float3(l, a, b);
}

float3 RGBToLab(float3 rgb)
{
    return XYZToLab(RGBToXYZ(rgb));
}

#endif