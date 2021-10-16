# CIS 566 Homework 2: Implicit Surfaces
Author: Nathaniel Korzekwa

PennKey: korzekwa

[Live Demo](https://ciscprocess.github.io/hw02-raymarching-sdfs/)

# Overview and Goal
I didn't get to make the piano play music. It was a nice goal but as it turns out,
I am really, _really_ bad at making SDF scenes: It takes me hours to make a relatively
simple model and I just don't have the time or bandwidth to realize this vision yet.

So currently this project really just meets the bare minimum requirements!

## Materials
The scene contains 4 basic material types: Flat, woodgrain, metal, and tile. Flat
is just a color and lambertian shading, woodgrain uses countour'ed perlin noise
along with a wood-like color palette to (not very convincingly, I'm afraid) mimic
the patterns of wood grain. Warped FBM by some other noise would likely help with this.
Metal uses a color and Blinn-Phong shading to look shiny, and tile just uses lambertian
along with L6-norm worley noise.

## Lights and Shadows
There are 3 basic light sources: a "white" or grey light (boring, I know) that casts
shadows, a reddish light and a greenish one. Note that the vase only takes in the 
"grey" light which almost gives it an aura (I think it's mildly cool). Basic,
distance-based penumbra are used in calculating shadows.


# Engine
Currently, the raymarching engine closely follows the template given in class:
rays are cast from the eye through voxels in the screen, and points are generated
based on the distance to the closest object along the ray until a collision is
found.

I did add a bounding box around the most complicated part of the scene (the keys),
to limit the amount of rays that needed to compute that part of the SDF, as well
as a somewhat trivial "max distance" ray limiter. For part 2, I ended up also using
a periodic replication function to repeat the keys rather than using a for loop.
Significantly faster!

Since I have old hardware and the piano keys add a huge drain, I actually downsampled
the resolution and may need to keep it that way (or add it as a setting perhaps),
since timing will be so critical in this project, at least someday.

# Status
<p align="center">
  <img src="https://en.wiktionary.org/wiki/piano#/media/File:Pianodroit.jpg">
</p>
<p align="center">(Rough) inspiration picture.</p>

<p align="center">
  <img src="https://www.liveabout.com/thmb/a1SocZo9FhCYtJAPaY39UWM-kOk=/768x0/filters:no_upscale():max_bytes(150000):strip_icc():format(webp)/GettyImages-88636562-59efa520845b340011857d90.jpg">
</p>
<p align="center">Foot pedal model.</p>

Currently the scene is pretty drab. It's not really my best work, but the 
basics are there to be improved upon. The 'D' keys are animated according to 
exponential impulse and cosine over time, and parts of the piano are smoothed
together. I did add basic coloring since the white was painful on my eyes.

I used some smooth union and smooth subtraction operations to make things look
a little nicer than plain min/max operations.

But there are still many details off: No bench, no music, the number
of keys is wrong, and I'm sure there are some other piano details that will
throw red flags. I hope to address these later in the project, but that has been
a broken promise already.

# References
Anything IQ for the most part:
- [Soft Shadow ShaderToy](https://www.shadertoy.com/view/lsKcDD)
- [Color Palettes](https://iquilezles.org/www/articles/palettes/palettes.htm)
- [Canonical SDF Page](https://www.iquilezles.org/www/articles/distfunctions/distfunctions.htm)
- [Copied color palette](https://www.shadertoy.com/view/3dlfW2)
