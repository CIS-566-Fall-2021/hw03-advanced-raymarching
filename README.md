# Leaning Tower of Pisa - SDF Recreation

By An Duong

Pennkey: onlyname

## Overview
* **Leaning Tower of Pisa Recreation**
<img src="PisaNew.png" width="800"/>

<img src="PisaNew2.png" width="800"/>
* **Inspiration**
<img src="pisa-leaning-tower1.jpg" width="800"/>

[Live Demo](https://onlyname1.github.io/hw03-advanced-raymarching/)

## Implementation
The Tower of Pisa was recreated using a fragment shader that rendered the scene through raymarched signed distance functions. The scene also includes Blinn-Phong specular reflection, soft shadows implemented via raymarched shadow feeler rays, as well as basic materials. The scene includes a main light to cast shadows, a fill light to add color, and an ambient light to add color variation. Basic fog was added to emulate a horizon. The tower is made up of the smooth blend and union of SDF cylinders. The floors of the tower were created using the repetition of a singular floor through the SDF limited modullo function. The tower leans over time via a sine function. The crowds of people were also created by repeating an SDF cylinder over an area. The crowds jump up and down by offsetting their position with a triangle wave function dependent on time and a specific person's position.

## Citations
[SDF Functions](https://www.iquilezles.org/www/articles/distfunctions/distfunctions.htm)
