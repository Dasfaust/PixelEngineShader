#ifndef TOON_OUTLINES_INCLUDED
#define TOON_OUTLINES_INCLUDED

TEXTURE2D_X_FLOAT(_CameraDepthTexture);
SAMPLER(sampler_CameraDepthTexture);
float4 _CameraDepthTexture_TexelSize;
TEXTURE2D_X_FLOAT(_CameraNormalsTexture);
SAMPLER(sampler_CameraNormalsTexture);
float4 _CameraNormalsTexture_TexelSize;

// https://forum.unity.com/threads/getting-scene-depth-z-buffer-of-the-orthographic-camera.601825/#post-4966334
float CorrectDepth(float rawDepth)
{
    float persp = LinearEyeDepth(rawDepth, _ZBufferParams);
    float ortho = (_ProjectionParams.z - _ProjectionParams.y) * (1 - rawDepth) + _ProjectionParams.y;
    return lerp(persp, ortho, unity_OrthoParams.w);
}

float SampleSceneDepth(float2 screenUv)
{
    float rawDepth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_CameraDepthTexture, UnityStereoTransformScreenSpaceTex(screenUv)).r;
    return CorrectDepth(rawDepth);
}

float3 SampleSceneNormal(float2 screenUv)
{
    float4 sample = SAMPLE_TEXTURE2D_X(_CameraNormalsTexture, sampler_CameraNormalsTexture, UnityStereoTransformScreenSpaceTex(screenUv));
    return normalize(mul((float3x3)UNITY_MATRIX_V, sample.xyz));
}

// https://github.com/KodyJKing/hello-threejs
float4 BlendOutlines(float4 diffuseColor, float4 outerColor, float4 innerColor, float2 screenUv, float thickness, float depthThreshold, float normalThreshold, float3 normalEdgeBias)
{
    float fragDepth = SampleSceneDepth(screenUv);
    float3 fragNormal = SampleSceneNormal(screenUv);

    #if defined(_OUTLINES_PERSPECTIVE)
        // Adjust outline size to be smaller as the camera gets further away
        float4 objectOriginWS = mul(unity_ObjectToWorld, float4(0.0f, 0.0f, 0.0f, 1.0f));
        float distanceWS = distance(_WorldSpaceCameraPos, objectOriginWS.xyz);
        float distancePercentage = Remap(distanceWS, float2(0, _PerspectiveOutlineMaxDistance), float2(1.0f, 0));
        thickness *= distancePercentage;
    #endif

    float2 uvCoords[4];
    uvCoords[0] = screenUv + (float2(1.0f, 0.0f) * _CameraDepthTexture_TexelSize.xy * thickness);
    uvCoords[1] = screenUv + (float2(-1.0f, 0.0f) * _CameraDepthTexture_TexelSize.xy * thickness);
    uvCoords[2] = screenUv + (float2(0.0f, 1.0f) * _CameraDepthTexture_TexelSize.xy * thickness);
    uvCoords[3] = screenUv + (float2(0.0f, -1.0f) * _CameraDepthTexture_TexelSize.xy * thickness);

    float depthDifference = 0.0f;
    float dotSum = 0.0f;
    [unroll] for (int i = 0; i < 4; i++)
    {
        depthDifference += SampleSceneDepth(uvCoords[i]) - fragDepth;
        float3 normalDifference = SampleSceneNormal(uvCoords[i]) - fragNormal;
        float normalBiasDifference = dot(normalDifference, normalEdgeBias);
        float normalIndicator = smoothstep(-0.01, 0.1, normalBiasDifference);
        dotSum += dot(normalDifference, normalDifference) * normalIndicator;
    }

    depthDifference = step(depthThreshold, depthDifference);
    float normalDifference = step(normalThreshold, sqrt(dotSum));
    normalDifference = depthDifference > 0 ? 0 : normalDifference;
    
    float4 outlineColor = (outerColor * depthDifference) + (innerColor * normalDifference);

    #if defined(_DEBUG_OUTLINES)
        return outlineColor;
    #endif

    float diffuseModifier = 1.0f;
    #if defined(_OUTLINES_LIGHTING_EMISSIVE) || defined(_OUTLINES_LIGHTING_UNLIT)
        diffuseModifier = depthDifference + normalDifference;
    #endif

    #if defined(_OUTLINES_BLENDING_OVERLAY)
        return BlendOverlay(diffuseColor * diffuseModifier, outlineColor, (depthDifference + normalDifference) * outlineColor.a);
    #elif defined(_OUTLINES_BLENDING_OVERWRITE)
        return BlendOverwrite(diffuseColor * diffuseModifier, outlineColor, (depthDifference + normalDifference) * outlineColor.a);
    #else
        return BlendSoftLight(diffuseColor * diffuseModifier, outlineColor, (depthDifference + normalDifference) * outlineColor.a);
    #endif
}

#endif