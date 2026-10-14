#ifndef PIXELENGINE_BLOCK_INSTANCING_INCLUDED
#define PIXELENGINE_BLOCK_INSTANCING_INCLUDED

// Per-instance block data for the indirect block draw.
//
// The buffer is two float4 elements per instance: element 2i is the cell center (xyz, w unused),
// element 2i + 1 is the instance color (rgba). The C# side writes the pairs and binds the buffer
// globally; the draw call's instance index selects the pair.
//
// The keyword is a shader_feature_local, so only the material that requests it compiles the
// instanced variants. No other material using this shader pays for the path.

#if defined(_BLOCK_INSTANCED)

// The args buffer is read by the GPU and never by the shader.
//
// The instance count lives in the args buffer the submission carries, and the draw runs that count.
// The shader's only job is to index the instance pairs with the draw's own SV_InstanceID.
//
// UnityIndirect.cginc is not part of that contract on this pipeline. That file sits in
// Editor/Data/Resources/CGIncludes, beside UnityInstancing.cginc, which is the built-in pipeline's CG
// include set. No file in com.unity.render-pipelines.core or
// com.unity.render-pipelines.universal names it, its InitIndirectDrawArgs helper, or its
// GetIndirectInstanceID helper, and URP never binds the unity_IndirectDrawArgs buffer those helpers
// read. An unbound buffer read returns zeros, so the helper returns the index unchanged and the shader
// is correct by accident and not by contract. The built-in pipeline is obsolete from Unity 7.0, so a
// dependency on that file is a dependency that ends.
//
// This is the shape the A3c1 screen check recorded as "one slab": the counters said drawn=9 and the
// screen showed one cube. The counters were the half that was true, and the cause was Unity's
// instancing machinery, recorded below and in Docs/phase3-block-rendering.md.

StructuredBuffer<float4> _BlockInstances;

// The instance index the draw call numbers, and the attribute that carries it.
//
// The block draw takes the plain variant, and that is a rule and not a preference. Unity services an
// instanced draw from the per-instance property data Unity owns. A RenderParams submission from a
// MonoBehaviour has exactly one renderer, so that data is one instance deep: the args buffer's instance
// count is ignored, every vertex reads index 0, and unity_ObjectToWorld carries the renderer's culling
// transform, which is the draw bounds' center. The one cube that draws lands on instance 0's cell plus
// that center, and the machinery logs nothing. BlockRenderer logs a material that carries the flag on,
// and clears it.
//
// UNITY_INSTANCING_ENABLED is defined only for the INSTANCING_ON variant. URP compiles an SRP-batched
// material with DOTS_INSTANCING_ON as well, and that path defines UNITY_DOTS_INSTANCING_ENABLED and not
// UNITY_INSTANCING_ENABLED. UNITY_ANY_INSTANCING_ENABLED is the switch that declares
// UNITY_VERTEX_INPUT_INSTANCE_ID, so it names both paths.
//
// The instancing branch pins the index to 0 and declares no attribute, so the variant still builds. A
// material that asks for instancing and this keyword together draws one cube, which is exactly what the
// machinery does, and the renderer's log names that material.
#if UNITY_ANY_INSTANCING_ENABLED
    #define BLOCK_INSTANCE_ID(input) 0u
    #define BLOCK_INSTANCE_ID_ATTRIBUTE()
#else
    #define BLOCK_INSTANCE_ID(input) (input).blockInstanceID
    #define BLOCK_INSTANCE_ID_ATTRIBUTE() uint blockInstanceID : SV_InstanceID;
#endif

float4 GetBlockInstancePosition(uint instanceID)
{
    return _BlockInstances[instanceID * 2];
}

float4 GetBlockInstanceColor(uint instanceID)
{
    return _BlockInstances[instanceID * 2 + 1];
}

// The block's world position.
//
// The RenderMesh* submission family carries no object transform — `RenderParams` has no matrix field
// on Unity 6.6 — so unity_ObjectToWorld on this draw is Unity's own value for the submission, and the
// play-mode screen check measured it as the draw bounds' center. Every block the draw placed landed
// on its own cell plus that center, in x and in z, and nothing logged it.
//
// So the placement never touches the object-to-world matrices. The instance pair IS the world cell
// center, the mesh is a unit cube centered at the origin, and the view matrices do the rest.
float3 GetBlockPositionWS(float3 positionOS, uint instanceID)
{
    return positionOS + GetBlockInstancePosition(instanceID).xyz;
}

#endif

// The keyword is off: the attribute the pass structs declare is empty, and no instance index exists.
#ifndef BLOCK_INSTANCE_ID_ATTRIBUTE
    #define BLOCK_INSTANCE_ID_ATTRIBUTE()
#endif
#endif
