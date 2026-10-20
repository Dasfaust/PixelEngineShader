Shader "PixelEngine/Atlas UI Sample"
{
    Properties
    {
        _MainTex("Atlas", 2D) = "white" {}

        [Header(Sampling)]
        [Toggle(_TEXEL_BLEND)] _TexelBlend("Blend at sub-texel scale", float) = 0

        [Header(UI)]
        [HideInInspector] _ClipRect("Clip Rect", Vector) = (-32767, -32767, 32767, 32767)
        [HideInInspector] _ClipRectMin("Clip Rect Min", Vector) = (-32767, -32767, -32767, 1)
        [HideInInspector] _MaskSoftnessX("Mask Softness X", float) = 0
        [HideInInspector] _MaskSoftnessY("Mask Softness Y", float) = 0
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Transparent"
            "Queue" = "Transparent"
            "IgnoreProjector" = "True"
        }

        Pass
        {
            Name "AtlasSample"

            Cull Off
            ZWrite Off
            ZTest [unity_GUIZTestMode]
            Blend SrcAlpha OneMinusSrcAlpha

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "ShaderLibrary/BilinearPointSampling.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            // Mode A (_TEXEL_BLEND): BilinearPointSamplingUV snaps UVs to texel
            // centers when a texel covers at least one pixel, and blends across the
            // texel edge when a texel minifies below one. Mode B (keyword off):
            // hard snap to texel centers. A quantized slide keeps the sampled texel
            // fixed, so the center sample returns one texel and no blend.
            #pragma shader_feature_local_fragment _ _TEXEL_BLEND

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float4 _MainTex_TexelSize;
                float4 _ClipRect;
                float4 _ClipRectMin;
                float2 _MaskSoftnessXY;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float4 color : COLOR;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float4 color : COLOR;
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
            };

            Varyings vert(Attributes attributes)
            {
                Varyings varyings;
                varyings.positionHCS = TransformObjectToHClip(attributes.positionOS.xyz);
                varyings.color = attributes.color;
                // RawImage bakes the uvRect into the geometry UVs, so the sampled
                // region arrives in atlas UV. The x can run outside 0..1: the
                // Repeat wrap carries the slide through the atlas edge.
                varyings.uv = attributes.uv;
                varyings.positionWS = TransformObjectToWorld(attributes.positionOS.xyz);
                return varyings;
            }

            half4 frag(Varyings varyings) : SV_Target
            {
                float2 texelUv;
                #if defined(_TEXEL_BLEND)
                    texelUv = BilinearPointSamplingUV(varyings.uv, _MainTex_TexelSize);
                #else
                    texelUv = (floor(varyings.uv * _MainTex_TexelSize.zw) + 0.5) * _MainTex_TexelSize.xy;
                #endif

                half4 color = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, texelUv);
                color *= varyings.color;

                // Canvas RectMask2D clip, the UI/Default shape: the mask is the
                // distance to the clip rect edges, floored by the softness inset,
                // saturate-masked, and scaled by the mask mode in ClipRectMin.w.
                // An unmasked RawImage gets a rect so wide the mask is 1.
                float2 rectMin = varyings.positionWS.xy - _ClipRect.xy + _MaskSoftnessXY;
                float2 rectMax = _ClipRect.zw - varyings.positionWS.xy - _MaskSoftnessXY;
                half mask = saturate(min(rectMin.x, rectMin.y) * _ClipRectMin.w);
                mask *= saturate(min(rectMax.x, rectMax.y) * _ClipRectMin.w);
                color.a *= mask;

                return color;
            }
            ENDHLSL
        }
    }
}
