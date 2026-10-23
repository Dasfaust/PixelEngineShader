#ifndef TOON_COMMON_INCLUDED
#define TOON_COMMON_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/ParallaxMapping.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Input.hlsl"

TEXTURECUBE(_SpecularCubemap);
SAMPLER(sampler_SpecularCubemap);
TEXTURE2D(_DiffuseMap);
SAMPLER(sampler_DiffuseMap);
TEXTURE2D(_NormalMap);
SAMPLER(sampler_NormalMap);
TEXTURE2D(_EmissionMap);
SAMPLER(sampler_EmissionMap);
TEXTURE2D(_MaskMap);
SAMPLER(sampler_MaskMap);
TEXTURE2D(_RampMap);
SAMPLER(sampler_RampMap);

// The material property block the SRP lays out per material.
//
// Every member here must name a property the shader's Properties block declares. Unity validates the
// layout against the material's property set, and a member with no matching property raises
// "Property offset falls outside of range for type in GetPropertyData" and "Expected instancing
// keynames to match" out of the render loop. When that validation fails, Unity never builds the
// per-instance property buffer, and an instanced draw is submitted with one instance and per-draw
// data nobody wrote. Nothing in the material, the scene, or the draw call says so.
//
// _MainTex_ST and _MainTex_TexelSize sat here for a shader that has no _MainTex: this shader's main
// texture is _DiffuseMap, marked [NoScaleOffset], and the viewport shader declares its own block
// beside its own _MainTex property. _ShadowMapTexture_TexelSize sat here too. It is a built-in
// pipeline uniform. The shadow-caster code that read it sits behind one keyword, and no pragma
// declares that keyword, so the code compiled out of every variant and the read never ran. The
// uniform and the dead code are gone.
CBUFFER_START(UnityPerMaterial)
    float4 _DiffuseMap_TexelSize;
    float4 _NormalMap_TexelSize;
    float4 _EmissionMap_TexelSize;
    float4 _MaskMap_TexelSize;
    float _Cutoff;
    float4 _DiffuseColor;
    float _NormalStrength;
    int _SmoothnessMaskChannel;
    float _SmoothnessStrength;
    int _MetallicMaskChannel;
    float _MetallicStrength;
    int _AOMaskChannel;
    float _AOStrength;
    int _HeightMaskChannel;
    float _HeightStrength;
    float4 _EmissionColor;
    float _EmissionStrength;
    float4 _SizeRange;
    float4 _TilingOffset;
    float _FPS;
    float _MinLinearBrightness;
    float _DiffuseQuantization;
    float _SpecularQuantization;
    float _PointQuantization;
    float _SpotQuantization;
    float _PerspectiveOutlineMaxDistance;
    float _OutlineSize;
    float _OutlineEmissionStrength;
    float4 _OuterOutlineColor;
    float _OuterOutlineThreshold;
    float4 _InnerOutlineColor;
    float _InnerOutlineThreshold;
    float4 _InnerOutlineBias;
    float _PixelsPerUnit;
    float4 _WarpBurnColor;
    float _WarpBurnStrength;
    float _WarpBurnPower;
    float _WarpBurnFlickerScale;
    float _WarpBurnFlickerSpeed;
CBUFFER_END


#ifdef UNITY_DOTS_INSTANCING_ENABLED
    UNITY_DOTS_INSTANCING_START(MaterialPropertyMetadata)
        UNITY_DOTS_INSTANCED_PROP(float4, _DiffuseColor)
        UNITY_DOTS_INSTANCED_PROP(float4, _SizeRange)
        UNITY_DOTS_INSTANCED_PROP(float4, _EmissionColor)
        UNITY_DOTS_INSTANCED_PROP(float, _FPS)
        UNITY_DOTS_INSTANCED_PROP(float, _OutlineEmissionStrength)
        UNITY_DOTS_INSTANCED_PROP(float, _OutlineSize)
        UNITY_DOTS_INSTANCED_PROP(float4, _OuterOutlineColor)
        UNITY_DOTS_INSTANCED_PROP(float4, _InnerOutlineColor)
        UNITY_DOTS_INSTANCED_PROP(float, _PixelsPerUnit)
    UNITY_DOTS_INSTANCING_END(MaterialPropertyMetadata)

    #define _DiffuseColor UNITY_ACCESS_DOTS_INSTANCED_PROP_WITH_DEFAULT(float4, _DiffuseColor)
    #define _SizeRange UNITY_ACCESS_DOTS_INSTANCED_PROP_WITH_DEFAULT(float4, _SizeRange)
    #define _EmissionColor UNITY_ACCESS_DOTS_INSTANCED_PROP_WITH_DEFAULT(float4, _EmissionColor)
    #define _FPS UNITY_ACCESS_DOTS_INSTANCED_PROP_WITH_DEFAULT(float, _FPS)
    #define _OutlineEmissionStrength UNITY_ACCESS_DOTS_INSTANCED_PROP_WITH_DEFAULT(float, _OutlineEmissionStrength)
    #define _OutlineSize UNITY_ACCESS_DOTS_INSTANCED_PROP_WITH_DEFAULT(float, _OutlineSize)
    #define _OuterOutlineColor UNITY_ACCESS_DOTS_INSTANCED_PROP_WITH_DEFAULT(float4, _OuterOutlineColor)
    #define _InnerOutlineColor UNITY_ACCESS_DOTS_INSTANCED_PROP_WITH_DEFAULT(float4, _InnerOutlineColor)
    #define _PixelsPerUnit UNITY_ACCESS_DOTS_INSTANCED_PROP_WITH_DEFAULT(float, _PixelsPerUnit)
#endif

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

float3 SnapWorldPositionToPixelGrid(float3 worldPos)
{
    // This function snaps a world position to the camera's pixel grid,
    // accounting for camera rotation. It mirrors the logic from
    // SubpixelOrthographicCamera.WorldPositionToPixelGrid.

    // Get camera's right and up vectors in world space from the inverse view matrix.
    float3 right = UNITY_MATRIX_I_V[0].xyz;
    float3 up    = UNITY_MATRIX_I_V[1].xyz;

    // Project the world position onto the camera's local axes.
    float projX = dot(worldPos, right);
    float projY = dot(worldPos, up);

    // Calculate the size of a pixel in world units.
    float unitsPerPixel = 1.0 / _PixelsPerUnit;

    // Snap the projected coordinates to the pixel grid.
    float snappedX = floor(projX / unitsPerPixel) * unitsPerPixel;
    float snappedY = floor(projY / unitsPerPixel) * unitsPerPixel;

    // Subtract the remainder from the original position to get the snapped position.
    return worldPos - right * (projX - snappedX) - up * (projY - snappedY);
}


VertexPositionInputs _GetVertexPositionInputs(float3 positionOS)
{
    VertexPositionInputs input;
    input.positionWS = TransformObjectToWorld(positionOS);
    
    #if defined(_STABILIZATION_SNAP_WORLD_POS)
    input.positionWS = SnapWorldPositionToPixelGrid(input.positionWS);
    #endif
    
    input.positionVS = TransformWorldToView(input.positionWS);
    input.positionCS = TransformWorldToHClip(input.positionWS);
    
    float4 ndc = input.positionCS * 0.5f;
    input.positionNDC.xy = float2(ndc.x, ndc.y * _ProjectionParams.x) + ndc.w;
    input.positionNDC.zw = input.positionCS.zw;
    

    return input;
}

float2 AtlasUV(float2 uv)
{
    float time = floor(_Time.y * _FPS);
    float currentIndex = (_SizeRange.z + time) % (_SizeRange.w + 1);
    currentIndex = fmod(currentIndex, _SizeRange.x * _SizeRange.y);
    float2 tileCount = float2(1, 1) / float2(_SizeRange.x, _SizeRange.y);
    float tileX = abs(currentIndex - _SizeRange.x * floor(currentIndex * tileCount.x));
    float tileY = abs(1 * _SizeRange.y - (floor(currentIndex * tileCount.x) + 1));
    return ((uv + float2(tileX, tileY)) * tileCount) * _TilingOffset.xy + _TilingOffset.zw;
}

float2 AdjustUVParallaxMapping(float2 atlasUv, float4 tangentWS, float3 normalWS, float3 viewDirectionWS)
{
    float2 uv = atlasUv;
    #if defined(_HEIGHT_MODE_PARALLAX)
        float3 viewDirectionTS = GetViewDirectionTangentSpace(tangentWS, normalWS, viewDirectionWS);
        uv += ParallaxMappingChannel(TEXTURE2D_ARGS(_MaskMap, sampler_MaskMap), viewDirectionTS, _HeightStrength, uv, _HeightMaskChannel);
    #endif
    return uv;
}

// https://www.youtube.com/watch?v=d6tp43wZqps
float2 UpscaleUVs(float2 atlasUv, float4 texelSize)
{
    float2 boxSize = clamp(fwidth(atlasUv) * texelSize.zw, 1e-5, 1);
    float2 tx = atlasUv * texelSize.zw - 0.5 * boxSize;
    float2 txOffset = smoothstep(1 - boxSize, 1, frac(tx));
    return (floor(tx) + 0.5 + txOffset) * texelSize.xy;
}

float4 SampleDiffuseColor(float2 atlasUv)
{
    #if defined(_TEXTURE_SAMPLING_TYPE_UPSCALED)
        return SAMPLE_TEXTURE2D_GRAD(_DiffuseMap, sampler_DiffuseMap, UpscaleUVs(atlasUv, _DiffuseMap_TexelSize), ddx(atlasUv), ddy(atlasUv)) * _DiffuseColor;
    #endif

    return SAMPLE_TEXTURE2D_LOD(_DiffuseMap, sampler_DiffuseMap, atlasUv, 0) * _DiffuseColor;
}

float4 SampleEmissionColor(float2 atlasUv)
{
    #if defined(_TEXTURE_SAMPLING_TYPE_UPSCALED)
        return SAMPLE_TEXTURE2D_GRAD(_EmissionMap, sampler_EmissionMap, UpscaleUVs(atlasUv, _EmissionMap_TexelSize), ddx(atlasUv), ddy(atlasUv));
    #endif

    return SAMPLE_TEXTURE2D_LOD(_EmissionMap, sampler_EmissionMap, atlasUv, 0) * _EmissionColor;
}

float4 SampleMaskMap(float2 atlasUv)
{
    #if defined(_TEXTURE_SAMPLING_TYPE_UPSCALED)
        return SAMPLE_TEXTURE2D_GRAD(_MaskMap, sampler_MaskMap, UpscaleUVs(atlasUv, _MaskMap_TexelSize), ddx(atlasUv), ddy(atlasUv));
    #endif

    return SAMPLE_TEXTURE2D_LOD(_MaskMap, sampler_MaskMap, atlasUv, 0);
}

float4 SampleMaskMapNoLOD(float2 atlasUv)
{
    return SAMPLE_TEXTURE2D(_MaskMap, sampler_MaskMap, atlasUv);
}

float SampleRampMap(float2 uv)
{
    return SAMPLE_TEXTURE2D(_RampMap, sampler_RampMap, uv).r;
}

float3 GenerateNormalFromHeightMap(float2 atlasUv)
{
    float left = SampleMaskMapNoLOD(atlasUv - float2(_MaskMap_TexelSize.x, 0))[_HeightMaskChannel].r;
    float right = SampleMaskMapNoLOD(atlasUv + float2(_MaskMap_TexelSize.x, 0))[_HeightMaskChannel].r;
    float down = SampleMaskMapNoLOD(atlasUv - float2(0, _MaskMap_TexelSize.y))[_HeightMaskChannel].r;
    float up = SampleMaskMapNoLOD(atlasUv + float2(0, _MaskMap_TexelSize.y))[_HeightMaskChannel].r;

    float3 normalTS = float3((left - right) / (_MaskMap_TexelSize.x * 2), (down - up) / (_MaskMap_TexelSize.y * 2), 1);
    normalTS.xy *= _NormalStrength;

    return normalize(normalTS);
}

float3 SampleNormalMap(float2 atlasUv)
{
    #if defined(_HEIGHT_TO_NORMALS)
        return GenerateNormalFromHeightMap(atlasUv);
    #else
        #if defined(_TEXTURE_SAMPLING_TYPE_UPSCALED)
            return UnpackNormalScale(SAMPLE_TEXTURE2D_GRAD(_NormalMap, sampler_NormalMap, UpscaleUVs(atlasUv, _NormalMap_TexelSize), ddx(atlasUv), ddy(atlasUv)), _NormalStrength);
        #endif

        return UnpackNormalScale(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, atlasUv), _NormalStrength);
    #endif
}

void TestAlphaClip(float4 color)
{
    #if defined(_ALPHA_CUTOUT)
        clip(color.a - _Cutoff);
    #endif
}

float4 Saturation(float4 color, float saturation)
{
    float luma = dot(color.rgb, float3(0.2126729, 0.7151522, 0.0721750));
    return float4(luma.xxx + saturation * (color.rgb - luma.xxx), color.a);
}

float AverageFloat3(float3 value)
{
    return max(value.r + value.b + value.g, HALF_MIN) / 3.0f;
}

float Posterize(float value, float steps)
{
    return floor(value / (1 / steps)) * (1 / steps);
}

float3 Posterize(float3 value, float steps)
{
    return floor(value / (1 / steps)) * (1 / steps);
}

float Remap(float value, float2 inputRange, float2 outputRange)
{
    return outputRange.x + (value - inputRange.x) * (outputRange.y - outputRange.x) / (inputRange.y - inputRange.x);
}

float3 Remap(float3 value, float2 inputRange, float2 outputRange)
{
    return outputRange.x + (value - inputRange.x) * (outputRange.y - outputRange.x) / (inputRange.y - inputRange.x);
}

float Quantize(float value, float track, float amount)
{
    #if defined(_QUANTIZATION_TYPE_RAMP)
        return SampleRampMap(float2(value, track)) * value;
    #endif

    return Posterize(value, amount);
}

float3 Quantize(float3 value, float track, float amount)
{
    #if defined(_QUANTIZATION_TYPE_RAMP)
        return SampleRampMap(float2(saturate(AverageFloat3(value)), track)) * value;
    #endif

    return Posterize(value, amount);
}

float QuantizeAndRemap(float value, float track, float amount, float minValue)
{
    #if defined(_QUANTIZATION_TYPE_RAMP)
        float quantized = SampleRampMap(float2(value, track)) * value;
    #else
        float quantized = Posterize(value, amount);
    #endif

    return Remap(quantized, float2(0, 1.0f), float2(minValue, 1.0f));
}

float3 QuantizeAndRemap(float3 value, float track, float amount, float minValue)
{
    #if defined(_QUANTIZATION_TYPE_RAMP)
        float3 quantized = SampleRampMap(float2(saturate(AverageFloat3(value)), track)) * value;
    #else
        float3 quantized = Posterize(value, amount);
    #endif

    return Remap(quantized, float2(0, 1.0f), float2(minValue, 1.0f));
}

VertexPositionInputs CylindricalBillboard(float3 positionOS, float3 positionWS)
{
    float3 direction = _WorldSpaceCameraPos - positionWS;
    float rad = atan2(direction.x, direction.z);
    float _sin = sin(rad);
    float _cos = cos(rad);
    float3x3 _mat = float3x3(_cos, 0, _sin, 0, 1, 0, -_sin, 0, _cos);
    float3 newPositionOS = mul(_mat, positionOS);
    return GetVertexPositionInputs(newPositionOS);
}

float3x3 CylindricalBillboardMatrix(float3 positionWS)
{
    float3 direction = _WorldSpaceCameraPos - positionWS;
    float rad = atan2(direction.x, direction.z);
    float _sin = sin(rad);
    float _cos = cos(rad);
    return float3x3(_cos, 0, _sin, 0, 1, 0, -_sin, 0, _cos);
}

float3 RGBToHSV(float3 color)
{
    float4 k = float4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    float4 p = lerp(float4(color.bg, k.wz), float4(color.gb, k.xy), step(color.b, color.g));
    float4 q = lerp(float4(p.xyw, color.r), float4(color.r, p.yzx), step(p.x, color.r));
    float d = q.x - min(q.w, q.y);
    float e = 1e-10;
    return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

float3 HSVToRGB(float3 color)
{
    float4 k = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    float3 p = abs(frac(color.xxx + k.xyz) * 6.0 - k.www);
    return color.z * lerp(k.xxx, saturate(p - k.xxx), color.y);
}

float4 BlendSoftLight(float4 baseColor, float4 blendColor, float opacity)
{
    float4 result1 = 2.0 * baseColor * blendColor + baseColor * baseColor * (1.0 - 2.0 * blendColor);
    float4 result2 = sqrt(baseColor) * (2.0 * blendColor - 1.0) + 2.0 * baseColor * (1.0 - blendColor);
    float4 zeroOrOne = step(0.5, blendColor);
    float4 blended = result2 * zeroOrOne + (1 - zeroOrOne) * result1;
    return lerp(baseColor, blended, opacity);
}

float4 BlendOverlay(float4 baseColor, float4 blendColor, float opacity)
{
    float4 result1 = 1.0 - 2.0 * (1.0 - baseColor) * (1.0 - blendColor);
    float4 result2 = 2.0 * baseColor * blendColor;
    float4 zeroOrOne = step(baseColor, 0.5);
    float4 blended = result2 * zeroOrOne + (1 - zeroOrOne) * result1;
    return lerp(baseColor, blended, opacity);
}

float4 BlendOverwrite(float4 baseColor, float4 blendColor, float opacity)
{
    return lerp(baseColor, blendColor, opacity);
}

float GetLuminance(float4 color)
{
    return (0.2126f * color.r + 0.7152f * color.g + 0.0722 * color.b);
}

float Square(float value)
{
	return value * value;
}

#endif