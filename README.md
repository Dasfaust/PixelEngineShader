# Pixel Engine Shader
A URP Forward+/SRP Batcher/DOTS instancing compatible PBR-esque toon shader made for use with [PixelEngine](https://github.com/Dasfaust/PixelEngine), but it can be used in any project!

## Preview
![preview](https://github.com/Dasfaust/UniversalToonPBR/blob/main/Docs/hazmat.gif?raw=true)

## Main Features
* Texture atlasing and flipbook support
* Flexible diffuse, specular, and additional light attenuation quantization
* Parallax mapping support
* Emission support
* Robust per-object outlines; edge and inner colors, lighting support, multiple blending modes, and emission support
* Transparency, billboarding, and foliage support

## Starfield

`PixelEngineStarfield.shader` draws a procedural sky in one unlit pass: hashed
stars on a world-unit cell grid, each star feathered at one game pixel, and a
smooth value-noise nebula in coarse world cells. Placement is integer grid math,
so every device sees the same stars in the same cells. The look is authored in
world units - `Cell Size`, `Star Size`, density, brightness, nebula cell and
strength - and two runtime uniforms keep the scale discipline:
`Pixels Per Unit` (game pixels per world unit) and `Screen Pixels Per World
Unit` (`pixelsPerUnit x zoom / renderScale`, pushed by the game each camera
snap). The second uniform drives the screen-pixel fade: a star the screen can
no longer resolve dims toward zero across the fade band instead of shimmering,
which is what keeps the sky readable at 1:0.5 overview. No keywords, so the
material needs no variant work.
