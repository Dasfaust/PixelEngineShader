#ifndef PLUME_MASK_INCLUDED
#define PLUME_MASK_INCLUDED

// The warp bow plume's brightness mask, in one place for both passes of PixelEngineWarpPlume.
//
// The forward pass multiplies this mask by the authored strength to get its alpha. The DepthNormals
// pass clips the same mask at an authored floor, and that is the pass's job here: the pass writes
// depth, this project's renderer runs the prepass, and the depth the pass writes decides what the
// primed main pass draws behind the plume. A mask term is an area that answers no light, so a
// prepass without the clip writes depth for pixels that draw nothing, and the primed frame resolves
// what sits behind them against depth that names nothing. The clip keeps the prepass depth and the
// drawn pixels one set.
//
// The mask takes every number as an argument and reads no material constant itself. Each pass hands
// in its own UnityPerMaterial values, so the two constant blocks stay identical, which is what a
// material needs to stay SRP-batcher compatible.

float PlumeMaskHash(float2 seed)
{
    float2 p = frac(seed * 0.1031);
    p += dot(p, p.yx + 33.33);
    return frac((p.x + p.y) * p.y);
}

// The mask runs 0..1. Facing dims the wraps, downstream spends the sheath along the tail, the end
// taper closes a sweep wider than a half circle, the filaments flow downstream on the warp clock,
// and the grain breaks the surface into cells at the pixel scale.
// The mask answers its facing term as an out parameter: the forward pass blends the core colour
// toward the hot colour by that number, and the prepass ignores it. One function, one signature, so
// both passes read one rule.
float PlumeMask(float2 uv, float3 normalWS, float intensity, float facingPower, float downstreamPower,
    float edgeTaper, float filamentCount, float filamentScale, float scrollSpeed, float grainCells,
    float flowPhase, float3 travelWS, out float facingOut)
{
    // The front of the cap faces the travel, so the front is where the sheath lights. A surface at a
    // right angle to the travel answers zero, which is what dims the wraps.
    float facing = pow(saturate(dot(normalize(normalWS), normalize(travelWS))), max(facingPower, 0.01f));
    facingOut = facing;

    // The sheath spends itself along the tail.
    float downstream = pow(saturate(1.0f - uv.y), max(downstreamPower, 0.01f));

    // The ends of a sweep wider than a half circle reach behind the sides. The taper takes their
    // brightness down to zero, so the wrap does not end on a cut edge.
    float ends = pow(saturate(min(uv.x, 1.0f - uv.x) * 2.0f), max(edgeTaper, 0.01f));

    // Filaments flow downstream on the warp clock, one hash cell per band across the wrap.
    float cell = floor(uv.x * max(filamentCount, 1.0f));
    float scroll = frac(uv.y * max(filamentScale, 0.01f)
        + flowPhase * max(scrollSpeed, 0.0f)
        + PlumeMaskHash(float2(cell, 3.71f)) * 7.13f);
    float pulse = pow(saturate(sin(scroll * 6.2831853f) * 0.5f + 0.5f), 3.0f);
    float filaments = 0.35f + 0.65f * pulse;

    // Grain on the cap's own grid, so the sheath breaks into cells at the pixel scale.
    float2 grainCell = floor(uv * max(grainCells, 1.0f));
    float grain = 0.7f + 0.3f * PlumeMaskHash(grainCell + floor(flowPhase * 2.0f));

    return saturate(intensity * facing * downstream * ends * filaments * grain);
}


// The travel direction the facing term reads. The warp rig publishes the travel as a global, and a
// surface at the start of a pass has no travel number yet, so the fallback states the game's travel
// axis, which is world +Z. Both passes read travel through this rule, so a forward pass and a prepass
// cannot disagree about which side of the cap is the front.
float3 PlumeTravelWS(float4 travelWS)
{
    return length(travelWS.xyz) > 0.0001f ? normalize(travelWS.xyz) : float3(0.0f, 0.0f, 1.0f);
}

// The intensity the plume reads. The seam global is the number the warp pass runs on, and that is the
// shipped answer. The authored override exists for a measurement that must pin the intensity without a
// commented-out line: above zero it replaces the seam, and it stands at zero in the shipped material.
//
// Both passes read intensity through this helper. The prepass writes depth, and its clip uses the
// intensity, so a prepass that reads a different number from the forward pass writes depth for pixels
// the forward pass does not light.
float PlumeIntensityNow(float debugIntensityOverride)
{
    float overrideValue = saturate(debugIntensityOverride);
    return overrideValue > 0.0f ? overrideValue : saturate(_WarpIntensity);
}

#endif
