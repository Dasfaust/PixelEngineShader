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

// The indirect draw contract Unity's RenderMeshIndirect call requires.
//
// Unity reads the instance count and the start instance from the args buffer on the GPU, and it
// binds that buffer under the name UnityIndirect.cginc declares. A shader that never declares it
// never gets the buffer, and the submission degrades: the draw runs as one instance, every vertex
// sees SV_InstanceID 0, and the per-draw data the batch fills for a normal draw is what the vertex
// reads. Nothing logs it. A 6-block world then draws as one cube stacked on one cell, and the
// instance count the CPU wrote into the args buffer is a number no reader on the screen can see.
//
// This is the shape the A3c1 screen check recorded as "one slab": the counters said drawn=9 and the
// screen showed one cube, and the counters were the half that was true.
//
// InitIndirectDrawArgs must run at the top of the vertex stage that uses the index, so the args
// are loaded before GetIndirectInstanceID reads them.
#define UNITY_INDIRECT_DRAW_ARGS IndirectDrawIndexedArgs
#include "UnityIndirect.cginc"

#define BLOCK_INIT_INDIRECT_DRAW() InitIndirectDrawArgs(0)

StructuredBuffer<float4> _BlockInstances;

// The instance index the draw call numbers, read the way the indirect path states it.
//
// Two traps sit on this one line, and each one lands every vertex on instance 0.
//
// UNITY_INSTANCING_ENABLED is defined only for the INSTANCING_ON variant. URP compiles an
// instanced material with DOTS_INSTANCING_ON as well, and that path defines
// UNITY_DOTS_INSTANCING_ENABLED and not UNITY_INSTANCING_ENABLED. A macro that tests the one name
// takes the fallback branch on the path the pipeline draws with. UNITY_ANY_INSTANCING_ENABLED is
// the switch that declares UNITY_VERTEX_INPUT_INSTANCE_ID, so it is true exactly when the field the
// macro reads exists.
//
// SV_InstanceID is the draw's own numbering, and on Vulkan it starts at the args buffer's
// startInstance. GetIndirectInstanceID is the portable form of that subtraction, and it is the
// reason the index goes through the args and not straight through the semantic.
//
// The plain variant of multi_compile_instancing — the one a device without GPU instancing compiles
// — has neither the semantic nor the args buffer, so the fallback keeps that variant building.
// Desktop devices take an instancing variant.
#if UNITY_ANY_INSTANCING_ENABLED
    #define BLOCK_INSTANCE_ID(input) GetIndirectInstanceID((input).instanceID)
#else
    // The plain variant: the draw's own SV_InstanceID, read straight off the vertex.
    //
    // This is the branch the block draw takes, and it is the whole point of the keyword's contract.
    // Unity's GPU-instancing machinery services a draw from the per-instance property data Unity
    // itself owns. A RenderParams submission from a MonoBehaviour has exactly one renderer, so that
    // data is one instance deep: the args buffer's instance count is overridden, every vertex sees
    // index 0, and unity_ObjectToWorld carries the renderer's culling transform — the draw bounds'
    // center — so the one cube that draws lands on instance 0's cell plus the bounds center. Nothing
    // logs any of it.
    //
    // Out of the machinery, the submission is a raw indexed-indirect draw: the args buffer's count is
    // the instance count, unity_ObjectToWorld is the submission's own matrix, and the per-instance
    // data is the buffer this header declares.
    #define BLOCK_INSTANCE_ID(input) (input).blockInstanceID
#endif

// The vertex attribute carrying the draw's instance index in the plain variant. Under Unity's
// instancing macros the field already exists as `instanceID`, so the macro is empty there and the
// Attributes structs stay as they are.
#if UNITY_ANY_INSTANCING_ENABLED
    #define BLOCK_INSTANCE_ID_ATTRIBUTE()
#else
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
