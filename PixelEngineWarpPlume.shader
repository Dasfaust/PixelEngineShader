// The bow plume: the plasma sheath that wraps the front of a platform moving through the warp.
//
// The geometry is the cap WarpPlumeMath builds: an arc across the front, authored wider than a half circle
// so the ends wrap past the sides, with a ribbon running downstream from the arc. This shader lights it.
//
// Brightness comes from three authored terms multiplied together. The facing term is the cap normal against
// the travel direction, so the front of the cap is the hot band and the wrapped ends go dim, which is what
// makes the sheath read as a curve and not as a decal. The downstream term spends the sheath along the tail.
// The edge term tapers the wrap ends, so the ends that reach behind the sides do not stop on a hard line.
//
// The plate draws additive with ZTest Always. A platform that travels away from the camera puts its sheath
// behind the hull in depth, and a depth test the hull can win would hide the burn.
Shader "PixelEngine/Warp Plume"
{
    Properties
    {
        [Header(Plume Look)]
        [HDR] _PlumeColor("Plume Colour", color) = (1.6, 0.34, 0.08, 1)
        [HDR] _PlumeHotColor("Front Hot Colour", color) = (1.4, 0.78, 0.3, 1)
        _PlumeIntensity("Plume Intensity", Range(0, 8)) = 2.5
        _PlumePower("Downstream Falloff Power", Range(0.01, 8)) = 1.2
        _PlumeFacing("Facing Falloff Power", Range(0.01, 16)) = 1.5
        _PlumeEdge("Wrap End Taper", Range(0.01, 8)) = 1.5
        _PlumeFilaments("Filament Count", Range(1, 64)) = 14
        _PlumeTurbulence("Filament Length Scale", Range(0.05, 8)) = 1.2
        _PlumeSpeed("Scroll Speed", Range(0, 8)) = 1
        _PlumeCells("Grain Cells", Range(1, 128)) = 28
        _PlumeDepthAlphaMin("Prepass Alpha Floor", Range(0, 1)) = 0.04
        [Header(Debug)]
        [Toggle(_DEBUG_PLUME)] _DebugRender("Debug Render (flat colour, reads no warp state)", Float) = 0
        _PlumeDebugIntensity("Debug Intensity Override (0 reads the warp seam)", Range(0, 1)) = 0
        [HideInInspector] _PlumeDebugAlpha("Debug Alpha Override (0 keeps the authored mask)", Range(0, 1)) = 0
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
        }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        // The warp rig publishes these three: the intensity the pass runs on, the clock the filaments
        // scroll on, and the direction of travel. They are globals and not per-material constants, so
        // they stay outside the constant block. They are declared before the mask include, because the
        // mask reads the intensity and HLSL binds a declaration before the point of use.
        float4 _WarpTravelWS;
        float _WarpIntensity;
        float _WarpFlowPhase;

        #include "./ShaderLibrary/PlumeMask.hlsl"

        CBUFFER_START(UnityPerMaterial)
            float4 _PlumeColor;
            float4 _PlumeHotColor;
            float _PlumeIntensity;
            float _PlumePower;
            float _PlumeFacing;
            float _PlumeEdge;
            float _PlumeFilaments;
            float _PlumeTurbulence;
            float _PlumeSpeed;
            float _PlumeCells;
            float _PlumeDepthAlphaMin;
            float _PlumeDebugIntensity;
            float _PlumeDebugAlpha;
        CBUFFER_END

        #ifdef UNITY_DOTS_INSTANCING_ENABLED
            UNITY_DOTS_INSTANCING_START(MaterialPropertyMetadata)
                UNITY_DOTS_INSTANCED_PROP(float4, _PlumeColor)
                UNITY_DOTS_INSTANCED_PROP(float4, _PlumeHotColor)
                UNITY_DOTS_INSTANCED_PROP(float, _PlumeIntensity)
                UNITY_DOTS_INSTANCED_PROP(float, _PlumePower)
                UNITY_DOTS_INSTANCED_PROP(float, _PlumeFacing)
                UNITY_DOTS_INSTANCED_PROP(float, _PlumeEdge)
                UNITY_DOTS_INSTANCED_PROP(float, _PlumeFilaments)
                UNITY_DOTS_INSTANCED_PROP(float, _PlumeTurbulence)
                UNITY_DOTS_INSTANCED_PROP(float, _PlumeSpeed)
                UNITY_DOTS_INSTANCED_PROP(float, _PlumeCells)
                UNITY_DOTS_INSTANCED_PROP(float, _PlumeDepthAlphaMin)
                UNITY_DOTS_INSTANCED_PROP(float, _PlumeDebugIntensity)
                UNITY_DOTS_INSTANCED_PROP(float, _PlumeDebugAlpha)
            UNITY_DOTS_INSTANCING_END(MaterialPropertyMetadata)

            #define _PlumeColor         UNITY_ACCESS_DOTS_INSTANCED_PROP_WITH_DEFAULT(float4, _PlumeColor)
            #define _PlumeHotColor      UNITY_ACCESS_DOTS_INSTANCED_PROP_WITH_DEFAULT(float4, _PlumeHotColor)
            #define _PlumeIntensity     UNITY_ACCESS_DOTS_INSTANCED_PROP_WITH_DEFAULT(float, _PlumeIntensity)
            #define _PlumePower         UNITY_ACCESS_DOTS_INSTANCED_PROP_WITH_DEFAULT(float, _PlumePower)
            #define _PlumeFacing        UNITY_ACCESS_DOTS_INSTANCED_PROP_WITH_DEFAULT(float, _PlumeFacing)
            #define _PlumeEdge          UNITY_ACCESS_DOTS_INSTANCED_PROP_WITH_DEFAULT(float, _PlumeEdge)
            #define _PlumeFilaments     UNITY_ACCESS_DOTS_INSTANCED_PROP_WITH_DEFAULT(float, _PlumeFilaments)
            #define _PlumeTurbulence    UNITY_ACCESS_DOTS_INSTANCED_PROP_WITH_DEFAULT(float, _PlumeTurbulence)
            #define _PlumeSpeed         UNITY_ACCESS_DOTS_INSTANCED_PROP_WITH_DEFAULT(float, _PlumeSpeed)
            #define _PlumeCells         UNITY_ACCESS_DOTS_INSTANCED_PROP_WITH_DEFAULT(float, _PlumeCells)
            #define _PlumeDepthAlphaMin UNITY_ACCESS_DOTS_INSTANCED_PROP_WITH_DEFAULT(float, _PlumeDepthAlphaMin)
            #define _PlumeDebugIntensity UNITY_ACCESS_DOTS_INSTANCED_PROP_WITH_DEFAULT(float, _PlumeDebugIntensity)
            #define _PlumeDebugAlpha    UNITY_ACCESS_DOTS_INSTANCED_PROP_WITH_DEFAULT(float, _PlumeDebugAlpha)
        #endif

        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            ZTest LEqual
            Cull Off

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 4.5
            #pragma multi_compile_instancing
            #pragma instancing_options renderinglayer
            #pragma multi_compile _ DOTS_INSTANCING_ON
            #pragma shader_feature_local _DEBUG_PLUME

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 normalWS : TEXCOORD0;
                float2 uv : TEXCOORD1;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            Varyings vert(Attributes input)
            {
                Varyings output = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);

                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                output.positionCS = TransformWorldToHClip(positionWS);
                output.normalWS = TransformObjectToWorldNormal(input.normalOS);
                output.uv = input.uv;
                return output;
            }

            float4 frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);

#if defined(_DEBUG_PLUME)
                // The debug answer. It reads no warp state, no travel, no normal, and no uv, so a mesh
                // with this material either draws a solid shape or does not draw at all, and nothing in
                // the warp rig can be the reason. A scene view and a play mode frame answer the same
                // question from the same material, so the split between the draw path and the rig is a
                // measurement and not a guess.
                return float4(saturate(_PlumeColor.rgb) * 2.0, 1.0);
#endif

                // The intensity is the warp seam's number, so the sheath and the streaks run on one value.
                // PlumeIntensityNow is the measurement override: authored zero, which is the shipped state.
                float intensity = PlumeIntensityNow(_PlumeDebugIntensity);
                if (intensity <= 0.0f)
                {
                    return float4(0.0f, 0.0f, 0.0f, 0.0f);
                }

                float2 uv = saturate(input.uv);

                float3 travel = PlumeTravelWS(_WarpTravelWS);
                float facing = pow(saturate(dot(normalize(input.normalWS), travel)), max(_PlumeFacing, 0.01f));
                float mask = PlumeMask(uv, input.normalWS, intensity, _PlumeFacing, _PlumePower,
                    _PlumeEdge, _PlumeFilaments, _PlumeTurbulence, _PlumeSpeed, _PlumeCells,
                    _WarpFlowPhase, travel, facing);
                float alpha = saturate(_PlumeIntensity * mask);
                alpha = lerp(alpha, saturate(_PlumeDebugAlpha) * intensity, saturate(_PlumeDebugAlpha));
                float3 colour = lerp(_PlumeColor.rgb, _PlumeHotColor.rgb,
                    pow(saturate(1.0f - uv.y), 3.0f) * facing);
                return float4(colour, alpha);
            }
            ENDHLSL
        }

        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode" = "DepthNormals" }

            ZWrite On
            Cull Off

            HLSLPROGRAM
            #pragma vertex DepthNormalsVertex
            #pragma fragment DepthNormalsFragment
            #pragma target 4.5
            #pragma multi_compile_instancing
            #pragma instancing_options renderinglayer
            #pragma multi_compile _ DOTS_INSTANCING_ON
            #pragma shader_feature_local _DEBUG_PLUME

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Interpolators
            {
                float4 positionCS : SV_POSITION;
                float3 normalWS : TEXCOORD0;
                float2 uv : TEXCOORD1;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            Interpolators DepthNormalsVertex(Attributes input)
            {
                Interpolators output = (Interpolators)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);
                output.positionCS = TransformWorldToHClip(TransformObjectToWorld(input.positionOS.xyz));
                output.normalWS = TransformObjectToWorldNormal(input.normalOS);
                output.uv = input.uv;
                return output;
            }

            void DepthNormalsFragment(Interpolators input, out float4 outNormalWS : SV_Target0)
            {
                UNITY_SETUP_INSTANCE_ID(input);

#if defined(_DEBUG_PLUME)
                // The debug answer writes the normal for the whole footprint and clips nothing, so the
                // prepass and the forward pass agree on what the debug run covers.
                outNormalWS = float4(NormalizeNormalPerPixel(normalize(input.normalWS)), 0.0f);
                return;
#endif

                // The clip reads the intensity the forward pass reads. A prepass computed at a fixed
                // intensity passes the clip over the whole footprint, and the prepass writes depth, so the
                // primed main pass resolves what sits behind against depth the plume never lights.
                float intensity = PlumeIntensityNow(_PlumeDebugIntensity);
                float3 travel = PlumeTravelWS(_WarpTravelWS);
                float facing = pow(saturate(dot(normalize(input.normalWS), travel)), max(_PlumeFacing, 0.01f));
                float mask = PlumeMask(saturate(input.uv), input.normalWS, intensity,
                    _PlumeFacing, _PlumePower, _PlumeEdge, _PlumeFilaments, _PlumeTurbulence,
                    _PlumeSpeed, _PlumeCells, _WarpFlowPhase, travel, facing);
                clip(mask * saturate(_PlumeIntensity) - saturate(_PlumeDepthAlphaMin));

                outNormalWS = float4(NormalizeNormalPerPixel(normalize(input.normalWS)), 0.0f);
            }
            ENDHLSL
        }
    }
}