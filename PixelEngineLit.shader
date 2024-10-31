Shader "PixelEngineLit"
{
    Properties
    {
        [Header(Surface Options)]
        [KeywordEnum(Upscaled, None)] _Texture_Sampling_Type("Texture Sampling Type", float) = 0
        [MainTexture][NoScaleOffset] _DiffuseMap("Diffuse Map", 2D) = "white" { }
        [MainColor] _DiffuseColor("Diffuse Base Color", color) = (1, 1, 1, 1)
        [Normal][NoScaleOffset] _NormalMap("Normal Map", 2D) = "bump" { }
        _NormalStrength("Normal Strength", Range(0, 1)) = 1
        [NoScaleOffset] _MaskMap("Mask Map", 2D) = "white" { }
        [Enum(R,0,G,1,B,2,A,3)] _SmoothnessMaskChannel("Smoothness Mask Channel", Integer) = 0
        _SmoothnessStrength("Smoothness Strength", Range(0, 1)) = 0
        [Toggle(_INVERT_SMOOTHNESS)] _InvertSmoothness("Smoothness is Roughness", float) = 0
        [Enum(R,0,G,1,B,2,A,3)] _MetallicMaskChannel("Metallic Mask Channel", Integer) = 1
        _MetallicStrength("Metallic Strength", Range(0, 1)) = 0
        [Enum(R,0,G,1,B,2,A,3)] _AOMaskChannel("AO Mask Channel", Integer) = 2
        _AOStrength("AO Strength", Range(0, 1)) = 1
        [Enum(R,0,G,1,B,2,A,3)] _HeightMaskChannel("Height Mask Channel", Integer) = 3
        _HeightStrength("Height Strength", Range(0, 1)) = 0
        [Toggle(_HEIGHT_TO_NORMALS)] _HeightToNormals("Convert Height to Normals", float) = 0
        [NoScaleOffset] _EmissionMap("Emission Map", 2D) = "white" { }
        [HDR] _EmissionColor("Emission Base Color", color) = (1, 1, 1, 1)
        _EmissionStrength("Emission Strength", Range(0, 1)) = 0

        [Header(Atlas Options)]
        _SizeRange("Size and Index Range", vector) = (1, 1, 0, 0)
        _TilingOffset("Tiling and Offset", vector) = (1, 1, 0, 0)
        _FPS("Flipbook FPS", float) = 0

        [Header(Lighting Options)]
        [KeywordEnum(BRDF, BlinnPhong)] _Lighting_Model("Lighting Model", float) = 0
        [Toggle(_ADDITIONAL_LIGHTS_MODEL_NONE)] _AdditionalLightsModelNone("Additional Lights Additive Only", float) = 0
        [Toggle(_ENABLE_QUANTIZATION)] _EnableQuantization("Enable Quantization", float) = 1
        [Toggle(_ENABLE_GI_QUANTIZATION)] _EnableGIQuantization("Enable GI Quantization", float) = 0
        [KeywordEnum(Linear, Ramp)] _Quantization_Type("Quantization Type", float) = 0
        [NoScaleOffset] _RampMap("Ramp Map", 2D) = "white" { }
        _MinLinearBrightness("Minimum Linear Brightness", Range(0, 1)) = 0
        _DiffuseQuantization("Diffuse Quantization", float) = 4
        _SpecularQuantization("Specular Quantization", float) = 4
        _PointQuantization("Point Light Quantization", float) = 6
        _SpotQuantization("Spot Light Quantization", float) = 6

        [Header(Outline Options)]
        [Toggle(_OUTLINES_ENABLED)] _EnableOutlines("Enable Outlines", float) = 0
        [KeywordEnum(Orthographic, Perspective)] _Outlines("Outline Mode", float) = 0
        _PerspectiveOutlineMaxDistance("Perspective Outline Max Distance", float) = 50
        [KeywordEnum(SoftLight, Overlay, Overwrite)] _Outlines_Blending("Outlines Blending Mode", float) = 0
        [KeywordEnum(Lit, Unlit, Emissive)] _Outlines_Lighting("Outlines Lighting Type", float) = 0
        _OutlineEmissionStrength("Emission Strength", Range(0, 1)) = 1
        _OutlineSize("Outline Scale", float) = 1
        [HDR] _OuterOutlineColor("Outer Outline Color", color) = (1, 0.945098, 0.9098039, 1)
        _OuterOutlineThreshold("Outer Outline Threshold", float) = 0.1
        [HDR] _InnerOutlineColor("Inner Outline Color", color) = (0.4705882, 0.454902, 0.454902, 1)
        _InnerOutlineThreshold("Inner Outline Threshold", float) = 0.15
        _InnerOutlineBias("Inner Outline Bias", vector) = (1, 1, 1, 0)

        [Header(Rendering Options)]
        _Cutoff("Alpha Clip Threshold", Range(0, 1)) = 0.5
        [HideInInspector] _SurfaceType("Surface Type", Integer) = 0
        [HideInInspector] _HeightMode("Height Mode", Integer) = 0
        [KeywordEnum(None, Cylindrical)] _Billboarding("Billboarding Type", float) = 0
        [HideInInspector] _Cull("Cull Mode", float) = 2
        [HideInInspector] _SrcBlend("Source Blend", float) = 1
        [HideInInspector] _DstBlend("Destination Blend", float) = 0
        [HideInInspector] _ZWrite("ZWrite ", float) = 1

        [Header(Debug Options)]
        [KeywordEnum(None, Depth, Normals, Outlines)] _Debug("Debug Type", float) = 0
    }

    SubShader
    {
        Tags
        { 
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
        }

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            Cull [_Cull]
            ZWrite [_ZWrite]
            Blend [_SrcBlend] [_DstBlend]

            HLSLPROGRAM
                #pragma vertex Vertex
                #pragma fragment Fragment

                // com.unity.render-pipelines.universal/ShaderLibrary/DOTS.hlsl
                #pragma target 5.0
                #pragma multi_compile_instancing
                #pragma instancing_options renderinglayer
                #pragma multi_compile _ DOTS_INSTANCING_ON

                #pragma shader_feature_local_vertex _ _BILLBOARDING_CYLINDRICAL
                #pragma shader_feature_local_fragment _ _ALPHA_CUTOUT
                #pragma shader_feature_local_fragment _ _DOUBLE_SIDED_NORMALS
                #pragma shader_feature_local_fragment _HEIGHT_MODE_PARALLAX _HEIGHT_MODE_TESSELLATION
                #pragma shader_feature_local_fragment _ _INVERT_SMOOTHNESS
                #pragma shader_feature_local_fragment _ _HEIGHT_TO_NORMALS
                #pragma shader_feature_local_fragment _ _LIGHTING_MODEL_BLINNPHONG
                #pragma shader_feature_local_fragment _ _ADDITIONAL_LIGHTS_MODEL_NONE
                #pragma shader_feature_local_fragment _ _ENABLE_QUANTIZATION
                #pragma shader_feature_local_fragment _ _ENABLE_GI_QUANTIZATION
                #pragma shader_feature_local_fragment _ _QUANTIZATION_TYPE_RAMP
                #pragma shader_feature_local_fragment _ _OUTLINES_ENABLED
                #pragma shader_feature_local_fragment _ _OUTLINES_PERSPECTIVE
                #pragma shader_feature_local_fragment _OUTLINES_BLENDING_OVERLAY _OUTLINES_BLENDING_OVERWRITE
                #pragma shader_feature_local_fragment _ _OUTLINES_LIGHTING_UNLIT _OUTLINES_LIGHTING_EMISSIVE
                #pragma shader_feature_local_fragment _ _DEBUG_DEPTH _DEBUG_NORMALS _DEBUG_OUTLINES
                #pragma shader_feature_local_fragment _ _TEXTURE_SAMPLING_TYPE_UPSCALED

                // com.unity.render-pipelines.universal/Shaders/Lit.shader#L136
                #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
                #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
                #pragma multi_compile _ EVALUATE_SH_MIXED EVALUATE_SH_VERTEX
                #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
                #pragma multi_compile_fragment _ _REFLECTION_PROBE_BLENDING
                #pragma multi_compile_fragment _ _REFLECTION_PROBE_BOX_PROJECTION
                #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
                #pragma multi_compile_fragment _ _SCREEN_SPACE_OCCLUSION
                #pragma multi_compile_fragment _ _LIGHT_COOKIES
                #pragma multi_compile_fragment _ _LIGHT_LAYERS
                #pragma multi_compile _ _FORWARD_PLUS
                #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/RenderingLayers.hlsl"

                // com.unity.render-pipelines.universal/Shaders/Lit.shader#L153
                #pragma multi_compile _ LIGHTMAP_SHADOW_MIXING
                #pragma multi_compile _ SHADOWS_SHADOWMASK
                #pragma multi_compile _ DIRLIGHTMAP_COMBINED
                #pragma multi_compile _ LIGHTMAP_ON
                #pragma multi_compile _ DYNAMICLIGHTMAP_ON
                #pragma multi_compile_fragment _ LOD_FADE_CROSSFADE
                #pragma multi_compile_fog

                #include "ShaderLibrary/PassLit.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }

            Cull [_Cull]
            ZWrite [_ZWrite]
            ColorMask 0

            HLSLPROGRAM
                #pragma vertex Vertex
                #pragma fragment Fragment

                // com.unity.render-pipelines.universal/ShaderLibrary/DOTS.hlsl
                #pragma target 5.0
                #pragma multi_compile_instancing
                #pragma instancing_options renderinglayer
                #pragma multi_compile _ DOTS_INSTANCING_ON

                #pragma shader_feature_local_vertex _BILLBOARDING_CYLINDRICAL
                #pragma shader_feature_local_fragment _ALPHA_CUTOUT
                #pragma shader_feature_local_fragment _DOUBLE_SIDED_NORMALS
                #pragma shader_feature_local_fragment _HEIGHT_MODE_PARALLAX
                #pragma shader_feature_local_fragment _HEIGHT_MODE_TESSELLATION

                #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

                #include "ShaderLibrary/PassShadowCaster.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode" = "DepthNormals" }

            Cull [_Cull]
            ZWrite [_ZWrite]
            Blend [_SrcBlend] [_DstBlend]

            HLSLPROGRAM
                #pragma vertex Vertex
                #pragma fragment Fragment

                // com.unity.render-pipelines.universal/ShaderLibrary/DOTS.hlsl
                #pragma target 5.0
                #pragma multi_compile_instancing
                #pragma instancing_options renderinglayer
                #pragma multi_compile _ DOTS_INSTANCING_ON

                #pragma shader_feature_local_vertex _BILLBOARDING_CYLINDRICAL
                #pragma shader_feature_local_fragment _ALPHA_CUTOUT
                #pragma shader_feature_local_fragment _DOUBLE_SIDED_NORMALS
                #pragma shader_feature_local_fragment _HEIGHT_MODE_PARALLAX
                #pragma shader_feature_local_fragment _HEIGHT_MODE_TESSELLATION
                #pragma shader_feature_local_fragment _HEIGHT_TO_NORMALS

                // com.unity.render-pipelines.universal/Shaders/Lit.shader#L382
                #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/RenderingLayers.hlsl"

                #include "ShaderLibrary/PassDepthNormals.hlsl"
            ENDHLSL
        }
    }

    CustomEditor "PixelEngine.PixelEngineShaderInspector"
}