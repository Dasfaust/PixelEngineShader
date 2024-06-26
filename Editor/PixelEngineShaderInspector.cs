using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;

namespace PixelEngine
{
    public class PixelEngineShaderInspector : ShaderGUI
    {
        public enum SurfaceType
        {
            Opaque = 0, AlphaClip = 1, Transparent = 2
        }

        public enum HeightMode
        {
            Parallax = 0, Tessellation = 1
        }

        public override void OnGUI(MaterialEditor materialEditor, MaterialProperty[] properties)
        {
            base.OnGUI(materialEditor, properties);

            Material material = materialEditor.target as Material;

            var surfaceProp = BaseShaderGUI.FindProperty("_SurfaceType", properties, true);
            EditorGUI.BeginChangeCheck();
            surfaceProp.intValue = (int)(SurfaceType)EditorGUILayout.EnumPopup("Surface Type", (SurfaceType)surfaceProp.intValue);
            if (EditorGUI.EndChangeCheck())
            {
                UpdateSurfaceType(material);
            }

            var heightProp = BaseShaderGUI.FindProperty("_HeightMode", properties, true);
            EditorGUI.BeginChangeCheck();
            heightProp.intValue = (int)(HeightMode)EditorGUILayout.EnumPopup("Height Mode", (HeightMode)heightProp.intValue);
            if (EditorGUI.EndChangeCheck())
            {
                UpdateHeightMode(material);
            }
        }

        public override void AssignNewShaderToMaterial(Material material, Shader oldShader, Shader newShader)
        {
            base.AssignNewShaderToMaterial(material, oldShader, newShader);

            if (newShader.name == "PixelEngineLit")
            {
                UpdateSurfaceType(material);
                UpdateHeightMode(material);
            }
        }

        private void UpdateSurfaceType(Material material)
        {
            SurfaceType surface = (SurfaceType)material.GetInteger("_SurfaceType");
            switch (surface)
            {
                case SurfaceType.Opaque:
                    material.renderQueue = (int)RenderQueue.Geometry;
                    material.SetOverrideTag("RenderType", "Opaque");
                    material.SetFloat("_SourceBlend", (int)BlendMode.One);
                    material.SetFloat("_DestBlend", (int)BlendMode.Zero);
                    material.SetFloat("_ZWrite", 1);
                    material.SetFloat("_Cull", (int)CullMode.Back);
                    material.DisableKeyword("_DOUBLE_SIDED_NORMALS");
                    material.DisableKeyword("_ALPHA_CUTOUT");
                    material.SetShaderPassEnabled("ShadowCaster", true);
                    break;
                case SurfaceType.AlphaClip:
                    material.renderQueue = (int)RenderQueue.AlphaTest;
                    material.SetOverrideTag("RenderType", "TransparentCutout");
                    material.SetFloat("_SourceBlend", (int)BlendMode.One);
                    material.SetFloat("_DestBlend", (int)BlendMode.Zero);
                    material.SetFloat("_ZWrite", 1);
                    material.SetFloat("_Cull", (int)CullMode.Off);
                    material.EnableKeyword("_DOUBLE_SIDED_NORMALS");
                    material.EnableKeyword("_ALPHA_CUTOUT");
                    material.SetShaderPassEnabled("ShadowCaster", true);
                    break;
                case SurfaceType.Transparent:
                    material.renderQueue = (int)RenderQueue.Transparent;
                    material.SetOverrideTag("RenderType", "Transparent");
                    material.SetFloat("_SourceBlend", (int)BlendMode.SrcAlpha);
                    material.SetFloat("_DestBlend", (int)BlendMode.OneMinusSrcAlpha);
                    material.SetFloat("_ZWrite", 0);
                    material.SetFloat("_Cull", (int)CullMode.Back);
                    material.DisableKeyword("_DOUBLE_SIDED_NORMALS");
                    material.DisableKeyword("_ALPHA_CUTOUT");
                    material.SetShaderPassEnabled("ShadowCaster", false);
                    break;
            }
        }

        private void UpdateHeightMode(Material material)
        {
            HeightMode heightMode = (HeightMode)material.GetInteger("_HeightMode");
            switch (heightMode)
            {
                case HeightMode.Parallax:
                    material.EnableKeyword("_HEIGHT_MODE_PARALLAX");
                    material.DisableKeyword("_HEIGHT_MODE_TESSELLATION");
                    break;
                case HeightMode.Tessellation:
                    material.DisableKeyword("_HEIGHT_MODE_PARALLAX");
                    material.EnableKeyword("_HEIGHT_MODE_TESSELLATION");
                    break;
            }
        }
    }
}
