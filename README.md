# RayMarching SDFs

## Nathan Devlin - @ndevlin - ndevlin@seas.upenn.edu - www.ndevlin.com

Result:

![](Results.png)

Reference Image:

![](Reference.jpeg)

## Live Demo
View a live WebGL Demo here!:
https://ndevlin.github.io/RayMarching-SDFs-wMaterials/

## Project Description

This project uses Signed Distance Functions (as opposed to explicit geometry) to define a scene. Ray marching is used to determine pixel colors. The project uses WebGL and was coded with TypeScript and GLSL in Visual Studio Code.

## Implementation Details

This scene is created entirely in the fragment shader. Rays are shot from the camera through the pixels of the screen to test against the sdfs that comprise the scene to determine distance of the nearest object to the camera. The scene is composed of primitives that have been combined together in various ways; for example a smooth blend operation is used to nicely blend together the toruses that compose the robot's feet/wheels with the capsule primitives that compose his lower legs. 

The primitives are described by SDF functions at the top of the shader. To improve efficiency, bounding spheres a limiting of the cast rays is utilized. Normals are calculated by sampling the scene in the same way, using small epsilon differences from the sampled fragment to determine the normal. These normals are then used to achieve lambertian shading by comparing the normal to the light position. 

There is also some simple animation added to the scene. The face of the robot, which looks sort of like an old-school scuba mask is created with a boolean subtraction operation between one rounded cylinder and a smaller one. This is added to the sphere that composes the head with a Union operation to meld them together. This face is animated using rotation operations and a quadratic Impulse function combined with a sin function to create the effect that the robot abruptly looks at the camera, then slowly looks away again. Additionally, the antenna ball on his head is animated using cosin functions to give the feeling that it is bouncing around playfully. 

Materials are added along with the SDFs in the sceneSDF function by pairing a material ID with each object, stored in a vec2. Then later in the rendering function (getSceneColor()), the shading of that material is calculated. There are currently 3 materials in the scene: two different lambert materials of different colors for the floor and for the rubber connectors at the robot's joints, and one blinn-phong metallic material for the robot's body.

There additionally is a carefully crafted lighting set up using a 3-point lighting scheme. Directional lights with unique colors and intensities color the scene and cast shadows through the use of raymarched shadow light-feeling rays sent from the camera ray's intersection point towards the light source to determine if there is an occlusion. The hardness of the lights is created through an optical estimation that uses a penumbra shadow algorithm to determine how sharp or soft the shadows cast should be. 


IQ's article on SDF shapes was very useful:
https://www.iquilezles.org/www/articles/distfunctions/distfunctions.htm