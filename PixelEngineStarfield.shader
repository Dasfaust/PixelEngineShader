Shader "Custom/PixelEngineStarfield"
{
    Properties
    {
        _StarColor("Star Color", Color) = (0.85, 0.9, 1.0, 1)
        _StarColorWarm("Star Color Warm", Color) = (1.0, 0.72, 0.45, 1)
        _StarSaturation("Star Saturation (0..1)", range(0, 1)) = 0.85
        _StarContrast("Star Brightness Contrast (1..4)", range(1, 4)) = 2.2
        _NebulaColor("Nebula Color", Color) = (0.25, 0.18, 0.42, 1)
        _CellSize("Cell Size (world units)", float) = 0.25
        _StarSize("Star Size (world units)", float) = 0.06
        _StarDensity("Star Density (0..1)", range(0, 1)) = 0.35
        _Brightness("Star Brightness", range(0, 4)) = 1.2
        _ClusterCell("Cluster Cell (world units)", float) = 8
        _ClusterWarp("Cluster Warp (world units)", float) = 2.2
        _NebulaCell("Nebula Cell (world units)", float) = 1.5
        _NebulaStrength("Nebula Strength", range(0, 1)) = 0.3
        _PixelsPerUnit("Pixels Per Unit (game pixels per world unit)", float) = 64
        _ScreenPxPerUnit("Screen Pixels Per World Unit", float) = 64
        _PlaneInvSin("Screen Y Pixels Per World Z (1 over sin of the plane pitch)", float) = 1
        _NebulaPixel("Nebula Lattice (screen pixels per noise cell)", float) = 4
        _NebulaBands("Nebula Bands (posterize levels)", range(2, 64)) = 8
        _LagOffset("Lag Offset (quad screen offset, pattern axes)", Vector) = (0, 0, 0, 0)
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
                float4 _StarColorWarm;
                float4 _NebulaColor;
                float  _StarSaturation;
                float  _StarContrast;
                float  _CellSize;
                float  _StarSize;
                float  _StarDensity;
                float  _Brightness;
                float  _ClusterCell;
                float  _ClusterWarp;
                float  _NebulaCell;
                float  _NebulaStrength;
                float  _NebulaPixel;
                float  _NebulaBands;
                float  _PixelsPerUnit;
                float  _ScreenPxPerUnit;
                float  _PlaneInvSin;
                float4 _LagOffset;
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

            // Style lineage: the cluster warp, ridged nebula, brightness contrast,
            // and hue grading terms implement ideas from the Star Nest starfield
            // design family (Shadertoy view XlfGRj and its Godot ports). The ideas
            // are the borrow; no code from those ports is copied - their license
            // claim is contested upstream, so the math here is written in this file.
            half4 frag(Varyings IN) : SV_Target
            {
                // The rig anchors the pattern here and pushes the quad's smooth
                // screen offset: shifting the sampling window by -offset shows the
                // pattern at +offset on screen, which is the layer's lag law running
                // continuously. The quad's grid snap cancels out of this sampling -
                // it moves the window's edges, not the stars.
                float2 w = IN.worldXZ - _LagOffset.xy;

                // Cluster warp: a smooth domain warp of the sampling coordinates.
                // Two value-noise fields pull the grid by up to _ClusterWarp world
                // units, so cells bunch into nests with near-empty gaps between
                // them. The warp is a function of world position, so the clusters
                // are world-anchored and the pan law is untouched. Authored density
                // stays the average: warping moves stars into nests, it adds none.
                float2 warp = float2(
                    ValueNoise(w / _ClusterCell),
                    ValueNoise(w / _ClusterCell + float2(7.31, 3.17))) - 0.5;
                float2 ws = w + warp * 2.0 * _ClusterWarp;

                // Nebula: ridged value noise on a screen-pixel lattice, posterized
                // into bands. 1 - abs(2n - 1) peaks where the noise crosses its
                // midpoint, so the field reads as filaments crossing in two octaves,
                // not as blobs. Squared, the ridge keeps the filaments and drops the
                // flat ground to near dark. The lattice is authored in screen pixels
                // (_NebulaPixel), so the field is flat inside a block and steps at
                // block edges - the same game-pixel scale the star feather lands on,
                // at any render scale and any plane pitch. The intensity then runs
                // through floor(x * steps) / steps, the same form the lit shader's
                // Posterize uses, so one banding law governs both shaders: filaments
                // read as flat bands with hard edges, and not as a smooth gradient.
                float2 pxPerWorld = float2(_PixelsPerUnit, _PixelsPerUnit * _PlaneInvSin);
                float2 wsn = floor(ws * pxPerWorld / max(_NebulaPixel, 1.0))
                           * max(_NebulaPixel, 1.0) / pxPerWorld;
                float ridge1 = 1.0 - abs(2.0 * ValueNoise(wsn / _NebulaCell) - 1.0);
                float ridge2 = 1.0 - abs(2.0 * ValueNoise(wsn / (_NebulaCell * 0.25)) - 1.0);
                float ridge = ridge1 * ridge2;
                float glow = floor(ridge * ridge * max(_NebulaBands, 2.0)) / max(_NebulaBands, 2.0);
                float3 col = _NebulaColor.rgb * glow * _NebulaStrength;

                // Stars: one hashed star per world-unit cell, quantized placement,
                // feathered at one game pixel so the edge lands on the pixel grid at
                // any zoom. The screen-pixel fade dims stars the screen can no longer
                // resolve: one game-pixel star at 1:0.5 covers half a screen pixel,
                // and the eye should see a dim, half-present star - never a full
                // brightness point that shimmers as the camera pans.
                float2 cell = floor(ws / _CellSize);
                int2 cu = int2(cell);
                float presence = CellHash(cu, 101u);
                float starScreenPx = _StarSize * _ScreenPxPerUnit;
                float fade = smoothstep(0.5, 1.8, starScreenPx);

                if (presence < _StarDensity)
                {
                    float2 offset = float2(CellHash(cu, 202u), CellHash(cu, 303u));
                    float2 starPos = (cell + 0.15 + offset * 0.7) * _CellSize;
                    // Screen-unit distance. One game pixel along X covers
                    // 1/_PixelsPerUnit world X; one game pixel of screen height covers
                    // that much world Z divided by sin of the plane pitch, and the rig
                    // pushes 1/sin as _PlaneInvSin. This metric therefore measures whole
                    // game pixels on both axes, so the disc and its one-pixel feather are
                    // circular on screen at every pitch. The world-unit metric this
                    // replaces measured a 1/sin ellipse: 3-4 px wide against 6-9 px tall
                    // at pitch 35.264, where sin is 0.5736.
                    float2 delta = (ws - starPos) * float2(_PixelsPerUnit, _PixelsPerUnit * _PlaneInvSin);
                    float d = length(delta);
                    // The authored star size is a world-unit diameter; in game pixels it
                    // is the same number the screen-pixel fade below already reads.
                    float r = _StarSize * 0.5 * _PixelsPerUnit;
                    float cover = 1.0 - smoothstep(r - 1.0, r + 1.0, d);
                    // Brightness contrast skews the authored 0.45..1 spread toward
                    // its low end, so a few stars carry the field and the rest sit
                    // under it as grain.
                    float bright = pow(lerp(0.45, 1.0, CellHash(cu, 404u)), _StarContrast);
                    // Hue grading: a cube-skewed hash sends most stars cool and a
                    // rare few warm, the way a real field grades, rather than
                    // tinting every star the same. Saturation pulls the tint
                    // toward its own luminance - at 1 fully colored, at 0 white.
                    float hue = pow(CellHash(cu, 505u), 3.0);
                    float3 tint = lerp(_StarColor.rgb, _StarColorWarm.rgb, hue);
                    float lum = dot(tint, float3(0.299, 0.587, 0.114));
                    tint = lerp(float3(lum, lum, lum), tint, _StarSaturation);
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
