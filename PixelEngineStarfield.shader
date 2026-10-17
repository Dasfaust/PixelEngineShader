Shader "Custom/PixelEngineStarfield"
{
    Properties
    {
        _StarColor("Star Color", Color) = (0.85, 0.9, 1.0, 1)
        _NebulaColor("Nebula Color", Color) = (0.25, 0.18, 0.42, 1)
        _CellSize("Cell Size (world units)", float) = 0.25
        _StarSize("Star Size (world units)", float) = 0.06
        _StarDensity("Star Density (0..1)", range(0, 1)) = 0.35
        _Brightness("Star Brightness", range(0, 4)) = 1.2
        _NebulaCell("Nebula Cell (world units)", float) = 1.5
        _NebulaStrength("Nebula Strength", range(0, 1)) = 0.18
        _PixelsPerUnit("Pixels Per Unit (game pixels per world unit)", float) = 64
        _ScreenPxPerUnit("Screen Pixels Per World Unit", float) = 64
    }

    // The pass skeleton mirrors "Universal Render Pipeline/Unlit" from this pipeline version:
    // its SubShader tags, state placement, LOD line, and keyword pragma set. The star field
    // quad drew full-screen with Unlit in the same slot, and drew nothing with a hand-written
    // URP pass in every probe (constant output, fresh material, queue override, command-buffer
    // DrawRenderer), so the difference lives in this skeleton, not in the pattern code.
    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "IgnoreProjector" = "True"
            "UniversalMaterialType" = "Unlit"
            "RenderPipeline" = "UniversalPipeline"
            "Queue" = "Background"
        }
        LOD 100

        Blend One Zero
        ZWrite On
        Cull Off

        Pass
        {
            Name "Starfield"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 2.0

            #pragma multi_compile_fragment _ _SCREEN_SPACE_OCCLUSION
            #pragma multi_compile_fragment _ _DBUFFER_MRT1 _DBUFFER_MRT2 _DBUFFER_MRT3
            #pragma multi_compile _ DEBUG_DISPLAY
            #pragma multi_compile _ LOD_FADE_CROSSFADE
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/RenderingLayers.hlsl"
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Fog.hlsl"

            #pragma multi_compile_instancing
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DOTS.hlsl"

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 worldXZ     : TEXCOORD0;
            };

            CBUFFER_START(UnityPerMaterial)
                float4 _StarColor;
                float4 _NebulaColor;
                float  _CellSize;
                float  _StarSize;
                float  _StarDensity;
                float  _Brightness;
                float  _NebulaCell;
                float  _NebulaStrength;
                float  _PixelsPerUnit;
                float  _ScreenPxPerUnit;
            CBUFFER_END

            // Cell hash in float space: the star field is cosmetic and the server
            // never renders it, so per-platform determinism is all this shader needs.
            // The integer LCG chain this replaced measured a dead zone and a skewed
            // density under Unity 6.6's compiler - the star count came out 10% of the
            // authored density, and no integer form fixed it.
            float CellHash(int2 p, uint salt)
            {
                float2 q = float2(p) + float(salt);
                return frac(sin(dot(q, float2(12.9898, 78.233))) * 43758.5453);
            }

            float ValueNoise(float2 p)
            {
                float2 i = floor(p);
                float2 f = p - i;
                f = f * f * (3.0 - 2.0 * f);
                int2 u = int2(i);
                float a = CellHash(u, 0u);
                float b = CellHash(u + int2(1, 0), 0u);
                float c = CellHash(u + int2(0, 1), 0u);
                float d = CellHash(u + int2(1, 1), 0u);
                return lerp(lerp(a, b, f.x), lerp(c, d, f.x), f.y);
            }

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                float3 world = TransformObjectToWorld(IN.positionOS.xyz);
                OUT.positionHCS = TransformWorldToHClip(world);
                OUT.worldXZ = world.xz;
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                float2 w = IN.worldXZ;

                // Nebula: smooth low-amplitude gradient in world units, authored in
                // coarse cells so it reads soft at 1:1 and keeps covering ground at
                // overview - it never needs the screen-pixel fade the stars use.
                float n = ValueNoise(w / _NebulaCell) * 0.6
                        + ValueNoise(w / (_NebulaCell * 0.25)) * 0.4;
                float3 col = _NebulaColor.rgb * (n * n) * _NebulaStrength;

                // Stars: one hashed star per world-unit cell, quantized placement,
                // feathered at one game pixel so the edge lands on the pixel grid at
                // any zoom. The screen-pixel fade dims stars the screen can no longer
                // resolve: one game-pixel star at 1:0.5 covers half a screen pixel,
                // and the eye should see a dim, half-present star - never a full
                // brightness point that shimmers as the camera pans.
                float2 cell = floor(w / _CellSize);
                int2 cu = int2(cell);
                float presence = CellHash(cu, 101u);
                float starScreenPx = _StarSize * _ScreenPxPerUnit;
                float fade = smoothstep(0.5, 1.8, starScreenPx);

                if (presence < _StarDensity)
                {
                    float2 offset = float2(CellHash(cu, 202u), CellHash(cu, 303u));
                    float2 starPos = (cell + 0.15 + offset * 0.7) * _CellSize;
                    float r = _StarSize * 0.5;
                    float px = 1.0 / _PixelsPerUnit;
                    float d = distance(w, starPos);
                    float cover = 1.0 - smoothstep(r - px, r + px, d);
                    float bright = lerp(0.45, 1.0, CellHash(cu, 404u));
                    float3 tint = lerp(_StarColor.rgb, _StarColor.rgb.gbr, CellHash(cu, 505u) * 0.35);
                    col += tint * (cover * bright * fade * _Brightness);
                }

                return half4(col, 1.0);
            }
            ENDHLSL
        }

        // DepthNormals prepass pass. The project renderer runs forced depth priming
        // (PC_Renderer m_DepthPrimingMode 1): the main pass draws with ZTest Equal
        // against the prepass depth, and an object whose shader has no prepass pass
        // never has that depth, so it is never drawn - silently, not pink. Every
        // shader this renderer draws (URP Lit/Unlit, PixelEngineLit) carries the
        // prepass passes; a forward-only shader is invisible to it. This pass mirrors
        // the DepthNormals pass of PixelEngineLit: billboard normal out, rendering
        // layers encoded for the D-Buffer decal feature.
        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode" = "DepthNormals" }

            HLSLPROGRAM
            #pragma vertex dnVert
            #pragma fragment dnFrag
            #pragma target 2.0

            #pragma multi_compile _ LOD_FADE_CROSSFADE
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/RenderingLayers.hlsl"

            #pragma multi_compile_instancing
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DOTS.hlsl"

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct DNAttributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
            };

            struct DNVaryings
            {
                float4 positionCS : SV_POSITION;
                float3 normalWS   : TEXCOORD0;
            };

            DNVaryings dnVert(DNAttributes IN)
            {
                DNVaryings OUT;
                OUT.positionCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.normalWS = TransformObjectToWorldNormal(IN.normalOS);
                return OUT;
            }

            void dnFrag(
                DNVaryings IN
                , out half4 outNormalWS : SV_Target0
            #ifdef _WRITE_RENDERING_LAYERS
                , out float4 outRenderingLayers : SV_Target1
            #endif
            )
            {
                outNormalWS = half4(NormalizeNormalPerPixel(IN.normalWS), 0.0);
            #ifdef _WRITE_RENDERING_LAYERS
                outRenderingLayers = float4(EncodeMeshRenderingLayer(), 0.0, 0.0, 0.0);
            #endif
            }
            ENDHLSL
        }
    }
}
