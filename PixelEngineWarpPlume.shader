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
// The draw state is authored on the material: source and destination blend, depth write, cull mode, and
// the double sided normals toggle. The shipped state is SrcAlpha over OneMinusSrcAlpha, no depth write,
// cull off, and the double sided rule on. The queue is Transparent, which is where Unity sorts by camera
// distance, and a surface that writes no depth needs that sorting. The surface writes no depth and joins
// no depth prepass, so it occludes nothing and is occluded by the hull it wraps.
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
        _PlumeFacingFloor("Facing Floor (the brightness a surface keeps at a right angle to travel and eye)", Range(0, 1)) = 0.35
        _PlumeEdge("Wrap End Taper", Range(0.01, 8)) = 1.5
        _PlumeFilaments("Filament Count", Range(1, 64)) = 14
        _PlumeFilamentsFloor("Filament Floor (the brightness the sheath stands at between pulses)", Range(0, 1)) = 0.65
        _PlumeTurbulence("Filament Length Scale", Range(0.05, 8)) = 1.2
        _PlumeSpeed("Scroll Speed", Range(0, 8)) = 1
        _PlumeCells("Grain Cells", Range(1, 128)) = 28
        [Header(Transparency and Blending)]
        [Enum(UnityEngine.Rendering.BlendMode)] _SrcBlend("Source Blend", Float) = 5
        [Enum(UnityEngine.Rendering.BlendMode)] _DstBlend("Destination Blend", Float) = 10
        [Toggle] _ZWrite("Depth Write", Float) = 0
        [Enum(UnityEngine.Rendering.CullMode)] _Cull("Cull Mode", Float) = 0
        [Enum(UnityEngine.Rendering.CompareFunction)] _ZTest("Depth Test (Always draws over what it covers)", Float) = 4
        [Toggle(_PREMULTIPLY_ALPHA)] _Premultiply("Premultiply Alpha (pairs with One / OneMinusSrcAlpha)", Float) = 1
        [Toggle(_DOUBLE_SIDED_NORMALS)] _DoubleSided("Double Sided Normals", Float) = 1

        [Header(Debug)]
        [Toggle(_DEBUG_PLUME)] _DebugRender("Debug Render (flat colour, reads no warp state)", Float) = 0
        _PlumeDebugIntensity("Debug Intensity Override (0 reads the warp seam)", Range(0, 1)) = 0
        [HideInInspector] _PlumeDebugAlpha("Debug Alpha Override (0 keeps the authored mask)", Range(0, 1)) = 0
    }

    SubShader
    {
        Tags { "Queue" = "Transparent" }
        Tags
        {
            "RenderType" = "Transparent"
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
            float _PlumeFacingFloor;
            float _PlumeEdge;
            float _PlumeFilaments;
            float _PlumeFilamentsFloor;
            float _PlumeTurbulence;
            float _PlumeSpeed;
            float _PlumeCells;
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
                UNITY_DOTS_INSTANCED_PROP(float, _PlumeFacingFloor)
                UNITY_DOTS_INSTANCED_PROP(float, _PlumeEdge)
                UNITY_DOTS_INSTANCED_PROP(float, _PlumeFilaments)
                UNITY_DOTS_INSTANCED_PROP(float, _PlumeFilamentsFloor)
                UNITY_DOTS_INSTANCED_PROP(float, _PlumeTurbulence)
                UNITY_DOTS_INSTANCED_PROP(float, _PlumeSpeed)
                UNITY_DOTS_INSTANCED_PROP(float, _PlumeCells)
                UNITY_DOTS_INSTANCED_PROP(float, _PlumeDebugIntensity)
                UNITY_DOTS_INSTANCED_PROP(float, _PlumeDebugAlpha)
            UNITY_DOTS_INSTANCING_END(MaterialPropertyMetadata)

            #define _PlumeColor         UNITY_ACCESS_DOTS_INSTANCED_PROP_WITH_DEFAULT(float4, _PlumeColor)
            #define _PlumeHotColor      UNITY_ACCESS_DOTS_INSTANCED_PROP_WITH_DEFAULT(float4, _PlumeHotColor)
            #define _PlumeIntensity     UNITY_ACCESS_DOTS_INSTANCED_PROP_WITH_DEFAULT(float, _PlumeIntensity)
            #define _PlumePower         UNITY_ACCESS_DOTS_INSTANCED_PROP_WITH_DEFAULT(float, _PlumePower)
            #define _PlumeFacing        UNITY_ACCESS_DOTS_INSTANCED_PROP_WITH_DEFAULT(float, _PlumeFacing)
            #define _PlumeFacingFloor   UNITY_ACCESS_DOTS_INSTANCED_PROP_WITH_DEFAULT(float, _PlumeFacingFloor)
            #define _PlumeEdge          UNITY_ACCESS_DOTS_INSTANCED_PROP_WITH_DEFAULT(float, _PlumeEdge)
            #define _PlumeFilaments     UNITY_ACCESS_DOTS_INSTANCED_PROP_WITH_DEFAULT(float, _PlumeFilaments)
            #define _PlumeFilamentsFloor UNITY_ACCESS_DOTS_INSTANCED_PROP_WITH_DEFAULT(float, _PlumeFilamentsFloor)
            #define _PlumeTurbulence    UNITY_ACCESS_DOTS_INSTANCED_PROP_WITH_DEFAULT(float, _PlumeTurbulence)
            #define _PlumeSpeed         UNITY_ACCESS_DOTS_INSTANCED_PROP_WITH_DEFAULT(float, _PlumeSpeed)
            #define _PlumeCells         UNITY_ACCESS_DOTS_INSTANCED_PROP_WITH_DEFAULT(float, _PlumeCells)
            #define _PlumeDebugIntensity UNITY_ACCESS_DOTS_INSTANCED_PROP_WITH_DEFAULT(float, _PlumeDebugIntensity)
            #define _PlumeDebugAlpha    UNITY_ACCESS_DOTS_INSTANCED_PROP_WITH_DEFAULT(float, _PlumeDebugAlpha)
        #endif

        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            Blend [_SrcBlend] [_DstBlend]
            ZWrite [_ZWrite]
            ZTest [_ZTest]
            Cull [_Cull]

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 4.5
            #pragma multi_compile_instancing
            #pragma instancing_options renderinglayer
            #pragma multi_compile _ DOTS_INSTANCING_ON
            #pragma shader_feature_local _DEBUG_PLUME
            #pragma shader_feature_local_fragment _DOUBLE_SIDED_NORMALS
            #pragma shader_feature_local_fragment _PREMULTIPLY_ALPHA

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
                float3 positionWS : TEXCOORD2;
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
                output.positionWS = positionWS;
                output.uv = input.uv;
                return output;
            }

            float4 frag(Varyings input, bool isFrontFace : SV_IsFrontFace) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);

#if defined(_DOUBLE_SIDED_NORMALS)
                // Cull Off draws the far side of the arc as well as the near side, and the cap normals
                // point outward from the arc axis, so the far side carries a normal that points away
                // from the eye. The facing term reads that normal, so without the flip the far side
                // dims the way a wrap does and the sheath reads asymmetric as the camera swings behind.
                float3 normalWS = isFrontFace ? input.normalWS : -input.normalWS;
#else
                float3 normalWS = input.normalWS;
#endif

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
                // The travel direction alone kills the outer band of a sweep authored wider than a half
                // circle: a cap normal at a right angle to the travel answers zero, and a normal past that
                // answers zero after saturation. The measured cost on the authored 220 degree sweep is the
                // outer 44 degrees on each side, which is 40 percent of the arc drawn at zero alpha, and
                // that zero is computed inside the surface, so no depth test setting brings those pixels
                // back. A surface is lit by the travel, which is the hot bow band, or by the eye, which is
                // the part of the sheath the camera is looking at, and the floor is what a surface keeps at
                // a right angle to both.
                float3 viewDirectionWS = normalize(GetWorldSpaceViewDir(input.positionWS));
                float facingLit = max(saturate(dot(normalize(normalWS), travel)), saturate(dot(viewDirectionWS, normalize(normalWS))));
                float facing = lerp(saturate(_PlumeFacingFloor), 1.0f, pow(facingLit, max(_PlumeFacing, 0.01f)));
                float mask = PlumeMask(uv, normalWS, intensity, _PlumeFacing, _PlumePower,
                    _PlumeEdge, _PlumeFilaments, _PlumeFilamentsFloor, _PlumeTurbulence, _PlumeSpeed,
                    _PlumeCells, _WarpFlowPhase, travel, facing);
                // The alpha a transparent surface outputs is the number the blend multiplies by, so it is
                // the whole answer about opacity. Three numbers own it: the brightness mask, the authored
                // strength, and the authored colour alpha. The colour alpha is an author's knob and the
                // code must read it, because a colour with no alpha effect on an alpha-blended surface
                // is a knob that does not turn.
                float alpha = saturate(mask * _PlumeIntensity * _PlumeColor.a);
                if (saturate(_PlumeDebugAlpha) > 0.0f)
                {
                    // A measurement pins the alpha without touching the mask terms. The shipped material
                    // stands at zero here, which is the path the code takes.
                    alpha = saturate(_PlumeDebugAlpha * intensity);
                }

                float3 colour = lerp(_PlumeColor.rgb, _PlumeHotColor.rgb,
                    pow(saturate(1.0f - uv.y), 3.0f) * facing);

#if defined(_PREMULTIPLY_ALPHA)
                // Premultiplied: the colour arrives carrying its alpha. The blend pair One /
                // OneMinusSrcAlpha then adds the plasma's brightness where it covers and keeps the
                // background where it does not, so a thin pixel is a dim plasma and not a window onto
                // the scene. Straight alpha, the other branch, multiplies the source by alpha at the
                // blend, which is the shape that dims an emissive surface toward its background.
                return float4(colour * alpha, alpha);
#else
                return float4(colour, alpha);
#endif
            }
            ENDHLSL
        }

    }
}