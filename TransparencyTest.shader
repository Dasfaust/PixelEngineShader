Shader "PixelEngine/TransparencyTest"
{
    Properties
    {
        [Header(Surface Options)]
        [MainTexture] _BaseMap("Base Map (RGB) Alpha (A)", 2D) = "white" {}
        [MainColor] _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        
        [Header(Transparency and Blending)]
        [Enum(UnityEngine.Rendering.BlendMode)] _SrcBlend("Source Blend", Float) = 5 // SrcAlpha
        [Enum(UnityEngine.Rendering.BlendMode)] _DstBlend("Destination Blend", Float) = 10 // OneMinusSrcAlpha
        [Toggle] _ZWrite("Depth Write (ZWrite)", Float) = 0
        [Enum(UnityEngine.Rendering.CullMode)] _Cull("Cull Mode", Float) = 2 // Back
        
        [Header(Alpha Clipping)]
        [Toggle(_ALPHATEST_ON)] _AlphaClip("Enable Alpha Clip", Float) = 0
        _Cutoff("Alpha Cutoff", Range(0.0, 1.0)) = 0.5
    }

    SubShader
    {
        Tags 
        { 
            "RenderType" = "Transparent" 
            "Queue" = "Transparent" 
            "RenderPipeline" = "UniversalPipeline" 
            "IgnoreProjector" = "True"
        }

        // Common HLSL shared across passes to guarantee SRP Batcher compatibility
        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half4 _BaseColor;
            half _Cutoff;
        CBUFFER_END

        TEXTURE2D(_BaseMap);
        SAMPLER(sampler_BaseMap);
        ENDHLSL

        // ------------------------------------------------------------------
        // 1. FORWARD LIT / UNLIT PASS
        // ------------------------------------------------------------------
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            Blend [_SrcBlend] [_DstBlend]
            ZWrite [_ZWrite]
            Cull [_Cull]

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            // Material Keywords
            #pragma shader_feature_local_fragment _ALPHATEST_ON

            // URP Keywords (Forward+ / Clustered lighting & Fog)
            #pragma multi_compile _ _FORWARD_PLUS
            #pragma multi_compile_fog

            // GPU Instancing
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS   : POSITION;
                float3 normalOS     : NORMAL;
                float2 uv           : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS   : SV_POSITION;
                float2 uv           : TEXCOORD0;
                float3 positionWS   : TEXCOORD1;
                float3 normalWS     : TEXCOORD2;
                half fogFactor      : TEXCOORD3;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings vert(Attributes input)
            {
                Varyings output = (Varyings)0;

                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS);

                output.positionCS = vertexInput.positionCS;
                output.positionWS = vertexInput.positionWS;
                output.normalWS = normalInput.normalWS;
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                output.fogFactor = ComputeFogFactor(vertexInput.positionCS.z);

                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                // Sample Texture and Tint
                half4 texColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv);
                half4 color = texColor * _BaseColor;

                // Optional Alpha Clipping
                #if defined(_ALPHATEST_ON)
                    clip(color.a - _Cutoff);
                #endif

                // Simple Main Light NdotL + Ambient (Strip this block if you want pure Unlit)
                Light mainLight = GetMainLight();
                half3 normalWS = normalize(input.normalWS);
                half NdotL = saturate(dot(normalWS, mainLight.direction));
                half3 ambient = SampleSH(normalWS);
                half3 lighting = mainLight.color * NdotL + ambient;
                
                color.rgb *= lighting;

                // Apply Scene Fog
                color.rgb = MixFog(color.rgb, input.fogFactor);

                return color;
            }
            ENDHLSL
        }

        // ------------------------------------------------------------------
        // 2. DEPTH ONLY PASS (Used if ZWrite is enabled or for Depth Prepass)
        // ------------------------------------------------------------------
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }

            ZWrite [_ZWrite]
            ColorMask R
            Cull [_Cull]

            HLSLPROGRAM
            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment

            #pragma shader_feature_local_fragment _ALPHATEST_ON
            #pragma multi_compile_instancing

            struct Attributes
            {
                float4 positionOS   : POSITION;
                float2 uv           : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS   : SV_POSITION;
                float2 uv           : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings DepthOnlyVertex(Attributes input)
            {
                Varyings output = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                return output;
            }

            half4 DepthOnlyFragment(Varyings input) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                #if defined(_ALPHATEST_ON)
                    half alpha = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv).a * _BaseColor.a;
                    clip(alpha - _Cutoff);
                #endif

                return 0;
            }
            ENDHLSL
        }
    }
}