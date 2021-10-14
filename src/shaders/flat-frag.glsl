#version 300 es
precision highp float;

uniform vec3 u_Eye, u_Ref, u_Up;
uniform vec2 u_Dimensions;
uniform float u_Time;

in vec2 fs_Pos;
out vec4 out_Col;

const int MAX_RAY_STEPS = 128;
const float maxRayDistance = 20.0;

const float FOV = 45.0;
const float EPSILON = 1e-4;

const float PI = 3.14159265359;

const float AMBIENT = 0.05;

const vec3 LIGHT1_DIR = vec3(-1.0, 1.0, 2.0);
float light1_OutputIntensity = 0.9;
vec3 light1_Color = vec3(1.0, 1.0, 1.0); // Full Daylight

const vec3 LIGHT2_DIR = vec3(1.0, 0.5, 0.0);
float light2_OutputIntensity = 0.3;
vec3 light2_Color = vec3(0.996, 0.879, 0.804); // 5000 Kelvin Tungsten light

const vec3 LIGHT3_DIR = vec3(-1.0, 1.0, -2.0);
float light3_OutputIntensity = 0.8;
vec3 light3_Color = vec3(0.996, 0.879, 0.804); // 5000 Kelvin Tungsten light

struct Ray 
{
    vec3 origin;
    vec3 direction;
};


struct Intersection 
{
    vec3 position;
    vec3 normal;
    float distance_t;
    int material_id;
};


// Operation functions

float smin( float a, float b, float k )
{
    float h = clamp( 0.5+0.5*(b-a)/k, 0.0, 1.0 );
    return mix( b, a, h ) - k*h*(1.0-h);
}


vec3 rotateAboutX(vec3 point, float theta)
{
    float cosTheta = cos(theta);
    float sinTheta = sin(theta);
    point.yz = mat2(cosTheta, -sinTheta, sinTheta, cosTheta) * point.yz;
    return point;
}


vec3 rotateAboutY(vec3 point, float theta)
{
    float cosTheta = cos(theta);
    float sinTheta = sin(theta);
    point.xz = mat2(cosTheta, -sinTheta, sinTheta, cosTheta) * point.xz;
    return point;
}

vec3 rotateAboutZ(vec3 point, float theta)
{
    float cosTheta = cos(theta);
    float sinTheta = sin(theta);
    point.xy = mat2(cosTheta, -sinTheta, sinTheta, cosTheta) * point.xy;
    return point;
}


vec3 rotateXYZ(vec3 point, float thetaX, float thetaY, float thetaZ)
{
    point = rotateAboutX(point, thetaX);
    point = rotateAboutY(point, thetaY);
    point = rotateAboutZ(point, thetaZ);

    return point;
}

// Each vec represents an object, e.g. sphere vs plane;
// First component is distance of that object, second is its materialID
vec2 unionSDF(vec2 object1, vec2 object2)
{
    if(object2.x < object1.x)
    {
        return vec2(object2.x, object2.y);
    }
    else
    {
        return vec2(object1.x, object1.y);
    }
}

float smoothSubtraction( float d1, float d2, float k ) 
{
    float h = clamp( 0.5 - 0.5*(d2+d1)/k, 0.0, 1.0 );
    return mix( d2, -d1, h ) + k*h*(1.0-h); 
}


float cubicPulse(float c, float w, float x)
{
    x = abs(x - c);
    if(x > w) return 0.0f;
    x /= w;
    return 1.0f - x * x * (3.0f - 2.0f * x);
}


float polyImpulse(float k, float n, float x)
{
    return (n / (n - 1.0)) * pow((n - 1.0) * k, 1.0 / n) * x / (1.0 + k * pow(x, n));
}


float quaImpulse( float k, float x )
{
    return 2.0*sqrt(k)*x/(1.0+k*x*x);
}


// SDF primitives

// Creates a box with dimensions dimensions
float sdfBox( vec3 position, vec3 dimensions )
{
    vec3 d = abs(position) - dimensions;
    return min(max(d.x,max(d.y,d.z)),0.0) + length(max(d,0.0));
}

// Creates a sphere
float sdfSphere(vec3 query_position, vec3 position, float radius)
{
    return length(query_position - position) - radius;
}


float sdfRoundedCylinder( vec3 p, float ra, float rb, float h )
{
  vec2 d = vec2( length(p.xz)-2.0*ra+rb, abs(p.y) - h );
  return min(max(d.x,d.y),0.0) + length(max(d,0.0)) - rb;
}


// Creates a plane
float heightField(vec3 queryPos, float planeHeight)
{
    return queryPos.y - planeHeight;
}

float sdfCapsule( vec3 point, vec3 pointA, vec3 pointB, float radius )
{
	vec3 pa = point - pointA;
    vec3 ba = pointB - pointA;
	float h = clamp( dot(pa, ba) / dot(ba, ba), 0.0, 1.0 );
	return length( pa - ba * h ) - radius;
}


float sdfTorus( vec3 point, float radius, float thickness)
{
    return length(vec2(length(point.xy)- radius, point.z)) - thickness;
}


// Describe the scene using sdf functions
vec2 sceneSDF(vec3 queryPos) 
{
    // First val is distance from camera, second is materialID; later will be changed to int
    float matID = 0.0;
    vec2 closestPointDistance = vec2(1e10, matID);

    // Add floor
    matID = 0.0;
    vec2 floor = vec2(heightField(queryPos, -2.1), matID);
    closestPointDistance = unionSDF(floor, closestPointDistance);

    // Bounding sphere to improve performance
    if(sdfSphere(queryPos, vec3(0.0, 0.0, 0.0), 2.0) < closestPointDistance.x)
    {
        // Add body
        vec3 bodyPos = rotateXYZ(queryPos, PI / 10.0,  PI / 4.0, 0.0);
        matID = 1.0;
        vec2 cube = vec2(sdfBox(bodyPos, vec3(0.5, 0.5, 0.5)), matID);
        closestPointDistance = unionSDF(cube, closestPointDistance);
        
        // Add head
        matID = 1.0;
        vec2 head = vec2(sdfSphere(queryPos, vec3(0.0, 1.3, 0.3), 0.6), matID);
        closestPointDistance = unionSDF(head, closestPointDistance);

        // Add neck
        matID = 1.0;
        vec2 neck = vec2(sdfCapsule(queryPos - vec3(0.0, 0.3, 0.3), 
                                                    vec3(-0.0, 0.1, -0.2), 
                                                    vec3(0.0, 0.4, -0.1), 0.1), matID);
        closestPointDistance = unionSDF(neck, closestPointDistance);



        // Add face
        matID = 1.0;
        vec3 shiftedFace = queryPos - vec3(-0.13, 1.3, 0.6);
        shiftedFace = rotateAboutX(shiftedFace, PI / 2.0);
        // Make robot abruptly turn head to look at camera
        shiftedFace = rotateAboutZ(shiftedFace, PI / 5.0 - quaImpulse(2.0, clamp(sin(u_Time * 0.05), 0.0, 1.0)) / 2.0);

        vec2 scubaMask = vec2(sdfRoundedCylinder(shiftedFace, 0.2, 0.1, 0.2), matID);
        float negMask = sdfRoundedCylinder(shiftedFace, 0.15, 0.05, 0.5);
        scubaMask = vec2(smoothSubtraction(negMask, scubaMask.x, 0.0), matID);

        closestPointDistance = unionSDF(scubaMask, closestPointDistance);

        // Add right upper arm
        matID = 1.0;
        vec2 rightUpperArm = vec2(sdfCapsule(queryPos - vec3(-0.8, -0.4, -0.4), 
                                                    vec3(-0.6, 0.3, 0.1), 
                                                    vec3(0.2, 0.8, 0.2), 0.1), matID);
        closestPointDistance = unionSDF(rightUpperArm, closestPointDistance);

        // Add right lower arm
        matID = 1.0;
        vec2 rightLowerArm = vec2(sdfCapsule(queryPos - vec3(-0.8, -0.4, -0.4), 
                                                    vec3(-0.6, 0.3, 0.1), 
                                                    vec3(-0.9, 0.3, 0.9), 0.1), matID);
        closestPointDistance = unionSDF(rightLowerArm, closestPointDistance);


        // Left Upper arm
        matID = 1.0;
        vec2 leftUpperArm = vec2(sdfCapsule(queryPos - vec3(0.8, 0.0, 0.2), 
                                                    vec3(-0.4, 0.3, 0.3), 
                                                    vec3(0.6, 0.2, -0.4), 0.1), matID);
        closestPointDistance = unionSDF(leftUpperArm, closestPointDistance);

        // Left lower arm
        matID = 1.0;
        vec2 leftLowerArm = vec2(sdfCapsule(queryPos - vec3(0.8, -0.6, 0.2), 
                                                vec3(0.4, 0.0, 0.5), 
                                                  vec3(0.6, 0.8, -0.4), 0.1), matID);
        closestPointDistance = unionSDF(leftLowerArm, closestPointDistance);


        // Add right upper leg
        matID = 1.0;
        vec2 rightUpperLeg = vec2(sdfCapsule(queryPos - vec3(-0.8, -1.4, -0.4), 
                                                    vec3(0.2, 0.4, 0.1), 
                                                    vec3(0.6, 1.0, -0.2), 0.1), matID);
        closestPointDistance = unionSDF(rightUpperLeg, closestPointDistance);

        // Add right lower leg
        matID = 1.0;
        vec2 rightLowerLeg = vec2(sdfCapsule(queryPos - vec3(-0.8, -1.4, -0.4), 
                                                    vec3(0.2, 0.4, 0.1), 
                                                    vec3(0.38, -0.2, -0.1), 0.1), matID);


        // Add left upper leg
        matID = 1.0;
        vec2 leftUpperLeg = vec2(sdfCapsule(queryPos - vec3(-0.4, -1.6, 0.1), 
                                                    vec3(0.8, 0.7, -0.4), 
                                                    vec3(0.6, 1.0, 0.0), 0.1), matID);
        closestPointDistance = unionSDF(leftUpperLeg, closestPointDistance);

        // Add left lower leg
        matID = 1.0;
        vec2 leftLowerLeg = vec2(sdfCapsule(queryPos - vec3(-0.4, -1.6, 0.1), 
                                                    vec3(0.8, 0.7, -0.4), 
                                                    vec3(1.2, 0.85, -0.9), 0.1), matID);


        // Right wheel
        vec3 rightWheelPos = rotateAboutY(queryPos - vec3(-0.4, -1.8, -0.5), -PI / 4.0);
        float rightWheel = sdfTorus(rightWheelPos, 0.18, 0.07);

        // Smooth blend the lower leg and the foot/wheel
        matID = 1.0;
        vec2 rightLegAndWheel = vec2(smin(rightLowerLeg.x, rightWheel, 0.1), matID);

        closestPointDistance = unionSDF(rightLegAndWheel, closestPointDistance);

        // Left wheel
        vec3 leftWheelPos = rotateAboutY(queryPos - vec3(0.9, -0.7, -0.9), -PI / 4.0);
        float leftWheel = sdfTorus(leftWheelPos, 0.18, 0.07);

        // Smooth blend the lower leg and the foot/wheel
        matID = 3.0;
        vec2 leftLegAndWheel = vec2(smin(leftLowerLeg.x, leftWheel, 0.1), matID);

        closestPointDistance = unionSDF(leftLegAndWheel, closestPointDistance);

        // Add antenna ball
        vec3 antennaPos = vec3(0.0, 1.0, 0.0);
        antennaPos = rotateAboutX(antennaPos, cos(u_Time * 0.4) / 10.0 + 0.1);
        antennaPos = rotateAboutZ(antennaPos, cos(u_Time * 0.4) / 10.0 + 0.1);
        antennaPos += vec3(0.0, 1.3, 0.4);

        matID = 1.0;
        vec2 antennaBall = vec2(sdfSphere(queryPos, antennaPos, 0.1), matID);
        closestPointDistance = unionSDF(antennaBall, closestPointDistance);

        // Add antenna wire
        matID = 1.0;
        vec2 antennaWire = vec2(sdfCapsule(queryPos, vec3(0.0, 1.8, 0.5), antennaPos, 0.01), matID);
        closestPointDistance = unionSDF(antennaWire, closestPointDistance);
        
        // Spheres at joints
        matID = 2.0; // Rubber
        vec2 ballJoint1 = vec2(sdfSphere(queryPos, vec3(0.4, 0.3, 0.5), 0.15), matID);
        closestPointDistance = unionSDF(ballJoint1, closestPointDistance);

        vec2 ballJoint2 = vec2(sdfSphere(queryPos, vec3(-0.6, 0.4, -0.2), 0.15), matID);
        closestPointDistance = unionSDF(ballJoint2, closestPointDistance);

        vec2 ballJoint3 = vec2(sdfSphere(queryPos, vec3(-0.6, -1.0, -0.3), 0.15), matID);
        closestPointDistance = unionSDF(ballJoint3, closestPointDistance);

        vec2 ballJoint4 = vec2(sdfSphere(queryPos, vec3(0.4, -0.9, -0.3), 0.15), matID);
        closestPointDistance = unionSDF(ballJoint4, closestPointDistance);

        vec2 ballJoint5 = vec2(sdfSphere(queryPos, vec3(1.35, 0.15, -0.05), 0.17), matID);
        closestPointDistance = unionSDF(ballJoint5, closestPointDistance);

        vec2 ballJoint6 = vec2(sdfSphere(queryPos, vec3(-1.3, -0.05, -0.3), 0.15), matID);
        closestPointDistance = unionSDF(ballJoint6, closestPointDistance);

        vec2 ballJoint7 = vec2(sdfSphere(queryPos, vec3(0.0, 0.53, 0.15), 0.15), matID);
        closestPointDistance = unionSDF(ballJoint7, closestPointDistance);
    }

    return closestPointDistance;
}

Ray getRay(vec2 uv)
{   
    Ray r;

    vec3 forward = u_Ref - u_Eye;
    float len = length(forward);
    forward = normalize(forward);
    vec3 right = normalize(cross(forward, u_Up));

    float tanAlpha = tan(FOV / 2.0);
    float aspectRatio = u_Dimensions.x / u_Dimensions.y;

    vec3 V = u_Up * len * tanAlpha;
    vec3 H = right * len * aspectRatio * tanAlpha;

    vec3 pointOnScreen = u_Ref + uv.x * H + uv.y * V;

    vec3 rayDirection = normalize(pointOnScreen - u_Eye);

    r.origin = u_Eye;
    r.direction = rayDirection;

    return r;
}

vec3 estimateNormal(vec3 p)
{
    vec3 normal = vec3(0.0, 0.0, 0.0);
    normal[0] = sceneSDF(vec3(p.x + EPSILON, p.y, p.z)).x - sceneSDF(vec3(p.x - EPSILON, p.y, p.z)).x;
    normal[1] = sceneSDF(vec3(p.x, p.y + EPSILON, p.z)).x - sceneSDF(vec3(p.x, p.y - EPSILON, p.z)).x;
    normal[2] = sceneSDF(vec3(p.x, p.y, p.z + EPSILON)).x - sceneSDF(vec3(p.x, p.y, p.z - EPSILON)).x;

    return normalize(normal);
}


float hardShadow(vec3 rayOrigin, vec3 rayDirection, float minT, float maxT)
{
    for(float t = minT; t < maxT; )
    {
        float h = sceneSDF(rayOrigin + rayDirection * t).x;
        if(h < EPSILON)
        {
            return 0.0;
        }
        t += h;
    }

    return 1.0;
}


float softShadow(vec3 rayOrigin, vec3 rayDirection, float minT, float maxT, float k)
{
    float result = 1.0;
    for(float t = minT; t < maxT; )
    {
        float h = sceneSDF(rayOrigin + rayDirection * t).x;
        if(h < EPSILON)
        {
            return 0.0;
        }
        result = min(result, k * h / t);
        t += h;
    }

    return result;
}


Intersection getRaymarchedIntersection(vec2 uv)
{
    Intersection intersection;    
    intersection.distance_t = -1.0;
    
    float distancet = 0.0f;
    
    Ray r = getRay(uv);
    for(int step; step < MAX_RAY_STEPS && distancet < maxRayDistance; ++step)
    {
        
        vec3 queryPoint = r.origin + r.direction * distancet;
        
        vec2 sceneAtPoint = sceneSDF(queryPoint);

        float currentDistance = sceneAtPoint.x;
        if(currentDistance < EPSILON)
        {
            // We hit something
            intersection.distance_t = distancet;
            
            intersection.normal = estimateNormal(queryPoint);

            intersection.position = queryPoint;

            intersection.material_id = int(sceneAtPoint.y);
            
            return intersection;
        }
        distancet += currentDistance;
        
    }
    
    return intersection;
}

vec3 getSceneColor(vec2 uv)
{
    Intersection intersection = getRaymarchedIntersection(uv);
    
    // Note that I flipped the camera to be at (0, 0, 3) instead of (0, 0, -10)
    // So that we are closer to the scene and so that positive blue normals face towards camera
    //return 0.5 * (getRay(uv).direction + vec3(1.0, 1.0, 1.0));

    if (intersection.distance_t > 0.0)
    { 
        //return intersection.normal;

        bool blinnPhong = false;

        // diffuseColor = Albedo: below is the default value;
        vec3 diffuseColor = vec3(1.0, 0.8745, 0.5333);

        if(intersection.material_id == 1)
        {
            diffuseColor = vec3(0.8, 0.8, 0.8);
            blinnPhong = true;
        }

        if(intersection.material_id == 2)
        {
            diffuseColor = vec3(0.1647, 0.1529, 0.1373);
        }

        if(intersection.material_id == 3)
        {
            diffuseColor = vec3(0.9, 0.9, 0.9);
            blinnPhong = true;
        }


        // First Light

        float diffuse1Term = dot(intersection.normal, normalize(LIGHT1_DIR));
        
        diffuse1Term = clamp(diffuse1Term, 0.0f, 1.0f);

        float light1Intensity = diffuse1Term * light1_OutputIntensity;  
        
        if(blinnPhong)
        {
            vec3 viewVec = u_Eye - intersection.position;
            vec3 posToLight = LIGHT1_DIR - intersection.position;
            vec3 H = (viewVec + posToLight) / (length(viewVec) + length(posToLight));
            float intensity = 1.0f;
            float sharpness = 5.0f;
            float specularIntensity = intensity * max(pow(dot(H, intersection.normal), sharpness), 0.0f);
            light1Intensity += specularIntensity * light1_OutputIntensity;
        }

        // Second Light

        float diffuse2Term = dot(intersection.normal, normalize(LIGHT2_DIR));
        
        diffuse2Term = clamp(diffuse2Term, 0.0f, 1.0f);

        float light2Intensity = diffuse2Term * light2_OutputIntensity;  
        
        if(blinnPhong)
        {
            vec3 viewVec = u_Eye - intersection.position;
            vec3 posToLight = LIGHT2_DIR - intersection.position;
            vec3 H = (viewVec + posToLight) / (length(viewVec) + length(posToLight));
            float intensity = 1.0f;
            float sharpness = 5.0f;
            float specularIntensity = intensity * max(pow(dot(H, intersection.normal), sharpness), 0.0f);            
            light2Intensity += specularIntensity * light2_OutputIntensity;
        }


        // Third Light

        float diffuse3Term = dot(intersection.normal, normalize(LIGHT3_DIR));
        
        diffuse3Term = clamp(diffuse3Term, 0.0f, 1.0f);

        float light3Intensity = diffuse3Term * light3_OutputIntensity;  
        
        if(blinnPhong)
        {
            vec3 viewVec = u_Eye - intersection.position;
            vec3 posToLight = LIGHT3_DIR - intersection.position;
            vec3 H = (viewVec + posToLight) / (length(viewVec) + length(posToLight));
            float intensity = 1.0f;
            float sharpness = 5.0f;
            float specularIntensity = intensity * max(pow(dot(H, intersection.normal), sharpness), 0.0f);            
            light3Intensity += specularIntensity * light3_OutputIntensity;
        }

        // Compute shadow from light1
        float shadowFactor = hardShadow(intersection.position, normalize(LIGHT1_DIR), EPSILON * 1000.0, 100.0);
        light1Intensity *= shadowFactor;


        // Compute shadow from light2
        shadowFactor = softShadow(intersection.position, normalize(LIGHT2_DIR), EPSILON * 1000.0, 100.0, 20.0);
        light2Intensity *= shadowFactor;

        // Compute shadow from light3
        shadowFactor = softShadow(intersection.position, normalize(LIGHT3_DIR), EPSILON * 1000.0, 100.0, 20.0);
        light3Intensity *= shadowFactor;


        light1_Color *= light1Intensity;

        light2_Color *= light2Intensity;

        light3_Color *= light3Intensity;

        // Combine different lights
        vec3 finalColor = diffuseColor * (light1_Color + light2_Color + light3_Color);
        finalColor = finalColor * (1.0 + AMBIENT);

        return finalColor;

    }
    return vec3(0.0);
}

void main()
{
    // Time varying pixel color
    vec3 col = getSceneColor(fs_Pos);

    // Output to screen
    out_Col = vec4(col,1.0);
}

