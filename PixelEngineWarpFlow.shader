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
        _Accel("Acceleration Exponent (speed ratio e^k across path)", Float) = 2
        _RayPath("Ray Path (UV length)", Float) = 1.2

        [Header(Size)]
        _RayWidth("Ray Width (sector fraction)", Range(0.05, 1)) = 0.35
        _TailSharp("Tail Sharpness (streak length along ray)", Range(0.5, 8)) = 3
        _Stagger("Ray Stagger (cycle spread)", Range(0, 2)) = 1
        _StaggerOffset("Streak Offset (lane fraction, signed)", Range(0, 1)) = 0.5
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
        _PixelScale("Pixel Scale (grid cells per streak pixel)", Range(1, 8)) = 2

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
                float _StaggerOffset;
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
                float _PixelScale;
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
                // Blit flip compensation, the UI/Default convention: a
                // Graphics.Blit into a texture flips the v axis on the
                // top-first graphics device APIs. The rig blits this shader
                // into the warp texture, and the canvas samples the texture
                // unflipped, so the compensation keeps the vanishing point on
                // the side the projection names.
                float2 uv = attributes.uv;
#if defined(UNITY_UV_STARTS_AT_TOP)
                if (_ProjectionParams.x < 0.0)
                {
                    uv.y = 1.0 - uv.y;
                }
#endif
                varyings.uv = uv;
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
            // Comets: each ray carries its own streak heads, and the flow is a
            // steady accelerating stream: a streak's speed answers its distance
            // from the vanishing point and never the clock. Speed grows
            // exponentially along the path — e^_Accel times from the point to
            // the path end — so a streak runs slow at the point, gathers speed,
            // and crosses the edge fast; the near and far fades hide the spawn
            // and the death, and the cycle wrap stays seamless because the
            // travel coordinate spans exactly the streak count in wavelengths.
            // Under AxialSign +1 the stream runs outward; under -1 the same
            // field runs inward, so the converging streaks recede from the
            // edge toward the point, gathering speed as they go and arriving
            // slow at the point, the recede read. The first landing ran the
            // head along the path on the cycle clock, so every streak's speed
            // rode the cycle profile and reset fast-to-slow when the cycle
            // restarted mid-flight — a flow that ended too early and a speed
            // that kicked; the report read it as an animation loop. No
            // distance-times-time term exists in either model, so no pole and
            // no reversal; the play-mode mirror at the retired pole time
            // (12 / (0.3 x 0.6) = 66.7 s) stands.
            // The consuming rig writes _RayPath per pose, running it past the
            // farthest screen corner: the side and nadir views land the point off
            // screen, and the visible screen then starts at a larger distance, so
            // a path shorter than that corner puts every visible pixel past the
            // far fade.
            //
            // Length bands: brightness ramps along the streak, brightest at the
            // head and fading to the tail, quantized through Posterize, the
            // PixelEngineLit linear light quantization, so the ramp presents as
            // bands and no gradient. _TailSharp sets the streak length along the
            // ray. _Stagger spreads each ray's cycle phase, so rays run out of
            // step; 0 runs them in phase. _StaggerOffset offsets each streak's
            // arc left or right of its sector center, signed by a hash of the
            // ray and the streak's cell index, so streaks run out of line
            // laterally, at random; the offset holds for the streak's whole run,
            // and 0 runs them on the center line. The UV answers on the warp
            // texture's grid cell times _PixelScale: the rig renders the
            // texture at screen resolution divided by its render scale and
            // the canvas upscales it point-filtered, so the streak pixels are
            // whole, uniform, and answer no screen-resolution grid.
            //
            // Color: the majority of rays answer the base color. _ColorIntensity
            // is the fraction that carries a palette color instead, one of
            // _RayColor1..3 picked per ray by the ray hash, discrete and not
            // blended. _RaySeed moves the picks. The HDR gain multiplies the
            // band above 1.0, the contract for a layer riding an HDR post path.
            // Travel-time coordinate: the clock a streak needs to reach path
            // coordinate c in a flow whose speed grows exponentially along the
            // path. It is the inverse of the head curve h(tau) = (exp(k tau) - 1)
            // / (exp(k) - 1), so the speed a point answers is h'(h^-1(c)) =
            // rate x k x exp(k c) / (exp(k) - 1): set by the distance, steady in
            // time, ratio exp(k) from the vanishing point to the path end.
            // Streak spacing inherits the speed: gaps grow toward the edge, the
            // spreading the accelerating flow must answer.
            float WarpTravelTime(float c, float accel)
            {
                float k = max(accel, 0.001f);
                return log(1.0 + c * (exp(k) - 1.0)) / k;
            }

            half4 frag(Varyings varyings) : SV_Target
            {
                // Streak pixels ride the warp texture's grid cell times the
                // authored pixel scale: the rig writes the cell as one warp
                // texture pixel, so a streak pixel is render scale x pixel
                // scale screen pixels wide, uniform across the frame.
                float2 cell = _GridCell.xy * max(_PixelScale, 1.0);
                float2 p = floor(varyings.uv / cell) * cell + 0.5 * cell;

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

                // Cycle coordinate: the flow clock, uniform across the screen
                // and bounded in [0, 1). _Stagger spreads the per-ray phase
                // over cycle fractions, so rays run their streaks out of step.
                float tau = frac(_FlowRate * _Time.y + rayPhase * _Stagger);

                // Path coordinate along the ray: 0 at the vanishing point,
                // 1 at the path end. The travel coordinate converts it to the
                // steady-flow clock, so the streak speed answers the distance
                // and the wrap drop is exactly the streak count.
                float c = dist / max(_RayPath, 0.01f);
                float travel = WarpTravelTime(c, _Accel);

                // Streak coordinate: u = 0 at the head, u -> 1 at the tail,
                // measured from head to tail along the way the streak came, so
                // the tail trails the head's travel. Diverging, the stream runs
                // outward: tau - travel falls with distance, so the tail lies
                // toward the point and the head runs outward ahead of it.
                // Converging, the stream runs inward: travel - (1 - tau) rises
                // with distance, so the tail lies toward the edge and the head
                // arrives at the point. In both signs the cycle wrap moves the
                // coordinate by exactly the streak count, so the integer count
                // and the slot rule keep the wrap seamless.
                // The cell index k names each streak along the ray and travels
                // with it, so a hash of (ray, k) is a per-streak number that
                // holds while the streak runs.
                float streakCoord = (_AxialSign > 0)
                    ? _StreakDensity * (tau - travel)
                    : _StreakDensity * (travel - (1.0 - tau));
                float streakIndex = floor(streakCoord);
                float u = frac(streakCoord);

                // Lateral stagger: the per-streak hash signs an offset of the
                // arc center inside its sector, so each streak runs left or
                // right of the ray's center line, randomly, and the offset
                // holds for the streak's whole run. The hash is indexed by the
                // streak's slot in the ray, counted modulo the streak count:
                // the cycle wrap shifts every streak index by the count — the
                // brightness is immune, because the pattern repeats every
                // wavelength, and a slot index past the count would inherit
                // the next slot's hash, so the whole configuration would swap
                // offsets at every wrap — the configuration snap, once per
                // cycle, read at the long streaks near the screen edge. The
                // slot modulo the count is invariant across the wrap and
                // constant while the streak travels, so the configuration
                // stands. The lane travel is the free half-space each side of
                // center, (1 - _RayWidth) / 2, so an offset of 1 lands the
                // streak edge on the sector border and rays never cross. The
                // offset is angular, so the streak runs a line pivoted on the
                // vanishing point: it spawns at the point and fans out, and
                // in the parallel side views the same shift reads as a
                // lateral displacement.
                float density = max(_StreakDensity, 1.0);
                float slot = fmod(fmod(streakIndex, density) + density, density);
                float offsetHash = WarpHash(rayIndex * 17.13 + slot * 5.17 + _RaySeed * 7.91) * 2.0 - 1.0;
                float lane = 0.5 * (1.0 - max(_RayWidth, 0.01f));
                float arcCenter = 0.5 + offsetHash * _StaggerOffset * lane;
                float arc = saturate(1.0 - abs(sectorPos - arcCenter) * 2.0 / max(_RayWidth, 0.01f));

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
