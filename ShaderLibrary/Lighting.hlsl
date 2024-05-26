#ifndef TOON_LIGHTING_INCLUDED
#define TOON_LIGHTING_INCLUDED

struct ToonLightingInput
{
    float3 albedo;
    float alpha;

    float smoothness;
    float metallic;
    float ambientOcclusion;

    float3 normalWS;
    float3 positionWS;
    float3 viewDirectionWS;
    
    float4 shadowCoord;
    float2 screenUV;

    float3 bakedGI;
    float fogFactor;
};

struct LightingResult
{
    float3 mixedColor;
    float currentAttenuation;
    float mainLightShadowAttenuation;
    float totalLightIntensity;
};

// Approximate encoded light intensity value
// Unity multiplies light color by its intensity value
float GetLightIntensity(float3 color)
{
    return max(color.r, max(color.g, color.b));
}

// Phong specular
float PhongAttenuation(ToonLightingInput data, Light light)
{
    float specularDot = saturate(dot(data.normalWS, normalize(light.direction + data.viewDirectionWS)));
    return pow(specularDot, exp2(10 * data.smoothness + 1)) * step(0.001f, data.smoothness);
}

// Blinn diffuse and Phong specular
void BlinnPhong(ToonLightingInput data, Light light, inout LightingResult result)
{
    float3 radiance = light.color * result.currentAttenuation;

    float diffuse = saturate(dot(data.normalWS, light.direction));
    float specular = PhongAttenuation(data, light);

    #if defined(_ENABLE_QUANTIZATION)
        diffuse = QuantizeAndRemap(diffuse, 0, _DiffuseQuantization, _MinLinearBrightness);
        specular = Quantize(specular, 1, _SpecularQuantization);
    #endif

    float attenuation = diffuse + specular;
    result.mixedColor += radiance * attenuation;
}

// com.unity.render-pipelines.universal/ShaderLibrary/BRDF.hlsl#L86
// com.unity.render-pipelines.universal/ShaderLibrary/BRDF.hlsl#L54
void InitBRDFData(ToonLightingInput lightData, inout BRDFData data)
{
    half oneMinusReflectivity = OneMinusReflectivityMetallic(lightData.metallic);
    data.reflectivity = 1.0f - oneMinusReflectivity;
    data.diffuse = (lightData.albedo * oneMinusReflectivity) * lightData.alpha;
    data.specular = lerp(kDieletricSpec.rgb, lightData.albedo, lightData.metallic);
    data.perceptualRoughness = PerceptualSmoothnessToPerceptualRoughness(lightData.smoothness);
    data.roughness = max(PerceptualRoughnessToRoughness(data.perceptualRoughness), HALF_MIN_SQRT);
    data.roughness2 = max(data.roughness * data.roughness, HALF_MIN);
    data.grazingTerm = saturate(lightData.smoothness + data.reflectivity);
    data.normalizationTerm = data.roughness * half(4.0) + half(2.0);
    data.roughness2MinusOne = data.roughness2 - half(1.0);
}

// Modified microfacet bidirectional reflectance distribution function
// (i.e. PBR, but it is a mash up between Blinn-Phong and PBR)
// com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl#L39
void BRDF(ToonLightingInput data, BRDFData brdfData, Light light, inout LightingResult result)
{
    float blinnDiffuseAttenuation = saturate(dot(data.normalWS, light.direction));
    float phongSpecularAttenuation = PhongAttenuation(data, light);

    #if defined(_ENABLE_QUANTIZATION)
        blinnDiffuseAttenuation = QuantizeAndRemap(blinnDiffuseAttenuation, 0, _DiffuseQuantization, _MinLinearBrightness);
        phongSpecularAttenuation = Quantize(phongSpecularAttenuation, 1, _SpecularQuantization);
    #endif

    float3 radiance = light.color * (blinnDiffuseAttenuation * result.currentAttenuation);

    float3 color = brdfData.diffuse;
    color += brdfData.specular * phongSpecularAttenuation;

    result.mixedColor += color * radiance;
}

// Modify this function so we can squish them numbers
// com.unity.render-pipelines.universal/ShaderLibrary/GlobalIllumination.hlsl#L353
half3 GlobalIllumination(BRDFData brdfData, half3 bakedGI, half occlusion, float3 positionWS, half3 normalWS, half3 viewDirectionWS, float2 normalizedScreenSpaceUV)
{
    half3 reflectVector = reflect(-viewDirectionWS, normalWS);
    half NdotV = saturate(dot(normalWS, viewDirectionWS));

    #if defined(_ENABLE_GI_QUANTIZATION)
        NdotV = Quantize(NdotV, 0, _DiffuseQuantization);
    #endif

    half fresnelTerm = Pow4(1.0 - NdotV);

    half3 indirectDiffuse = bakedGI;
    half3 indirectSpecular = GlossyEnvironmentReflection(reflectVector, positionWS, brdfData.perceptualRoughness, 1.0h, normalizedScreenSpaceUV);

    half3 color = EnvironmentBRDF(brdfData, indirectDiffuse, indirectSpecular, fresnelTerm);

    return color * occlusion * NdotV;
}

// Add additional lights without a lighting model, though Phong specular is included in this
void AddAdditionalLight(ToonLightingInput data, Light light, inout LightingResult result)
{
    float3 radiance = light.color * result.currentAttenuation;

    float specular = PhongAttenuation(data, light);

    #if defined(_ENABLE_QUANTIZATION)
        specular = Quantize(specular, 1, _SpecularQuantization);
    #endif

    result.mixedColor += radiance * specular;
}

// https://github.com/Cyanilux/URP_ShaderGraphCustomLighting/blob/4262886c09bb374db39944322999289f64110980/CustomLighting.hlsl#L274
// https://catlikecoding.com/unity/tutorials/custom-srp/point-and-spot-lights/
void CalculateAttenuationAdditionalLight(ToonLightingInput data, Light light, uint perObjectLightIndex, inout LightingResult result)
{
    // Perform our own distance attenuation because URP's default model does not give a lot of visible range when quantizing
    #if USE_STRUCTURED_BUFFER_FOR_LIGHT_DATA
        float4 lightPositionWS = _AdditionalLightsBuffer[perObjectLightIndex].position;
        half3 color = _AdditionalLightsBuffer[perObjectLightIndex].color.rgb;
        half4 distanceAndSpotAttenuation = _AdditionalLightsBuffer[perObjectLightIndex].attenuation;
        half4 spotDirection = _AdditionalLightsBuffer[perObjectLightIndex].spotDirection;
    #else
        float4 lightPositionWS = _AdditionalLightsPosition[perObjectLightIndex];
        half3 color = _AdditionalLightsColor[perObjectLightIndex].rgb;
        half4 distanceAndSpotAttenuation = _AdditionalLightsAttenuation[perObjectLightIndex];
        half4 spotDirection = _AdditionalLightsSpotDir[perObjectLightIndex];
    #endif

    float3 lightVector = lightPositionWS.xyz - data.positionWS * lightPositionWS.w;
    float distanceSqr = max(dot(lightVector, lightVector), HALF_MIN);

    // Point
    float range = rsqrt(distanceAndSpotAttenuation.x);
    float dist = sqrt(distanceSqr) / range;
    float pointAtten = saturate(1.0f - dist);

    // Spot
    half3 lightDirection = half3(lightVector * rsqrt(distanceSqr));
    half SdotL = dot(spotDirection.xyz, lightDirection);
    half spotAtten = saturate(SdotL * distanceAndSpotAttenuation.z + distanceAndSpotAttenuation.w);
    spotAtten *= spotAtten;

    #if defined(_ENABLE_QUANTIZATION)
        float maskSpotToRange = step(dist, 1);
        spotAtten = Posterize(spotAtten, _SpotQuantization) * maskSpotToRange;
        pointAtten = Posterize(pointAtten, _PointQuantization);
    #endif

    bool isSpot = (distanceAndSpotAttenuation.z > 0);
    float attenuation = isSpot ? spotAtten : pointAtten;
    result.currentAttenuation = light.shadowAttenuation * attenuation;
    result.totalLightIntensity += GetLightIntensity(light.color) * result.currentAttenuation;

    // Allow additional lights to remove main light shadows instead of just shading them
    result.mainLightShadowAttenuation = max(saturate(result.currentAttenuation * GetLightIntensity(light.color)), result.mainLightShadowAttenuation);
}

void CalculateAttenuationMainLight(Light light, inout LightingResult result)
{
    result.currentAttenuation = result.mainLightShadowAttenuation * light.distanceAttenuation;
    result.totalLightIntensity += GetLightIntensity(light.color) * result.currentAttenuation;
}

void HandleLight(ToonLightingInput data, BRDFData brdfData, Light light, inout LightingResult result)
{
    #if defined(_LIGHTING_MODEL_BLINNPHONG)
        BlinnPhong(data, light, result);
    #else
        BRDF(data, brdfData, light, result);
    #endif
}

void HandleAdditionalLight(ToonLightingInput data, BRDFData brdfData, Light additionalLight, uint lightIndex, inout LightingResult result)
{
    CalculateAttenuationAdditionalLight(data, additionalLight, lightIndex, result);

    #if defined(_ADDITIONAL_LIGHTS_MODEL_NONE)
        AddAdditionalLight(data, additionalLight, result);
    #else
        HandleLight(data, brdfData, additionalLight, result);
    #endif
}

// com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl
// https://www.youtube.com/watch?v=GQyCPaThQnA
LightingResult CalculateLighting(ToonLightingInput data)
{
    LightingResult result = (LightingResult)0;

    // com.unity.render-pipelines.universal/ShaderLibrary/Input.hlsl#L38
    InputData inputData = (InputData)0;
    inputData.normalizedScreenSpaceUV = data.screenUV;
    inputData.positionWS = data.positionWS;
    inputData.shadowCoord = data.shadowCoord;
    inputData.normalWS = data.normalWS;
    inputData.viewDirectionWS = data.viewDirectionWS;

    // com.unity.render-pipelines.universal/ShaderLibrary/AmbientOcclusion.hlsl#L55
    AmbientOcclusionFactor aoFactor = CreateAmbientOcclusionFactor(data.screenUV, data.ambientOcclusion);
    // com.unity.render-pipelines.universal/ShaderLibrary/RealtimeLights.hlsl#L309
    half4 shadowMask = CalculateShadowMask(inputData);

    // com.unity.render-pipelines.universal/ShaderLibrary/RealtimeLights.hlsl#L138
    Light mainLight = GetMainLight(inputData, shadowMask, aoFactor);
    result.mainLightShadowAttenuation = mainLight.shadowAttenuation;

    // Apply ambient and GI color
    MixRealtimeAndBakedGI(mainLight, data.normalWS, data.bakedGI);
    inputData.bakedGI = data.bakedGI;
    BRDFData brdfData = (BRDFData)0;
    BRDFData brdfClearcoat = (BRDFData)0;
    InitBRDFData(data, brdfData);
    result.mixedColor = GlobalIllumination(brdfData, inputData.bakedGI, aoFactor.indirectAmbientOcclusion, inputData.positionWS, inputData.normalWS, inputData.viewDirectionWS, inputData.normalizedScreenSpaceUV);

    // Forward+ additional lights loop
    #if defined(_ADDITIONAL_LIGHTS)
        uint meshRenderingLayers = GetMeshRenderingLayer();
        uint pixelLightCount = GetAdditionalLightsCount();

        // com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl#L296
        #if USE_FORWARD_PLUS
            for (uint lightIndex = 0; lightIndex < min(URP_FP_DIRECTIONAL_LIGHTS_COUNT, MAX_VISIBLE_LIGHTS); lightIndex++)
            {
                FORWARD_PLUS_SUBTRACTIVE_LIGHT_CHECK

                // com.unity.render-pipelines.universal/ShaderLibrary/RealtimeLights.hlsl#L282
                Light additionalLight = GetAdditionalLight(lightIndex, inputData, shadowMask, aoFactor);

                #ifdef _LIGHT_LAYERS
                    if (IsMatchingLightLayer(light.layerMask, meshRenderingLayers))
                #endif
                {
                    HandleAdditionalLight(data, brdfData, additionalLight, lightIndex, result);
                }
            }
        #endif

        LIGHT_LOOP_BEGIN(pixelLightCount)
            // com.unity.render-pipelines.universal/ShaderLibrary/RealtimeLights.hlsl#L282
            Light additionalLight = GetAdditionalLight(lightIndex, inputData, shadowMask, aoFactor);

            #ifdef _LIGHT_LAYERS
                if (IsMatchingLightLayer(light.layerMask, meshRenderingLayers))
            #endif
            {
                HandleAdditionalLight(data, brdfData, additionalLight, lightIndex, result);
            }
        LIGHT_LOOP_END
    #endif

    #ifdef _LIGHT_LAYERS
        if (IsMatchingLightLayer(light.layerMask, meshRenderingLayers))
    #endif
    {
        // Add in the main light last since we're changing its shadow attenuation
        CalculateAttenuationMainLight(mainLight, result);
        HandleLight(data, brdfData, mainLight, result);
    }
    
    // Mix fog color
    result.mixedColor = MixFog(result.mixedColor, InitializeInputDataFog(float4(inputData.positionWS, 1.0), data.fogFactor));

    return result;
}

#endif