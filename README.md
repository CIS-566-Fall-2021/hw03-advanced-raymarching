# Ruth Chung

## Pennkey: 33615194

## Link to scene
[https://ruthchu.github.io/hw03-advanced-raymarching/](https://ruthchu.github.io/hw03-advanced-raymarching/)

Decided to make Kirby riding a star. Inspiration taken from a scene in the [Smash Ultimate trailer](https://youtu.be/WShCN-AYHqA)

## GIF to see the animation

![](images/kirbyfinal.gif)

## Static image

![](images/kirbyfinal.png)

Screenshot of scene (no good static images unfortunately, so have a blurry screenshot):
![](images/start_side_shot.png)

## Materials/techniques used
Kirby
- Body
  - Made of a mix of sphere's, ellipsoids, and roundcones
  - Flat color with ambient light term added
  - Soft shadows applied
  - Specular term used to make the glow where kirby sits on the star
- Eyes
  - Blinn phong specular applied to eyes
  - Eyes made by using sdf subtraction to determine the COLOR boundaries
- Mouth
  - Sdf subtraction
- Cheeks
  - Used ellipsoid sdf to determine COLOR boundary only
- Animation
  - Animated using gain and bias to approximate an elastic bounce
  - All elements on kirby are modified by the same animation term
  - The way the sdf is constructed follows a scene graph, where the body is the root and everything else is a node from it (including the star)

Star
- Subsurface scattering on the star to make it appear as if glowing
- Specular term applied where kirby sits on the star to add to the glowing effect

Background (flat)
- Fbm clouds
- Sine/cosine functions used to determine the boundary of the light beams and make the light beams travel across the back
- Cone of white speckles made using fbm noise trailing behind kirby (tried to replicate sparkles, didn't go so well)

## Lighting
- Ambient light on kirby
- Point light to represent star glow
- Point light from behind kirby to represent glowing light reflecting off back
- Light from below for subsurface scattering on star

## Useful external resources
- Referenced the heck out of this page:
[https://www.iquilezles.org/www/articles/distfunctions/distfunctions.htm](https://www.iquilezles.org/www/articles/distfunctions/distfunctions.htm)
