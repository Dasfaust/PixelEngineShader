#ifndef PIXELENGINE_BLOCK_INSTANCING_INCLUDED
#define PIXELENGINE_BLOCK_INSTANCING_INCLUDED

// Per-instance block data for drawing the block arrays with DrawMeshInstancedIndirect.
//
// The buffer is two float4 elements per instance: element 2i is the cell center (xyz, w unused),
// element 2i + 1 is the instance color (rgba). The C# side writes the pairs and binds the buffer
// globally; the draw call's instance index selects the pair.
//
// The keyword is a shader_feature_local, so only the material that requests it compiles the
// instanced variants. No other material using this shader pays for the path.

#if defined(_BLOCK_INSTANCED)

StructuredBuffer<float4> _BlockInstances;

float4 GetBlockInstancePosition(uint instanceID)
{
    return _BlockInstances[instanceID * 2];
}

float4 GetBlockInstanceColor(uint instanceID)
{
    return _BlockInstances[instanceID * 2 + 1];
}

// The block mesh is a unit cube centered at the origin, and the drawing material's transform is
// the identity at the world origin. Adding the cell center in object space lands the cube on the
// cell, and every pass that calls this gets the same placement.
float3 ApplyBlockInstance(float3 positionOS, uint instanceID)
{
    return positionOS + GetBlockInstancePosition(instanceID).xyz;
}

#endif
#endif
