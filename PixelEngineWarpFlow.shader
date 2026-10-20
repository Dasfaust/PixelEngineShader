Shader "PixelEngine/Warp Flow"
{
    Properties
    {
        [Header(Flow Field)]
        _VanishPoint("Vanishing Point (UV)", Vector) = (0.5, 0.5, 0, 0)
        _AxialSign("Axial Sign (diverge 1, converge -1)", Float) = 1
        _RayCount("Ray Count", Float) = 24
        _StreakDensity("Streak Density (per UV width)", Float) = 12

        [Header(Motion)]
        _FlowRate("Flow Rate", Float) = 0.3
        _SpeedGain("Speed Gain with Distance", Float) = 0.6

        [Header(Look)]
        _BandCount("Brightness Bands", Float) = 4
        _NearFade("Near Fade (per UV distance)", Float) = 6
        _StreakColor("Streak Color", Color) = (0.75, 0.85, 1, 1)
        _Intensity("Intensity", Float) = 0

        [Header(Grid)]
        _GridCell("Grid Cell (UV xy)", Vector) = (0.005, 0.005, 0, 0)

        [Header(UI)]
        // UGUI's canvas path requires _MainTex on a UI material; RawImage
        // supplies no texture, so the property is declared, hidden, and
        // sampled nowhere. Without it every canvas rebuild logs "Material
        // 'WarpFlow' with Shader 'PixelEngine/Warp Flow' doesn't have a
        // texture property '_MainTex'" out of Canvas.SendWillRenderCanvases.
        [HideInInspector] _MainTex("Main Texture", 2D) = "white" { }
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
            Name "WarpFlow"

            Cull Off
            ZWrite Off
            ZTest [unity_GUIZTestMode]
            Blend SrcAlpha OneMinusSrcAlpha

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            // Declared so the canvas texture binding the RawImage path makes
            // has a target; the shader samples nothing from it.
            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);

            // Posterize, the PixelEngineLit linear light quantization
            // (ShaderLibrary/Common.hlsl), inlined so this shader carries no
            // include chain beyond Core.hlsl.
            #define WARP_PI 3.141592653589793

            float PosterizeLocal(float value, float steps)
            {
                return floor(value * steps) / steps;
            }

            CBUFFER_START(UnityPerMaterial)
                float4 _VanishPoint;
                float _AxialSign;
                float _RayCount;
                float _StreakDensity;
                float _FlowRate;
                float _SpeedGain;
                float _BandCount;
                float _NearFade;
                float4 _StreakColor;
                float _Intensity;
                float4 _GridCell;
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
                varyings.uv = attributes.uv;
                varyings.positionWS = TransformObjectToWorld(attributes.positionOS.xyz);
                return varyings;
            }

            // The flow field of a fixed travel vector seen from a rotating view,
            // authored as virtual perspective: one vanishing point drives everything.
            //
            // Rays: quantized angles through the vanishing point. A near point fans
            // them into the cone; a far point flattens them into parallel streaks,
            // so the side views need no special case.
            //
            // Pulses: streaks travel along a ray's distance from the vanishing
            // point, outward under AxialSign +1 and inward under -1, so diverge,
            // converge, and parallel are one field with the sign and the distance.
            // Speed grows with the distance, the acceleration read.
            //
            // Bands: the brightness answers through Posterize, the PixelEngineLit
            // linear light quantization, so the streaks present as bands and no
            // gradient. The UV answers on the render-texture grid cell, so the
            // streaks share the world's pixel size.
            half4 frag(Varyings varyings) : SV_Target
            {
                float2 p = floor(varyings.uv / _GridCell.xy) * _GridCell.xy + 0.5 * _GridCell.xy;

                float2 d = p - _VanishPoint.xy;
                float dist = length(d);
                float ang = atan2(d.y, d.x);

                // One ray phase per ray index, so rays stream out of step.
                float rayIndex = floor(ang * _RayCount * 100.0 / WARP_PI);
                float rayPhase = frac(sin(rayIndex * 12.9898) * 43758.5453);

                float speed = 0.25 + dist * _SpeedGain;
                // The sign rides the distance term only: it flips the pulse
                // direction, +1 outward from the vanishing point and -1 inward.
                // Riding the time term too would leave the direction fixed and
                // flip only the phase.
                float pulse = frac(dist * _StreakDensity * _AxialSign - _FlowRate * _Time.y * speed + rayPhase);
                float ridge = 1.0 - abs(2.0 * pulse - 1.0);

                float nearFade = saturate(dist * _NearFade);
                float value = ridge * nearFade * saturate(_Intensity);
                float band = PosterizeLocal(value, _BandCount);

                half4 color = _StreakColor * band;
                color.a *= varyings.color.a;

                // Canvas RectMask2D clip, the UI/Default shape: the mask is the
                // distance to the clip rect edges, floored by the softness inset,
                // saturate-masked, and scaled by the mask mode in ClipRectMin.w.
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
