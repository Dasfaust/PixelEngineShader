Shader "PixelEngine/Starfield Bake"
{
    // One GPU bake of the star field the panorama atlas stores.
    //
    // The pass writes one bake target: the yaw strip (every yaw cell inside one wide image) or the
    // nadir cell. A pass declares its target size in _FieldDims, and every lattice in the field
    // wraps at that size. The strip pass therefore repeats at exactly the strip width, so the
    // strip's right edge sits beside its left edge, the ring seam stays continuous, and each yaw
    // cell is a slice of one continuous picture. A feature that crosses a cell boundary needs no
    // extra rule, because the bake carries no cell grid inside the strip.
    //
    // The pass carries no time term. A bake of one seed writes the same pixels on every run, so a
    // same-seed re-bake reads the same look, and a cache file holds the picture the bake produced.
    // Moving stars and twinkles live on the real-time star layer and never inside a baked picture.
    //
    // _StarStrength answers 0.0 for the nadir cell. Crisp star dots live only on the layer that
    // rolls with a nadir yaw press, so a baked nadir picture is soft haze.
    //
    // Output is opaque, alpha 1.0. The canvas composites the atlas with source-alpha blending, so a
    // baked alpha below 1.0 lets the layers behind the background show through the background.
    //
    // Band quantization is the PixelEngineLit step, floor(value * steps) / steps, applied to scalar
    // tones. Nebula colors and star brightness land on authored steps and never on a ramp.

    Properties
    {
        [Header(Bake target)]
        _FieldDims("Bake target size (texels)", vector) = (964, 544, 0, 0)

        [Header(Seed)]
        _Seed("Field seed", int) = 1

        [Header(Deep space)]
        _DeepTop("Deep color (view top)", Color) = (0.043, 0.016, 0.078, 1)
        _DeepBottom("Deep color (view bottom)", Color) = (0.137, 0.031, 0.165, 1)
        _GradientBands("Gradient bands", Range(2, 32)) = 14

        [Header(Nebula band)]
        _NebulaAngle("Band angle (degrees)", Range(0, 180)) = 100
        _NebulaOffset("Band offset (field pixels)", float) = 0
        _NebulaWidth("Band width (field pixels)", float) = 40
        _NebulaScale("Detail scale (per field pixel)", float) = 0.075
        _NebulaWarp("Domain warp (field pixels)", float) = 8
        _NebulaFloor("Detail floor", Range(0, 0.9)) = 0.28
        _NebulaContrast("Detail contrast", Range(0.5, 6)) = 2.6
        _NebulaBands("Density bands", Range(2, 32)) = 6
        _NebulaCover("Coverage", Range(0, 1)) = 0.85
        _GlowWidth("Wash width (band widths)", float) = 3.0
        _GlowCover("Wash coverage", Range(0, 1)) = 0.42
        _NebulaEdge("Edge color", Color) = (0.200, 0.060, 0.250, 1)
        _NebulaMid("Mid color", Color) = (0.300, 0.140, 0.350, 1)
        _NebulaCore("Core color", Color) = (0.440, 0.270, 0.470, 1)
        _LaneScale("Dust lane scale (per field pixel)", float) = 0.055
        _LaneDepth("Dust lane depth", Range(0, 1)) = 0.6

        [Header(Stars)]
        _StarStrength("Star strength", Range(0, 1)) = 1
        _StarDensity("Star density", Range(0, 1)) = 0.8
        _StarSize("Star size (field pixels)", Range(0.1, 3)) = 0.65
        _StarSizeSpread("Largest star (x size)", Range(1, 4)) = 2.4
        _StarBands("Brightness bands", Range(2, 16)) = 5
        _StarCool("Cool star color", Color) = (0.62, 0.86, 1, 1)
        _StarWarm("Warm star color", Color) = (1, 0.92, 0.8, 1)

        [Header(Output)]
        _Exposure("Exposure", Range(0, 4)) = 1
        _PaletteBands("Posterize output (0 = off)", Range(0, 64)) = 0
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "Queue" = "Geometry"
            "IgnoreProjection" = "True"
        }

        Pass
        {
            Name "StarfieldBake"

            ZTest Always
            ZWrite Off
            Cull Off
            Blend Off

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "ShaderLibrary/IntegerHash.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _FieldDims;
                int _Seed;
                float4 _DeepTop;
                float4 _DeepBottom;
                float _GradientBands;
                float _NebulaAngle;
                float _NebulaOffset;
                float _NebulaWidth;
                float _NebulaScale;
                float _NebulaWarp;
                float _NebulaFloor;
                float _NebulaContrast;
                float _NebulaBands;
                float _NebulaCover;
                float _GlowWidth;
                float _GlowCover;
                float4 _NebulaEdge;
                float4 _NebulaMid;
                float4 _NebulaCore;
                float _LaneScale;
                float _LaneDepth;
                float _StarStrength;
                float _StarDensity;
                float _StarSize;
                float _StarSizeSpread;
                float _StarBands;
                float4 _StarCool;
                float4 _StarWarm;
                float _Exposure;
                float _PaletteBands;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float4 screenPos : TEXCOORD0;
            };

            // The band step PixelEngineLit applies to a light value.
            float Bands(float value, float steps)
            {
                return floor(value * steps) / steps;
            }

            float3 Bands(float3 value, float steps)
            {
                return floor(value * steps) / steps;
            }

            // UintHash, Hash01, and WrapLattice come from ShaderLibrary/IntegerHash.hlsl, the same
            // helpers the star layer reads. One hash means a field built at one seed reads the same
            // stars from the bake and from the layer.

            // Value noise on a wrapping integer lattice, in [0, 1]. The octave index is the hash salt,
            // so the four octaves never read the same hash cell.
            float ValueNoise(float2 p, float2 countF, int octave)
            {
                int2 count = (int2)countF;
                int2 lattice = (int2)floor(p);
                float2 f = frac(p);
                f = f * f * (3.0 - 2.0 * f);
                int salt = octave * 7919;
                float a = Hash01(WrapLattice(lattice, count), salt);
                float b = Hash01(WrapLattice(lattice + int2(1, 0), count), salt);
                float c = Hash01(WrapLattice(lattice + int2(0, 1), count), salt);
                float d = Hash01(WrapLattice(lattice + int2(1, 1), count), salt);
                return lerp(lerp(a, b, f.x), lerp(c, d, f.x), f.y);
            }

            // Lattice count for a requested scale: the count is a whole number of cells across the
            // bake target, so the scale a call asks for and the period it wraps at cannot drift.
            float2 CountFor(float scale)
            {
                return max(round(_FieldDims.xy * scale), float2(2.0, 2.0));
            }

            // Four octaves on integer cell counts that double each octave. Each octave reads its own
            // lattice origin, so the octaves never share a cell.
            float NebulaDetail(float2 coord)
            {
                float2 origin0 = float2(0.37, 0.71);
                float2 origin1 = float2(1.13, 0.29);
                float2 origin2 = float2(2.41, 0.83);
                float2 origin3 = float2(4.19, 1.37);

                float2 count = CountFor(_NebulaScale);
                float sum = 0.5334 * ValueNoise(coord * (count / _FieldDims.xy) + origin0, count, 0);
                count = CountFor(_NebulaScale * 2.0);
                sum += 0.2667 * ValueNoise(coord * (count / _FieldDims.xy) + origin1, count, 1);
                count = CountFor(_NebulaScale * 4.0);
                sum += 0.1333 * ValueNoise(coord * (count / _FieldDims.xy) + origin2, count, 2);
                count = CountFor(_NebulaScale * 8.0);
                sum += 0.0667 * ValueNoise(coord * (count / _FieldDims.xy) + origin3, count, 3);
                return sum;
            }

            // Stars for one layer, on a lattice that wraps at one bake target. Each cell holds at
            // most one dot, placed inside the cell by a hash, lit through the band step. Size and
            // light rise together in the same quantized steps, so the few large dots are the bright
            // ones and the mass of small dots stays dim.
            float3 StarLayer(float2 field, float cell, float densityFactor, float brightness, int layer)
            {
                float2 countF = max(round(_FieldDims.xy / cell), float2(2.0, 2.0));
                int2 count = (int2)countF;
                float2 cellSize = _FieldDims.xy / countF;
                float2 p = field / cellSize;
                int2 insideLattice = (int2)floor(p);
                float2 inside = frac(p);

                // The seed shifts every layer's lattice by whole cells, and the shift wraps inside
                // WrapLattice. Whole-number arithmetic keeps the shift exact at the top of the seed
                // range, where the old float shift lost its fine bits and the layer fell onto its grid.
                int2 lattice = WrapLattice(insideLattice + _Seed * (layer + 1), count);
                int salt = _Seed * 31 + layer * 1013904223;

                // Size, warmth, and the dot's center all read the same roll, the way the layer is
                // authored: the few large dots are the bright ones, and their color and size move
                // together. The roll now comes from the integer hash, so the steps it carries stay
                // real steps at every seed.
                float roll = Hash01(lattice, salt);
                float present = step(1.0 - _StarDensity * densityFactor, roll);

                float sizeRoll = saturate(frac(roll * 13.7) * 1.6 - 0.6);
                float sizeFactor = 1.0 + (_StarSizeSpread - 1.0) * Bands(sizeRoll, 3.0);
                float size = _StarSize * sizeFactor;

                float2 center = float2(Hash01(lattice, salt + 7), Hash01(lattice, salt + 13));
                float distance = length((inside - center) * cellSize);
                // The falloff spans one field pixel, so a lit dot carries a core value and at most
                // one dim neighbour: a dot never grows a soft halo around itself.
                float light = saturate((size + 0.5 - distance) * 2.0);
                light = Bands(light, _StarBands);

                float warmth = step(0.55, frac(roll * 13.0));
                float3 tint = lerp(_StarCool.rgb, _StarWarm.rgb, warmth);
                return tint * (light * present * brightness * sizeFactor);
            }

            Varyings vert(Attributes attributes)
            {
                Varyings varyings;
                varyings.positionCS = TransformObjectToHClip(attributes.positionOS.xyz);
                varyings.screenPos = ComputeScreenPos(varyings.positionCS);
                return varyings;
            }

            float4 frag(Varyings varyings) : SV_Target
            {
                float2 bakeUv = varyings.screenPos.xy / varyings.screenPos.w;

                // One texel is one field pixel, so the texel index is the field position. The lattice
                // wrap keeps the seam invisible at the target's edges.
                float2 fieldDims = max(_FieldDims.xy, float2(1.0, 1.0));
                float2 field = floor(bakeUv * fieldDims) + 0.5;
                float2 centered = field - fieldDims * 0.5;

                const float degreesToRadians = 0.017453292519949215;

                // Deep space: a gradient in field space that brightens toward the target's bottom,
                // the cast the background art carries.
                float gradientTone = Bands(saturate(0.5 - centered.y / fieldDims.y), _GradientBands);
                float3 color = lerp(_DeepTop.rgb, _DeepBottom.rgb, gradientTone);

                // Nebula band: one axis runs along the band, the other across it.
                float bandSine, bandCosine;
                sincos(_NebulaAngle * degreesToRadians, bandSine, bandCosine);
                float2 bandAxis = float2(bandCosine, bandSine);
                float2 bandNormal = float2(-bandSine, bandCosine);
                float across = dot(centered, bandNormal) - _NebulaOffset;
                float along = dot(centered, bandAxis);

                float2 warpSource = (centered + 17.3) * (CountFor(_NebulaScale * 0.35) / fieldDims);
                float2 warp = (float2(ValueNoise(warpSource, CountFor(_NebulaScale * 0.35), 4),
                                      ValueNoise(warpSource + 11.7, CountFor(_NebulaScale * 0.35), 5)) - 0.5)
                    * _NebulaWarp;

                float2 bandCount = CountFor(_NebulaScale * 0.2);
                float bandWidth = _NebulaWidth * (1.0 + _NebulaWarp * 0.02 *
                    (ValueNoise(centered * (bandCount / fieldDims) - 5.1, bandCount, 6) - 0.5));
                float bandMask = saturate(1.0 - abs(across) / max(bandWidth, 1.0));
                bandMask = bandMask * bandMask * (3.0 - 2.0 * bandMask);

                // A wide, low-frequency version of the same mask: the wash the band sits in.
                float glowMask = saturate(1.0 - abs(across) / max(bandWidth * _GlowWidth, 1.0));
                glowMask = glowMask * glowMask * (3.0 - 2.0 * glowMask);
                color = lerp(color, _NebulaEdge.rgb, saturate(glowMask * _GlowCover));

                float detail = NebulaDetail(centered + warp);
                detail = saturate((detail - _NebulaFloor) * _NebulaContrast);

                // The lane is a ridge in a noise field stretched along the band, carved out of the
                // density where the ridge stands. Its lattice wraps on the band axes at the target's
                // extent along each axis.
                float2 laneExtent = float2(abs(fieldDims.x * bandAxis.x) + abs(fieldDims.y * bandAxis.y),
                                           abs(fieldDims.x * bandNormal.x) + abs(fieldDims.y * bandNormal.y));
                float2 laneCount = max(round(laneExtent * _LaneScale * float2(0.5, 1.0)), float2(2.0, 2.0));
                float laneNoise = ValueNoise(float2(along, across) * (laneCount / laneExtent), laneCount, 7);
                float lane = saturate((1.0 - abs(laneNoise * 2.0 - 1.0)) * 2.0 - 1.0) * bandMask;

                float density = saturate(detail * bandMask - lane * _LaneDepth);

                // The density drives both the color mix and the coverage through the same quantized
                // tone, so the band shows authored colors at authored coverage steps.
                float tone = Bands(density, _NebulaBands);
                float3 nebula = lerp(_NebulaEdge.rgb, _NebulaMid.rgb, saturate(tone * 2.0));
                nebula = lerp(nebula, _NebulaCore.rgb, saturate(tone * 2.0 - 1.0));
                color = lerp(color, nebula, saturate(tone * _NebulaCover * 1.4));

                // Three star layers, slow and dense far away, fast and sparse near the camera.
                float3 stars = StarLayer(field, 22.0, 1.0, 0.40, 0);
                stars += StarLayer(field, 18.0, 0.8, 0.65, 1);
                stars += StarLayer(field, 15.0, 0.55, 1.0, 2);

                color += stars * _StarStrength;

                color = saturate(color) * _Exposure;

                // Off by default: a final posterize snaps the summed result onto a coarse palette.
                if (_PaletteBands > 0.5)
                {
                    color = Bands(color, _PaletteBands);
                }

                return float4(color, 1.0);
            }
            ENDHLSL
        }
    }
}
