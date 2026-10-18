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

// Threshold entry ramp: a measure past its threshold ramps in across [T, T * OUTLINE_RAMP_SPAN].
// Every blend mode below weights by the mask, so a pixel whose measure sits near the threshold
// travels an intensity band under sampling jitter, and does not flip.
#define OUTLINE_RAMP_SPAN 1.25f

// https://github.com/KodyJKing/hello-threejs
float4 BlendOutlines(float4 diffuseColor, float4 outerColor, float4 innerColor, float2 screenUv, float thickness, float depthThreshold, float normalThreshold, float3 normalEdgeBias)
{
    // Whole texels: the neighbor reads land on texel centers of the point-sampled depth and
    // normals textures, so each sample is a stored texel value. A fractional size lands the
    // reads between texels, and the point filter snaps them to the nearest one.
    float outlineSize = floor(thickness + 0.5f);

    float fragDepth = SampleSceneDepth(screenUv);
    
    float3 fragNormal = SampleSceneNormal(screenUv);

    #if defined(_OUTLINES_PERSPECTIVE)
        // Adjust outline size to be smaller as the camera gets further away
        float4 objectOriginWS = mul(unity_ObjectToWorld, float4(0.0f, 0.0f, 0.0f, 1.0f));
        float distanceWS = distance(_WorldSpaceCameraPos, objectOriginWS.xyz);
        float distancePercentage = Remap(distanceWS, float2(0, _PerspectiveOutlineMaxDistance), float2(1.0f, 0));
        outlineSize = floor(outlineSize * distancePercentage + 0.5f);
    #endif

    float2 uvCoords[4];
    uvCoords[0] = screenUv + (float2(1.0f, 0.0f) * _CameraDepthTexture_TexelSize.xy * outlineSize);
    uvCoords[1] = screenUv + (float2(-1.0f, 0.0f) * _CameraDepthTexture_TexelSize.xy * outlineSize);
    uvCoords[2] = screenUv + (float2(0.0f, 1.0f) * _CameraDepthTexture_TexelSize.xy * outlineSize);
    uvCoords[3] = screenUv + (float2(0.0f, -1.0f) * _CameraDepthTexture_TexelSize.xy * outlineSize);

    float depthDifference = 0.0f;
    float dotSum = 0.0f;
    [unroll] for (int i = 0; i < 4; i++)
    {
        depthDifference += SampleSceneDepth(uvCoords[i]) - fragDepth;
        float3 normalDifference = SampleSceneNormal(uvCoords[i]) - fragNormal;
        // The magnitude keeps the window symmetric: a normal slope crossing the fragment in
        // one direction counts the same as the slope crossing it in the other.
        float normalBiasDifference = abs(dot(normalDifference, normalEdgeBias));
        float normalIndicator = smoothstep(0.01, 0.1, normalBiasDifference);
        dotSum += dot(normalDifference, normalDifference) * normalIndicator;
    }

    // The symmetric pairs cancel on a planar slope, so the surviving depth sum marks a depth
    // discontinuity, positive on the low side of the step.
    depthDifference = smoothstep(depthThreshold, depthThreshold * OUTLINE_RAMP_SPAN, depthDifference);
    float normalDifference = smoothstep(normalThreshold, normalThreshold * OUTLINE_RAMP_SPAN, sqrt(dotSum));
    // The outer mask gates the inner mask: at a depth discontinuity the inner outline yields
    // to the outer, and the gate blends across the ramp band.
    normalDifference = (1.0f - depthDifference) * normalDifference;
    
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