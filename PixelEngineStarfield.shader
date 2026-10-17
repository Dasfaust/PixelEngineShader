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

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" "Queue" = "Background" }

        Pass
        {
            Name "Starfield"
            Tags { "LightMode" = "UniversalForward" }

            Cull Off
            ZWrite On
            ZTest LEqual
            Blend One Zero

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.5

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
    }
}
