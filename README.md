# CIS 566 Homework 3: Advanced Raymarched Scenes

## Info
- Lanqing Bao (lanqing)
- Link:  https://seiseiko.github.io/hw03-advanced-raymarching/

## Screenshots
![](res1.gif)
![](res2.gif)

## Implementation Details


### Truchet Tiling generated scene:
![Insipiration](gears.jpg)
I was thinking about generating the scene procedurally instead of manually put them together. I found [Truchet tiles](https://en.wikipedia.org/wiki/Truchet_tiles) interesting and implement a cubic pattern consisting of two kinds of tile as below.(Geometry outside the wireframe is not in the tile. Half gears enables the connectivity since teeth could overlap same area at boundary.)
![two_cubic_gear_tiles](showtile.gif)
- The gears are not symmetric along all axes so I have to manually calculate how to flip them. Thus I divide the world into 1x1x1 grids and use two checkerboard-like parameter:
1) Checker along all axes:
```
vec3 id = floor(mod(p,2.))*2.-1.;
float checker = id.x*id.y*id.z;
```
2) Checker along x axes: ```float second_checker = id.x;```
Then SDF is calculated by checker*second_checker* modular result of p.

### Lighting: 
- 1)Ambient occulusion for GI(see ```ambientOcclusion()```)
- 2)Directional Light 1 at ```(-4.*sin(0.01*u_Time),2.+sin(0.008*u_Time),3.*sin(0.01*u_Time) ```
- 3)Directional Light 2 at ```-3.*sin(0.01*u_Time), 4.+cos(0.01*u_Time), -2.*cos(0.009*u_Time)``` *** Softshadow is casted under this light.
![](softshdow.gif)

### Material: 
```struct Material {
    vec3 ambient;//ambient color
    vec3 diffuse;//diffuse color
    vec3 specular;//specular color
    float shininess;//shininess value
}; 
```
The material of teeth and axes of gear are defined differently and their surfaces are
calculated based on Lambert & Phong while the floor is only based on Lambert.
```
const Material mat_teeth = Material(vec3(0.4667, 0.8118, 0.3059),
            vec3(1.0, 0.6902, 0.9843),
            vec3(1.0, 1.0, 1.0),
            15.0);
const Material mat_axis = Material(vec3(0.9725, 0.2863, 0.2863),
            vec3(0.4863, 0.4941, 0.8941),
            vec3(1.0, 1.0, 1.0),
            10.0);         
const Material mat_floor = Material(vec3(1.0, 0.6431, 0.6431),
            vec3(0.4863, 0.4941, 0.8941),
            vec3(1.0, 1.0, 1.0),
            2.0);         
```
- Local framerate around 60 fps(Nvidia GeForce RTX 3080Ti). Sphere bounding is used for optimization.
## Citation and resources

- [IQ's Article on SDFs](http://www.iquilezles.org/www/articles/distfunctions/distfunctions.htm)
- [IQ's Article on Smooth Blending](http://www.iquilezles.org/www/articles/smin/smin.htm)
- [Breakdown of Rendering an SDF Scene](http://www.iquilezles.org/www/material/nvscene2008/rwwtt.pdf)

