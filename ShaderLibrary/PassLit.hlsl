#ifndef TOON_LIT_PASS_INCLUDED
#define TOON_LIT_PASS_INCLUDED

#include "ShaderLibrary/Common.hlsl"
#include "ShaderLibrary/Lighting.hlsl"
#include "ShaderLibrary/Outlines.hlsl"

struct Attributes
{
    float3 positionOS : POSITION;
    float3 normalOS : NORMAL;
    float4 tangentOS : TANGENT;
    float2 uv : TEXCOORD0;
    float2 uv1 : TEXCOORD1;

    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct Interpolators
{
    float4 positionCS : SV_POSITION;
    float3 positionWS : TEXCOORD3;
    float3 normalWS : TEXCOORD2;
    float4 tangentWS : TEXCOORD4;
    float2 uv : TEXCOORD0;
    float2 uv1 : TEXCOORD1;

    UNITY_VERTEX_INPUT_INSTANCE_ID
};

Interpolators Vertex(Attributes input)
{
    Interpolators output;

    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_TRANSFER_INSTANCE_ID(input, output);

    VertexPositionInputs positionInputs = GetVertexPositionInputs(input.positionOS);
    output.positionCS = positionInputs.positionCS;
    output.positionWS = positionInputs.positionWS;

    #if defined(_BILLBOARDING_CYLINDRICAL)
        float3x3 _mat = CylindricalBillboardMatrix(output.positionWS);
        float3 newPositionOS = mul(_mat, input.positionOS);
        VertexPositionInputs billboardedInputs = GetVertexPositionInputs(newPositionOS);
        output.positionCS = billboardedInputs.positionCS;
        output.positionWS = billboardedInputs.positionWS;

        float3 newNormalOS = mul(_mat, input.normalOS);
        float3 newTangentOS = mul(_mat, input.tangentOS.xyz);
        VertexNormalInputs normalInputs = GetVertexNormalInputs(newNormalOS, float4(newTangentOS, input.tangentOS.w));
        output.normalWS = normalInputs.normalWS;
        output.tangentWS = float4(normalInputs.tangentWS, input.tangentOS.w);
    #else
        VertexNormalInputs normalInputs = GetVertexNormalInputs(input.normalOS, input.tangentOS);
        output.normalWS = normalInputs.normalWS;
        output.tangentWS = float4(normalInputs.tangentWS, input.tangentOS.w);
    #endif

    output.uv = AtlasUV(input.uv);
    output.uv1 = input.uv1;

    return output;
}

float4 Fragment(Interpolators input
#if defined(_DOUBLE_SIDED_NORMALS)
, FRONT_FACE_TYPE frontFace : FRONT_FACE_SEMANTIC
#endif
) : SV_TARGET
{
    UNITY_SETUP_INSTANCE_ID(input);

    ToonLightingInput lightingInput = (ToonLightingInput)0;

    lightingInput.normalWS = input.normalWS;
    #if defined(_DOUBLE_SIDED_NORMALS)
        lightingInput.normalWS *= IS_FRONT_VFACE(frontFace, 1, -1);
    #endif

    lightingInput.viewDirectionWS = GetWorldSpaceNormalizeViewDir(input.positionWS);

    float2 uv = AdjustUVParallaxMapping(input.uv, input.tangentWS, lightingInput.normalWS, lightingInput.viewDirectionWS);

    float4 diffuseColor = SampleDiffuseColor(uv);
    TestAlphaClip(diffuseColor);

    lightingInput.screenUV = GetNormalizedScreenSpaceUV(input.positionCS);
    #if defined(_DEBUG_DEPTH)
        return SampleSceneDepth(lightingInput.screenUV, input.positionWS);
    #endif

    #if defined(_DEBUG_NORMALS)
        return float4(SampleSceneNormal(lightingInput.screenUV), 1);
    #endif

    #if defined(_OUTLINES_ENABLED)
        #if defined(_OUTLINES_LIGHTING_EMISSIVE) || defined(_OUTLINES_LIGHTING_UNLIT)
            float4 outlineColor = BlendOutlines(diffuseColor, _OuterOutlineColor, _InnerOutlineColor, lightingInput.screenUV, _OutlineSize, _OuterOutlineThreshold, _InnerOutlineThreshold, _InnerOutlineBias.xyz);
        #else
            diffuseColor = BlendOutlines(diffuseColor, _OuterOutlineColor, _InnerOutlineColor, lightingInput.screenUV, _OutlineSize, _OuterOutlineThreshold, _InnerOutlineThreshold, _InnerOutlineBias.xyz);
        #endif

        #if defined(_DEBUG_OUTLINES) && !(defined(_OUTLINES_LIGHTING_EMISSIVE) || defined(_OUTLINES_LIGHTING_UNLIT))
            return diffuseColor;
        #endif
    #endif

    lightingInput.albedo = diffuseColor.rgb;
    lightingInput.alpha = diffuseColor.a;

    float3 normalTS = SampleNormalMap(uv);
    float3x3 tangentToWorld = CreateTangentToWorld(lightingInput.normalWS, input.tangentWS.xyz, input.tangentWS.w);
    lightingInput.normalWS = normalize(TransformTangentToWorld(normalTS, tangentToWorld));

    lightingInput.positionWS = input.positionWS;

    #if defined(_MAIN_LIGHT_SHADOWS_SCREEN)
        lightingInput.shadowCoord = ComputeScreenPos(TransformWorldToHClip(input.positionWS));
    #else
        lightingInput.shadowCoord = TransformWorldToShadowCoord(input.positionWS);
    #endif

    float3 lightmapUV;
    OUTPUT_LIGHTMAP_UV(input.uv1, unity_LightmapST, lightmapUV);
    float3 vertexSh;
    OUTPUT_SH(lightingInput.normalWS, vertexSh);
    lightingInput.bakedGI = SAMPLE_GI(lightmapUV, vertexSh, lightingInput.normalWS);
    lightingInput.fogFactor = ComputeFogFactor(input.positionCS.z);

    float4 maskMap = SampleMaskMap(uv);
    float smoothnessSample = maskMap[_SmoothnessMaskChannel];
    #if defined(_INVERT_SMOOTHNESS)
        smoothnessSample = 1 - smoothnessSample;
    #endif
    lightingInput.smoothness = smoothnessSample * _SmoothnessStrength;
    lightingInput.metallic = maskMap[_MetallicMaskChannel] * _MetallicStrength;
    lightingInput.ambientOcclusion = maskMap[_AOMaskChannel] * _AOStrength;

    LightingResult result = CalculateLighting(lightingInput);
    float4 litColor = float4(result.mixedColor, diffuseColor.a);
    #if defined(_LIGHTING_MODEL_BLINNPHONG)
        litColor *= diffuseColor;
    #endif

    float4 emissionSample = SampleEmissionColor(uv);
    float4 emissedColor = max(litColor, ((_EmissionColor * emissionSample) * _EmissionStrength));

    #if defined(_OUTLINES_ENABLED)
        #if defined(_OUTLINES_LIGHTING_EMISSIVE)
            emissedColor = lerp(emissedColor, outlineColor * _OutlineEmissionStrength, outlineColor.a);
        #elif defined(_OUTLINES_LIGHTING_UNLIT)
            emissedColor = lerp(emissedColor, outlineColor, step(0.05f, result.totalLightIntensity) * outlineColor.a);
        #endif

        #if defined(_DEBUG_OUTLINES) && (defined(_OUTLINES_LIGHTING_EMISSIVE) || defined(_OUTLINES_LIGHTING_UNLIT))
            return emissedColor;
        #endif
    #endif

    return emissedColor;
}

#endif