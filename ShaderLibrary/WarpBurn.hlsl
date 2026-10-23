// The warp burn term: the surface that faces the direction of travel heats.
//
// The three uniforms here are globals. The warp rig writes them every frame, so a surface shader and a
// plume shader read the same intensity and the same clock the streak layer runs on. The per-material
// tuning — colour, strength, falloff, flicker — is authored on the material and rides the
// UnityPerMaterial block in Common.hlsl.
#ifndef PIXELENGINE_WARP_BURN_INCLUDED
#define PIXELENGINE_WARP_BURN_INCLUDED

float4 _WarpTravelWS;
float _WarpIntensity;
float _WarpFlowPhase;

float WarpBurnHash(float2 seed)
{
    float2 p = frac(seed * 0.1031);
    p += dot(p, p.yx + 33.33);
    return frac((p.x + p.y) * p.y);
}

/// The facing cap: a surface parallel to travel reads 1, a surface at a right angle to travel reads 0.
/// Raising it to a power narrows the lit region toward the face that points into the travel.
float WarpBurnFacing(float3 normalWS)
{
    float facing = saturate(dot(normalize(normalWS), normalize(_WarpTravelWS.xyz)));
    return facing;
}

/// The burn's emitted colour. Zero intensity answers zero, so the term adds nothing to a standing look.
/// The flicker is a per-cell hash scrolled on the warp clock, so a hull shimmers at the streak speed
/// instead of at its own speed.
float3 WarpBurnTerm(float3 normalWS, float3 positionWS, float4 burnColor, float burnStrength,
    float burnPower, float flickerScale, float flickerSpeed)
{
    float intensity = saturate(_WarpIntensity);
    if (intensity <= 0.0f)
    {
        return float3(0.0f, 0.0f, 0.0f);
    }

    float cap = pow(WarpBurnFacing(normalWS), max(burnPower, 1.0f));

    // One hash cell per authored world length, scrolled on the warp clock. A cell keeps its value while
    // the clock advances inside it, so the pattern reads as grain and not as crawling noise.
    float2 cell = floor(positionWS.xy / max(flickerScale, 0.01f));
    float grain = WarpBurnHash(cell + floor(_WarpFlowPhase * max(flickerSpeed, 0.0f)));
    float shimmer = 0.75f + 0.25f * grain;

    return burnColor.rgb * (cap * burnStrength * intensity * shimmer);
}

#endif
