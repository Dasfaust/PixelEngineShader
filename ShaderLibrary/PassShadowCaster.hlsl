#ifndef TOON_SHADOW_CASTER_PASS_INCLUDED
#define TOON_SHADOW_CASTER_PASS_INCLUDED

#include "ShaderLibrary/Common.hlsl"

// com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl

float3 FlipNormalBasedOnViewDir(float3 normalWS, float3 positionWS)
{
    float3 viewDirWS = GetWorldSpaceNormalizeViewDir(positionWS);
    return normalWS * (dot(normalWS, viewDirWS) < 0 ? -1 : 1);
}

float3 _LightDirection;
float3 _LightPosition;
float4 GetShadowCasterPositionCS(float3 positionWS, float3 normalWS)
{
    #if _CASTING_PUNCTUAL_LIGHT_SHADOW
        float3 lightDirectionWS = normalize(_LightPosition - positionWS);
    #else
        float3 lightDirectionWS = _LightDirection;
    #endif
    
    #if defined(_DOUBLE_SIDED_NORMALS)
        normalWS = FlipNormalBasedOnViewDir(normalWS, positionWS);
    #endif

    float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS));
    #if UNITY_REVERSED_Z
        positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
    #else
        positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
    #endif

    return positionCS;
}

struct Attributes
{
    float3 positionOS : POSITION;
    float3 normalOS : NORMAL;
    float2 uv : TEXCOORD0;

    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct Interpolators
{
    float4 positionCS : SV_POSITION;
    float2 uv : TEXCOORD0;

    UNITY_VERTEX_INPUT_INSTANCE_ID
};

Interpolators Vertex(Attributes input)
{
    Interpolators output;

    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_TRANSFER_INSTANCE_ID(input, output);

    VertexPositionInputs positionInputs = GetVertexPositionInputs(input.positionOS);
    VertexNormalInputs normalInputs = GetVertexNormalInputs(input.normalOS);
    #if defined(_BILLBOARDING_CYLINDRICAL)
        VertexPositionInputs billboardedInputs = CylindricalBillboard(input.positionOS, positionInputs.positionWS);
        output.positionCS = GetShadowCasterPositionCS(billboardedInputs.positionWS, normalInputs.normalWS);
    #else
        output.positionCS = GetShadowCasterPositionCS(positionInputs.positionWS, normalInputs.normalWS);
    #endif

    output.uv = AtlasUV(input.uv);

    return output;
}

float4 Fragment(Interpolators input) : SV_TARGET
{
    UNITY_SETUP_INSTANCE_ID(input);

    float4 diffuseColor = SampleDiffuseColor(input.uv);
    TestAlphaClip(diffuseColor);

    return 0;
}

#endif