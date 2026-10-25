Shader "PixelEngine/Starfield Layer"
{
    // The dynamic star layer, BG7. A procedural star field drawn every frame on its own UI layer,
    // above the baked sky and below the world blit.
    //
    // The field samples no texture. A texture layer answers its stars from texels, so a slide lands the
    // texels at sub-pixel positions and the stars shimmer; this layer computes its stars from screen
    // position, so a slide moves the field with no resampling and no shimmer at any zoom. The layer
    // needs no texel-snap rule, and it holds the pixel grid by snapping its own sample position, under
    // the warp flow's rule: the snap sits on whole pixels of the layer and the star dot covers whole
    // pixels.
    //
    // Motion arrives as authored numbers the rig computes, and one rule per motion:
    // - Slide: yaw carries the pattern across the screen. The caller states the slide in star cells at
    //   zoom 1, so a slide equal to the pattern's cell count carries the field through one full pattern
    //   width. The lattice wraps on the pattern width, so a slide past the pattern edge reads the cells
    //   it left and the field shows no seam.
    // - Roll: at the nadir pose, yaw is a roll about the view axis. The caller states the angle, and the
    //   layer rotates its pattern about the screen center by that angle, in the direction that carries
    //   the stars with the world content.
    // - Zoom: the pattern scales about the center. The caller states the scale, so the field spreads at
    //   a rate below the baked layer's rate, and the star dot keeps its authored pixel size unless the
    //   dot zoom factor lifts it with the scale.
    //
    // The rig writes the lattice cell count and the dot radius in cells, so the cell grid and the dot's
    // size answer one computation and a test can read both. The shader reads the authored pixel size and
    // the dot zoom factor as inputs to that computation, the way the warp flow rig reads its authored
    // flow rate.
    //
    // Twinkle rides time, not space: a star's brightness oscillates on a per-star phase, and its
    // position never moves. A texture layer animates a star by changing which texel it samples, which
    // moves the dot; this layer changes only the value it writes at a fixed pixel.
    //
    // The cell hash, the [0,1) read, and the wrapping lattice come from ShaderLibrary/IntegerHash.hlsl,
    // the same helpers the starfield bake reads. The bake's lesson travels with them: a hash built on
    // float multiplication loses quality past 2^24, and a star field lands on its own lattice there.
    //
    // Properties answer a star, not a picture: the density is the share of cells that carry a star, the
    // size is the star dot's diameter in layer pixels, the spread is the largest star as a multiple of
    // that size, and the bands quantize brightness so the field carries the stepped palette the baked
    // sky carries.
    //
    // The canvas path requires a `_MainTex` property on a UI material, so the shader declares it hidden
    // and samples nothing.

    Properties
    {
        [HideInInspector] _MainTex("Canvas requirement (sampled by nothing)", 2D) = "white" {}

        [Header(Pattern)]
        _StarCellsWide("Star cells across the screen", Range(16, 512)) = 128
        _Density("Star density (share of cells)", Range(0, 1)) = 0.35
        _StarSizePx("Star dot size (layer pixels)", Range(0.5, 16)) = 2
        _StarSizeSpread("Largest star (x dot size)", Range(1, 4)) = 2.5
        _StarBands("Brightness bands", Range(1, 16)) = 5
        _Brightness("Star brightness", Range(0, 4)) = 1.2
        _DotRadiusCells("Dot radius (star cells, rig-written)", Float) = 0.1
        _PatternCells("Pattern cell count (rig-written)", Vector) = (96, 54, 0, 0)

        [Header(Motion)]
        _Slide("Slide (star cells at zoom 1)", Vector) = (0, 0, 0, 0)
        _ZoomScale("Pattern zoom scale", Float) = 1
        _DotZoomFactor("Dot size follows zoom (rig input)", Range(0, 1)) = 0.25
        _RollAngle("Roll angle (degrees)", Float) = 0
        _LayerAspect("Layer aspect (width over height, rig-written)", Float) = 1.7777
        _Grain("Grain snap (layer pixels per step)", Range(1, 8)) = 1

        [Header(Twinkle)]
        _TwinkleRate("Twinkle rate (cycles per second)", Range(0, 4)) = 0.35
        _TwinkleDepth("Twinkle depth (0 = steady)", Range(0, 1)) = 0.6

        [Header(Look)]
        _StarCool("Cool star color", Color) = (0.62, 0.86, 1, 1)
        _StarWarm("Warm star color", Color) = (1, 0.92, 0.8, 1)
        _WarmFraction("Warm share of stars", Range(0, 1)) = 0.25
        _Opacity("Layer opacity", Range(0, 1)) = 1

        [Header(Seed)]
        [IntRange] _Seed("Field seed", int) = 1

        [Header(Layer size)]
        _LayerSize("Layer size (pixels)", Vector) = (964, 544, 0, 0)

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
            Name "StarfieldLayer"

            Cull Off
            ZWrite Off
            ZTest [unity_GUIZTestMode]
            Blend SrcAlpha OneMinusSrcAlpha

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "ShaderLibrary/IntegerHash.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float4 _MainTex_TexelSize;
                float _StarCellsWide;
                float _Density;
                float _StarSizePx;
                float _StarSizeSpread;
                float _StarBands;
                float _Brightness;
                float _DotRadiusCells;
                float4 _PatternCells;
                float4 _Slide;
                float _ZoomScale;
                float _DotZoomFactor;
                float _RollAngle;
                float _LayerAspect;
                float _Grain;
                float _TwinkleRate;
                float _TwinkleDepth;
                float4 _StarCool;
                float4 _StarWarm;
                float _WarmFraction;
                float _Opacity;
                int _Seed;
                float4 _LayerSize;
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

            half4 frag(Varyings varyings) : SV_Target
            {
                float2 layer = max(_LayerSize.xy, float2(1.0, 1.0));
                float zoom = max(_ZoomScale, 0.0001);
                float aspect = max(_LayerAspect, 0.0001);

                // Screen-space sampling: the pattern is authored in layer pixels, so a window resize
                // keeps the star dot's pixel size and answers more cells. The snap holds the grid: the
                // sample position lands on whole grain steps, so a dot covers whole pixels and the
                // field reads the pixel grid the baked sky reads.
                float2 pos = varyings.uv * layer;
                float grain = max(_Grain, 1.0);
                pos = floor(pos / grain) * grain + 0.5 * grain;

                // Rotate about the layer center in pixel units, so the spin reads circular and not
                // sheared by the layer's aspect. The space is height-normalized: the layer spans
                // `aspect` units across and 1 unit tall, and its center sits at 0.
                float2 p = (pos / layer - 0.5) * float2(aspect, 1.0);
                float rad = radians(_RollAngle);
                float2 rot = float2(cos(rad), sin(rad));

                // Two authored numbers set the whole geometry, and the rig writes both: the pattern's cell
                // count and the zoom. The pattern's count never moves with zoom. The screen shows
                // count ÷ zoom of those cells, and that division is the magnification: the same cells
                // spread over fewer screen pixels.
                //
                // One scalar carries the cell basis for both axes. A unit of this rotated space is one
                // layer height, and a cell is layerWidth × zoom ÷ pattern.x pixels on screen, so the
                // pattern's down count divided by the zoom answers the cells per unit across and down
                // alike. One number is why the cell stays square at every zoom, where two counts that
                // round on their own boundaries would answer a stretched cell.
                //
                // The center offset and the wrap both read the pattern's count. The offset puts the layer
                // center on the pattern center, so a zoom magnifies about the center and not about a
                // corner, and the center cell holds its answer at every zoom. The wrap repeats the
                // pattern at its own width, so a slide past the pattern edge reads the cells it left;
                // wrapping at the on-screen count would repeat the pattern inside one screen.
                float2 pattern = max(_PatternCells.xy, float2(1.0, 1.0));
                float cellsPerUnit = pattern.y / zoom;
                float2 spun = float2(p.x * rot.x - p.y * rot.y, p.x * rot.y + p.y * rot.x);
                float2 cells = spun * cellsPerUnit + 0.5 * pattern + _Slide.xy;

                int2 wrappedCount = max(int2(round(pattern)), int2(1, 1));
                int2 base = int2(floor(cells));
                float radius = max(_DotRadiusCells, 0.0001);

                half4 color = half4(0.0, 0.0, 0.0, 0.0);

                // A star sits off its cell center by up to 0.7 of a cell, so a star in a neighbour cell
                // can reach this pixel. The 3x3 sweep reads the nine lattice cells around the pixel.
                for (int oy = -1; oy <= 1; oy++)
                {
                    for (int ox = -1; ox <= 1; ox++)
                    {
                        int2 cell = WrapLattice(base + int2(ox, oy), wrappedCount);
                        int salt = _Seed;

                        // Three reads per cell: presence, the center inside the cell, and the dot's
                        // size and brightness roll. The salt names the read, so one cell's reads are
                        // independent of each other.
                        if (Hash01(cell, salt * 7 + 1) >= _Density)
                        {
                            continue;
                        }

                        float2 center = (float2)cell + 0.15 + 0.7 * float2(
                            Hash01(cell, salt * 7 + 2),
                            Hash01(cell, salt * 7 + 3));
                        float sizeRoll = Hash01(cell, salt * 7 + 4);
                        float brightRoll = Hash01(cell, salt * 7 + 5);
                        float warmRoll = Hash01(cell, salt * 7 + 6);
                        float phase = Hash01(cell, salt * 7 + 7);

                        float d = distance(cells, center);
                        // A cell hosts one star, so a star inside its own cell is the common case; a
                        // neighbour's star reaches at most one cell of distance.
                        if (d > radius * 1.6)
                        {
                            continue;
                        }

                        float dotRadius = max(radius * (1.0 + (_StarSizeSpread - 1.0) * sizeRoll), 0.0001);
                        float edge = max(fwidth(d), 0.0001);
                        float disc = saturate((dotRadius - d) / max(edge + dotRadius * 0.25, edge));

                        // Brightness quantizes to bands, so the field carries the stepped palette the
                        // baked sky carries. The twinkle rides time on the star's own phase.
                        float bands = max(_StarBands, 1.0);
                        float level = floor(brightRoll * bands) / bands;
                        float wave = sin(6.28318530718 * (_Time.y * _TwinkleRate + phase));
                        float twinkle = 1.0 - 0.5 * _TwinkleDepth * (1.0 - wave);
                        float amount = saturate(disc) * level * twinkle * _Brightness;

                        float3 tint = lerp(_StarCool.rgb, _StarWarm.rgb, step(_WarmFraction, warmRoll));
                        color.rgb += tint * amount;
                        color.a += amount;
                    }
                }

                color.rgb = saturate(color.rgb);
                color.a = saturate(color.a) * _Opacity;
                color *= varyings.color;

                // Canvas RectMask2D clip, the UI/Default shape: the mask is the distance to the clip
                // rect edges, floored by the softness inset, saturate-masked, and scaled by the mask
                // mode in ClipRectMin.w. An unmasked RawImage gets a rect so wide the mask is 1.
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
    CustomEditor "PixelEngineShaderInspector"
}
