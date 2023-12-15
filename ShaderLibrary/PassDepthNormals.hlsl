#ifndef TOON_DEPTH_NORMALS_PASS_INCLUDED
#define TOON_DEPTH_NORMALS_PASS_INCLUDED

#include "ShaderLibrary/Common.hlsl"

// com.unity.render-pipelines.universal/Shaders/LitDepthNormalsPass.hlsl

#if defined(LOD_FADE_CROSSFADE)
    #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/LODCrossFade.hlsl"
#endif

struct Attributes
{
    float3 positionOS : POSITION;
    float3 normalOS : NORMAL;
    float4 tangentOS : TANGENT;
    float2 uv : TEXCOORD0;

    UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct Interpolators
{
    float4 positionCS : SV_POSITION;
    float2 uv : TEXCOORD0;
    float3 positionWS : TEXCOORD1;
    float3 normalWS : TEXCOORD2;
    float4 tangentWS : TEXCOORD3;

    UNITY_VERTEX_INPUT_INSTANCE_ID
    UNITY_VERTEX_OUTPUT_STEREO
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
        VertexPositionInputs billboardedInputs = CylindricalBillboard(input.positionOS, output.positionWS);
        output.positionCS = billboardedInputs.positionCS;
        output.positionWS = billboardedInputs.positionWS;
    #endif

    VertexNormalInputs normalInputs = GetVertexNormalInputs(input.normalOS, input.tangentOS);
    output.normalWS = normalInputs.normalWS;
    output.tangentWS = float4(normalInputs.tangentWS, input.tangentOS.w);

    output.uv = AtlasUV(input.uv);

    return output;
}

void Fragment(
    Interpolators input
#if defined(_DOUBLE_SIDED_NORMALS)
    , FRONT_FACE_TYPE frontFace : FRONT_FACE_SEMANTIC
#endif
    , out float4 outNormalWS : SV_Target0
#ifdef _WRITE_RENDERING_LAYERS
    , out float4 outRenderingLayers : SV_Target1
#endif
)
{
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

    float3 normalWS = input.normalWS;
    #if defined(_DOUBLE_SIDED_NORMALS)
        normalWS *= IS_FRONT_VFACE(frontFace, 1, -1);
    #endif

    float3 viewDirectionWS = GetWorldSpaceNormalizeViewDir(input.positionWS);
    float2 uv = AdjustUVParallaxMapping(input.uv, input.tangentWS, normalWS, viewDirectionWS);
    float4 diffuseColor = SampleDiffuseColor(uv);
    TestAlphaClip(diffuseColor);

    #ifdef LOD_FADE_CROSSFADE
        LODFadeCrossFade(input.positionCS);
    #endif

    float3 normalTS = SampleNormalMap(uv);
    float3x3 tangentToWorld = CreateTangentToWorld(normalWS, input.tangentWS.xyz, input.tangentWS.w);
    outNormalWS = float4(NormalizeNormalPerPixel(TransformTangentToWorld(normalTS, tangentToWorld)), 0);

    #ifdef _WRITE_RENDERING_LAYERS
        uint renderingLayers = GetMeshRenderingLayer();
        outRenderingLayers = float4(EncodeMeshRenderingLayer(renderingLayers), 0, 0, 0);
    #endif
}

#endif