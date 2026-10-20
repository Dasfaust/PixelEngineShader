Shader "PixelEngine/Warp Flow"
{
    Properties
    {
        [Header(Flow Field)]
        _VanishPoint("Vanishing Point (UV)", Vector) = (0.5, 0.5, 0, 0)
        _AxialSign("Axial Sign (diverge 1, converge -1)", Float) = 1
        _RayCount("Ray Count", Float) = 24

        [Header(Motion)]
        _FlowRate("Flow Rate", Float) = 0.3
        _Accel("Acceleration Exponent (0 linear, 2..4 accelerating)", Float) = 2
        _RayPath("Ray Path (UV length)", Float) = 1.2

        [Header(Size)]
        _RayWidth("Ray Width (sector fraction)", Range(0.05, 1)) = 0.35
        _TailSharp("Tail Sharpness (streak length along ray)", Range(0.5, 8)) = 3
        _Stagger("Ray Stagger (cycle spread)", Range(0, 2)) = 1
        _StreakDensity("Streak Density (streaks per ray)", Float) = 12

        [Header(Look)]
        _BandCount("Brightness Bands", Float) = 4
        _NearFade("Near Fade (per UV distance)", Float) = 6
        _FarFade("Far Fade (per UV distance at path end)", Float) = 3
        _BaseColor("Base Color", Color) = (0.72, 0.84, 1, 1)
        _RayColor1("Ray Color 1", Color) = (0.35, 0.85, 1, 1)
        _RayColor2("Ray Color 2", Color) = (0.62, 0.45, 1, 1)
        _RayColor3("Ray Color 3", Color) = (1, 0.72, 0.4, 1)
        _ColorIntensity("Color Intensity (fraction of colored rays)", Range(0, 1)) = 0.3
        _RaySeed("Ray Seed", Float) = 0
        _Intensity("Intensity", Float) = 0

        [Header(HDR)]
        // The gain pushes the band above 1.0 so the streaks read hot and
        // bloom where the layer rides an HDR post path. The overlay canvas
        // composites after the camera's post stack, so the canvas path
        // clamps the value; the gain is the camera-path contract.
        _HDRGain("HDR Gain", Range(1, 8)) = 2

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
                float _FlowRate;
                float _Accel;
                float _RayPath;
                float _RayWidth;
                float _TailSharp;
                float _Stagger;
                float _StreakDensity;
                float _BandCount;
                float _NearFade;
                float _FarFade;
                float4 _BaseColor;
                float4 _RayColor1;
                float4 _RayColor2;
                float4 _RayColor3;
                float _ColorIntensity;
                float _RaySeed;
                float _Intensity;
                float _HDRGain;
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

            // One hash, used for the ray phase and the per-ray color pick.
            float WarpHash(float x)
            {
                return frac(sin(x) * 43758.5453);
            }

            // The flow field of a fixed travel vector seen from a rotating view,
            // authored as virtual perspective: one vanishing point drives everything.
            //
            // Rays: quantized angles through the vanishing point. A near point fans
            // them into the cone; a far point flattens them into parallel streaks,
            // so the side views need no special case. _RayCount sets the density
            // and _RayWidth the ray size, as a fraction of each angular sector.
            //
            // Comets: each ray carries its own streak heads that travel along the
            // ray from the vanishing point outward under AxialSign +1 and inward
            // under -1, so diverge, converge, and parallel are one field with the
            // sign and the distance. A head runs one cycle in 1 / _FlowRate, and
            // _Accel warps the cycle so the head speeds up along the path — the
            // acceleration read, and for the converge side it arrives fast. The
            // head position is bounded inside the cycle, so the pattern never
            // reverses; the first landing advected a distance-proportional speed
            // against unbounded time, and its ring positions crossed a pole at
            // (ray path scale) / (flow rate x speed gain), which read as reversal.
            //
            // Length bands: brightness ramps along the streak, brightest at the
            // head and fading to the tail, quantized through Posterize, the
            // PixelEngineLit linear light quantization, so the ramp presents as
            // bands and no gradient. _TailSharp sets the streak length along the
            // ray. _Stagger spreads each ray's cycle phase, so rays run out of
            // step; 0 runs them in phase. The UV answers on the render-texture
            // grid cell, so the streaks share the world's pixel size.
            //
            // Color: the majority of rays answer the base color. _ColorIntensity
            // is the fraction that carries a palette color instead, one of
            // _RayColor1..3 picked per ray by the ray hash, discrete and not
            // blended. _RaySeed moves the picks. The HDR gain multiplies the
            // band above 1.0, the contract for a layer riding an HDR post path.
            // Head position along one cycle: h(0) = 0 at the vanishing point,
            // h(1) = 1 at the path end. _Accel 0 answers the linear h = tau; a
            // positive exponent runs the head faster late in the cycle, the
            // acceleration read.
            float WarpHead(float tau, float accel)
            {
                float k = max(accel, 0.001f);
                return (exp(k * tau) - 1.0) / (exp(k) - 1.0);
            }

            half4 frag(Varyings varyings) : SV_Target
            {
                float2 p = floor(varyings.uv / _GridCell.xy) * _GridCell.xy + 0.5 * _GridCell.xy;

                float2 d = p - _VanishPoint.xy;
                float dist = length(d);
                float ang = atan2(d.y, d.x);

                // Sector coordinates: the ray index sets the cycle phase and the
                // color pick, and the position inside the sector answers the arc
                // mask, so _RayWidth sets the ray size in fraction of a sector.
                float sector = ang * _RayCount / (2.0 * WARP_PI);
                float rayIndex = floor(sector);
                float sectorPos = frac(sector);
                float rayPhase = WarpHash(rayIndex * 12.9898);
                float colorHash = WarpHash(rayIndex * 7.13 + _RaySeed * 3.71);
                float pickHash = WarpHash(rayIndex * 31.71 + _RaySeed * 11.3);

                float arc = saturate(1.0 - abs(sectorPos - 0.5) * 2.0 / max(_RayWidth, 0.01f));

                // Cycle coordinate, uniform in the ray and bounded in [0, 1):
                // no distance-times-time shear, so no pole, so no reversal.
                // _Stagger spreads the per-ray phase over cycle fractions, so
                // rays run their streaks out of step.
                float tau = frac(_FlowRate * _Time.y + rayPhase * _Stagger);
                float head = WarpHead(tau, _Accel);

                // Path coordinate along the ray: 0 at the vanishing point,
                // 1 at the path end.
                float c = dist / max(_RayPath, 0.01f);

                // Streak coordinate: u = 0 at a head, u -> 1 at its tail.
                // Diverging, the head runs outward, so the tail trails inward:
                // u rides (head - c). Converging, the head runs inward
                // (1 - head) and accelerates toward the point, so the tail
                // trails outward: u rides (c - (1 - head)).
                float u = (_AxialSign > 0)
                    ? frac(_StreakDensity * (head - c))
                    : frac(_StreakDensity * (c - (1.0 - head)));

                // Ramp along the streak: brightest at the head, fading to the
                // tail over the wavelength. _TailSharp sets the streak length.
                float ramp = pow(1.0 - u, max(_TailSharp, 0.01f));

                // Fades hide the cycle ends: the near fade covers the spawn
                // at the vanishing point, the far fade covers the death at
                // the path end, so a cycle wrap reads as flow and not as pop.
                float nearFade = saturate(dist * _NearFade);
                float farFade = saturate((_RayPath - dist) * _FarFade);
                float value = ramp * arc * nearFade * farFade * saturate(_Intensity);
                float band = PosterizeLocal(value, _BandCount);

                // Majority base: a ray carries a palette color only where the
                // color hash lands under _ColorIntensity, the fraction of
                // colored rays. The pick hash names which of the three. The
                // answer is discrete, not blended onto the base.
                float4 pick = _RayColor1;
                pick = (pickHash > 0.3333) ? _RayColor2 : pick;
                pick = (pickHash > 0.6666) ? _RayColor3 : pick;
                float4 rayColor = (colorHash < _ColorIntensity) ? pick : _BaseColor;

                // HDR: the gain pushes the band above 1.0. The blend keeps the
                // alpha in 0..1 and the rgb carries the gain.
                half4 color = 0;
                color.rgb = rayColor.rgb * band * _HDRGain;
                color.a = band * varyings.color.a;

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
