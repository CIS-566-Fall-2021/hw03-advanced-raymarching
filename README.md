# CIS 566 Homework 3: Advanced Raymarched Scenes

Eddie Huang (huanged)

Live Demo: 

Screenshots:

![](Picture1.png)

![](Picture2.png)

Reference:

![](Reference.png)

Description:

I added in some more geometry to the sword to make it look a bit better, using the SDFs for a box, capsule, and triangular prism. To color in the material for the podium/stairs, I fed FBM into a cosine color palette and used lambertian shading. To color in the floor of the scene, I fed Perlin Noise into a different cosine color palette. To color in the blade and yellow gem of the sword, I added in some Blinn-Phong shading and for the rest of the elements in the scene I used basic lambert shading. I once again fed Perlin Noise into a cosine color palette to color in the background, except this time I multiplied in the cosine of u_Time to add some animation.

For lighting I have a main key light that is used to create the soft shadows of the scene, and then I also used a fill light with a blueish green color to help illuminate the shadows a bit. I also added in a conditional to make this fill light more apparent on the blade of the sword so that it pops out more. I also used a global illumination light that contributes some yellow lighting to all elements in the scene, and added another conditional to increase the effect of this light on the yellow gem of the sword to make it more vibrant.

To help optimize the performance of my scene, I added in a max ray length to terminate the ray marching process early if needed and I also added in a bounding sphere check to help reduce computations when checking the SDFs of the scene. The overall FPS of my scene is still pretty bad though.


External Sources:

https://www.shadertoy.com/view/ssdSR2

https://www.shadertoy.com/view/7stSW7

https://www.iquilezles.org/www/articles/distfunctions/distfunctions.htm


## Objective
- Gain experience with signed distance functions
- Experiment with animation curves
- Create a presentable portfolio piece

## Base Code

You will copy your implementation of hw02 into your hw03 repository.

## Assignment Requirements
- __(35 points) Artwork Replication__ Your raymarched scene should attempt to replicate the appearance of your inspiration (include picture) with clear effort put into the replication.
- __(25 points) Materials__ Your scene should be composed of at least three different materials. We define a material to be a surface reflection model combined with some base surface color; texturing is optional.
- __(10 points) Lighting and Shadows__ Light your scene with at least three light sources. At least one of your light sources must cast shadows, and they should be soft shadows using the penumbra shadows algorithm we discussed in class. Consider following the "Key Light, Fill Light, GI Light" formulation from the in-class example.
- __(20 points) Performance__ The frame rate of your scene must be at least 10FPS.
- __(10 points)__ Following the specifications listed
[here](https://github.com/pjcozzi/Articles/blob/master/CIS565/GitHubRepo/README.md),
create your own README.md, renaming this file to INSTRUCTIONS.md. Don't worry
about discussing runtime optimization for this project. Make sure your
README contains the following information:
  - Your name and PennKey
  - Citation of any external resources you found helpful when implementing this
  assignment.
  - A link to your live github.io demo
  - An explanation of the techniques you used to model and animate your scene.

## Useful Links
- [IQ's Article on SDFs](http://www.iquilezles.org/www/articles/distfunctions/distfunctions.htm)
- [IQ's Article on Smooth Blending](http://www.iquilezles.org/www/articles/smin/smin.htm)
- [IQ's Article on Useful Functions](http://www.iquilezles.org/www/articles/functions/functions.htm)
- [Breakdown of Rendering an SDF Scene](http://www.iquilezles.org/www/material/nvscene2008/rwwtt.pdf)


## Submission
Commit and push to Github, then make a pull request on the hw03 repository with a title containing your name, and a comment containing a link to your live demo.

## Inspiration
- [Alien Corridor](https://www.shadertoy.com/view/4slyRs)
- [The Evolution of Motion](https://www.shadertoy.com/view/XlfGzH)
- [Fractal Land](https://www.shadertoy.com/view/XsBXWt)
- [Voxel Edges](https://www.shadertoy.com/view/4dfGzs)
- [Snail](https://www.shadertoy.com/view/ld3Gz2)
- [Cubescape](https://www.shadertoy.com/view/Msl3Rr)
- [Journey Tribute](https://www.shadertoy.com/view/ldlcRf)
- [Stormy Landscape](https://www.shadertoy.com/view/4ts3z2)
- [Generators](https://www.shadertoy.com/view/Xtf3Rn)
