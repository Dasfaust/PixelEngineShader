Shader "PixelEngineSubpixelViewport"
{
    Properties
    {
        _MainTex("Base Map", 2D) = "white" {}

        [Header(Viewport Properties)]
        _ZoomLevel("Zoom Level", float) = 1
        _SubPixelOffset("Subpixel UV Offset", vector) = (0, 0, 0, 0)

        [Header(Color Options)]
        [NoScaleOffset] _Palette("Color Palette", 2D) = "white" { }
        [Toggle(_QUANTIZE_COLORS)] _QuantizeColors("Quantize to Palette", float) = 0
        [KeywordEnum(RGB, CIELab)] _Quantize_Space("Quantization Color Space", float) = 0

        [Header(Rendering Options)]
        _Cutoff("Alpha Clip Threshold", Range(0, 1)) = 0.5
        [HideInInspector] _SurfaceType("Surface Type", Integer) = 0
        [HideInInspector] _Cull("Cull Mode", float) = 2
        [HideInInspector] _SrcBlend("Source Blend", float) = 1
        [HideInInspector] _DstBlend("Destination Blend", float) = 0
        [HideInInspector] _ZWrite("ZWrite ", float) = 1
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
        }

        Pass
        {
            Name "ForwardUnlit"
            
            Cull [_Cull]
            ZWrite [_ZWrite]
            Blend [_SrcBlend] [_DstBlend]
            
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "ShaderLibrary/BilinearPointSampling.hlsl"
            #include "ShaderLibrary/ColorOperations.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            #pragma shader_feature_local_fragment _ _ALPHA_CUTOUT
            #pragma shader_feature_local_fragment _ _QUANTIZE_COLORS
            #pragma shader_feature_local_fragment _QUANTIZE_SPACE_RGB _QUANTIZE_SPACE_CIELAB

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            TEXTURE2D(_Palette);
            SAMPLER(sampler_Palette);

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float4 _MainTex_TexelSize;
                float4 _Palette_TexelSize;
                float _ZoomLevel;
                float4 _SubPixelOffset;
                float _Cutoff;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            Varyings vert(Attributes attributes)
            {
                Varyings varyings;
                varyings.positionCS = TransformObjectToHClip(attributes.positionOS.xyz);
                varyings.uv = TRANSFORM_TEX(attributes.uv, _MainTex);
                return varyings;
            }

            half4 frag(Varyings varyings) : SV_Target
            {
                float2 adjustedUv = ((varyings.uv - 0.5) / _ZoomLevel + 0.5) + _SubPixelOffset.xy;
                half4 originalColor = SAMPLE_TEXTURE2D_GRAD(_MainTex, sampler_MainTex,
                    BilinearPointSamplingUV(adjustedUv, _MainTex_TexelSize), ddx(adjustedUv), ddy(adjustedUv));
                
                #if defined(_ALPHA_CUTOUT)
                    clip(originalColor.a - _Cutoff);
                #endif

                #if !defined(_QUANTIZE_COLORS)
                return originalColor;
                #endif

                #if defined(_QUANTIZE_SPACE_CIELAB)
                originalColor = float4(RGBToLab(originalColor.rgb), originalColor.a);
                #endif

                int paletteWidth = (int)_Palette_TexelSize.z;
                half3 posterizedColor = 0;
                float minDistance = 3.402823466e+38;

                for (int i = 0; i < paletteWidth; ++i)
                {
                    float2 paletteUv = float2((i + 0.5) * _Palette_TexelSize.x, 0.5);
                    half3 paletteColor = SAMPLE_TEXTURE2D(_Palette, sampler_Palette, paletteUv).rgb;

                    #if defined(_QUANTIZE_SPACE_CIELAB)
                    float dist = distance(originalColor, RGBToLab(paletteColor));
                    #else
                    float dist = distance(originalColor, paletteColor);
                    #endif

                    if (dist < minDistance)
                    {
                        minDistance = dist;
                        posterizedColor = paletteColor;
                    }
                }

                return half4(posterizedColor, originalColor.a);
            }
            ENDHLSL
        }
    }

    CustomEditor "PixelEngine.Editor.PixelEngineShaderInspector"
}