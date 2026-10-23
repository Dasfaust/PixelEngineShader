// The bow plume: the plasma sheath carried in front of a platform moving through the warp.
//
// One plate per platform, built by WarpBowPlume. The plate is camera-facing: the vertex builds it around
// the object's own centre in view space, so it reads the same in the ortho pixel camera and in
// perspective mode, and the object's transform carries the authored width, tail length, and placement.
//
// The plate draws additive with ZTest Always. The plate sits on the far side of the platform while the
// platform travels away from the camera, so a depth test the platform can win would hide the sheath
// behind the hull it is burning. Additive over the hull is what a re-entry looks like from this side.
Shader "PixelEngine/Warp Plume"
{
    Properties
    {
        [Header(Plume Look)]
        [HDR] _PlumeColor("Plume Colour", color) = (1, 0.4, 0.1, 1)
        [HDR] _PlumeHotColor("Nose Hot Colour", color) = (1, 0.92, 0.75, 1)
        _PlumeIntensity("Plume Intensity", Range(0, 8)) = 1
        _PlumePower("Nose Falloff Power", Range(0.01, 8)) = 2
        _PlumeFilaments("Filament Count", Range(1, 64)) = 12
        _PlumeTurbulence("Filament Length Scale", Range(0.05, 8)) = 1.5
        _PlumeSpeed("Scroll Speed", Range(0, 8)) = 1
        _PlumeCells("Grain Cells", Range(1, 128)) = 24
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Transparent"
            "Queue" = "Transparent"
            "RenderPipeline" = "UniversalPipeline"
        }

        Pass
        {
            Name "WarpPlume"
            Tags { "LightMode" = "UniversalForward" }

            Blend SrcAlpha One
            ZWrite Off
            ZTest Always
            Cull Off

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            #pragma multi_compile _ DOTS_INSTANCING_ON

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            CBUFFER_START(UnityPerMaterial)
                float4 _PlumeColor;
                float4 _PlumeHotColor;
                float _PlumeIntensity;
                float _PlumePower;
                float _PlumeFilaments;
                float _PlumeTurbulence;
                float _PlumeSpeed;
                float _PlumeCells;
            CBUFFER_END

            // The warp rig writes these three: the same intensity the streak layer runs on, the same clock
            // the streaks scroll on, and the direction of travel. The plate reads the intensity linearly,
            // so the sheath grows with the warp and nothing else. The travel direction is read by the game
            // side that places the plate; it is declared here so the shared block reads complete.
            float4 _WarpTravelWS;
            float _WarpIntensity;
            float _WarpFlowPhase;

            float PlumeHash(float2 seed)
            {
                float2 p = frac(seed * 0.1031);
                p += dot(p, p.yx + 33.33);
                return frac((p.x + p.y) * p.y);
            }


            Varyings vert(Attributes input)
            {
                Varyings output = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);

                // A camera-facing plate: the authored offsets run along the camera's own right and up axes
                // in world space, anchored at the object centre, so the plate turns with the camera and the
                // object's scale is the plate's size. A mesh built in world axes would tilt off the view as
                // the camera pitches.
                float3 centreWS = TransformObjectToWorld(float3(0.0f, 0.0f, 0.0f));
                float scaleX = length(float3(UNITY_MATRIX_M[0][0], UNITY_MATRIX_M[1][0], UNITY_MATRIX_M[2][0]));
                float scaleY = length(float3(UNITY_MATRIX_M[0][1], UNITY_MATRIX_M[1][1], UNITY_MATRIX_M[2][1]));
                float3 rightWS = normalize(UNITY_MATRIX_V[0].xyz);
                float3 upWS = normalize(UNITY_MATRIX_V[1].xyz);
                float3 worldPos = centreWS
                    + rightWS * (input.positionOS.x * scaleX)
                    + upWS * (input.positionOS.y * scaleY);
                output.positionCS = TransformWorldToHClip(worldPos);
                output.uv = input.uv;
                return output;
            }

            float4 frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);

                float intensity = saturate(_WarpIntensity);
                if (intensity <= 0.0f)
                {
                    return float4(0.0f, 0.0f, 0.0f, 0.0f);
                }

                float2 uv = saturate(input.uv);
                float along = uv.y;
                float across = uv.x * 2.0f - 1.0f;

                // Bright at the nose, spent at the tail. The nose is the surface facing the travel, so the
                // nose is where the sheath lights hottest.
                float nose = pow(saturate(1.0f - along), max(_PlumePower, 0.01f));
                float side = pow(saturate(1.0f - abs(across)), 2.0f);

                // Filaments: one hash cell across the width, scrolled along the length on the warp clock,
                // so the sheath flows at the streak speed.
                float filamentCell = floor(uv.x * max(_PlumeFilaments, 1.0f));
                float scroll = frac(along * max(_PlumeTurbulence, 0.01f)
                    + _WarpFlowPhase * max(_PlumeSpeed, 0.0f)
                    + PlumeHash(float2(filamentCell, 3.71f)) * 7.13f);
                float pulse = pow(saturate(sin(scroll * 6.2831853f) * 0.5f + 0.5f), 3.0f);
                float filaments = 0.35f + 0.65f * pulse;

                // Grain on the plate's own grid, so the sheath breaks into cells at the pixel scale.
                float2 grainCell = floor(float2(uv.x, uv.y) * max(_PlumeCells, 1.0f));
                float grain = 0.7f + 0.3f * PlumeHash(grainCell + floor(_WarpFlowPhase * 2.0f));

                float alpha = saturate(intensity * _PlumeIntensity * nose * side * filaments * grain);
                float3 colour = lerp(_PlumeColor.rgb, _PlumeHotColor.rgb, pow(saturate(1.0f - along), 3.0f));
                return float4(colour, alpha);
            }
            ENDHLSL
        }
    }
}
