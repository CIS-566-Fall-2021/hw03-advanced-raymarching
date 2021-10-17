#version 300 es
precision highp float;

#define PI 3.14159265

#define MAT_JOE -3
#define MAT_PORTAL -2
#define MAT_SKY -1
#define MAT_GROUND 0
#define MAT_HILL 1

#define HARD_SHADOW 0
// High Dynamic Range
#define SUN_KEY_LIGHT rgb(255.0, 200.0, 230.0)
// #define SUN_KEY_LIGHT vec3(0.6, 0.4, 0.9) * 1.5
// Fill light is sky color, fills in shadows to not be black
#define SKY_FILL_LIGHT vec3(0.7, 0.2, 0.7) * 0.2
// Faking global illumination by having sunlight
// bounce horizontally only, at a lower intensity
#define SUN_AMBIENT_LIGHT rgb(125.0, 182.0, 240.0) * 0.15
#define GAMMA 1

uniform vec3 u_Eye, u_Ref, u_Up;
uniform vec2 u_Dimensions;
uniform float u_Time;

in vec2 fs_Pos;
out vec4 out_Col;
const int MIN_RAY_STEPS = 0;
const int MAX_RAY_STEPS = 128;
// const int MAX_RAY_STEPS = 100;
const float FOV = 45.0;
const float EPSILON = 1e-3;

// const vec3 EYE = vec3(0.0, 0.0, 10.0);
const vec3 ORIGIN = vec3(0.0, 0.0, 0.0);
const vec3 WORLD_UP = vec3(0.0, 1.0, 0.0);
const vec3 WORLD_RIGHT = vec3(-1.0, 0.0, 0.0);
const vec3 WORLD_FORWARD = vec3(0.0, 0.0, 1.0);
const vec3 LIGHT_DIR = vec3(-1.0, 1.0, -1.0);
const vec3 LIGHT_ORIGIN = vec3(-.750, 0.15, -1.0);

struct DirectionalLight
{
    vec3 dir;
    vec3 col;
};

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

struct hitObj
{
    float distance_t;
    int material_id;
};

vec4 permute(vec4 x){return mod(((x*34.0)+1.0)*x, 289.0);}

float rand3(vec3 st) {
    float p1 = fract(sin(dot(st.xy,
                        vec2(12.9898,78.233)))
                 * 43758.5453123);
    float p2 = fract(sin(dot(st.yz,
                        vec2(12.9898,78.233)))
                 * 43758.5453123);;
    return fract(sin(dot(vec2(p1, p2),
                        vec2(12.9898,78.233)))
                 * 43758.5453123);
}

//    Classic Perlin 2D Noise 
//    by Stefan Gustavson
//
vec2 fade(vec2 t) {return t*t*t*(t*(t*6.0-15.0)+10.0);}

float cnoise(vec2 P){
    vec4 Pi = floor(P.xyxy) + vec4(0.0, 0.0, 1.0, 1.0);
    vec4 Pf = fract(P.xyxy) - vec4(0.0, 0.0, 1.0, 1.0);
    Pi = mod(Pi, 289.0); // To avoid truncation effects in permutation
    vec4 ix = Pi.xzxz;
    vec4 iy = Pi.yyww;
    vec4 fx = Pf.xzxz;
    vec4 fy = Pf.yyww;
    vec4 i = permute(permute(ix) + iy);
    vec4 gx = 2.0 * fract(i * 0.0243902439) - 1.0; // 1/41 = 0.024...
    vec4 gy = abs(gx) - 0.5;
    vec4 tx = floor(gx + 0.5);
    gx = gx - tx;
    vec2 g00 = vec2(gx.x,gy.x);
    vec2 g10 = vec2(gx.y,gy.y);
    vec2 g01 = vec2(gx.z,gy.z);
    vec2 g11 = vec2(gx.w,gy.w);
    vec4 norm = 1.79284291400159 - 0.85373472095314 * 
        vec4(dot(g00, g00), dot(g01, g01), dot(g10, g10), dot(g11, g11));
    g00 *= norm.x;
    g01 *= norm.y;
    g10 *= norm.z;
    g11 *= norm.w;
    float n00 = dot(g00, vec2(fx.x, fy.x));
    float n10 = dot(g10, vec2(fx.y, fy.y));
    float n01 = dot(g01, vec2(fx.z, fy.z));
    float n11 = dot(g11, vec2(fx.w, fy.w));
    vec2 fade_xy = fade(Pf.xy);
    vec2 n_x = mix(vec2(n00, n01), vec2(n10, n11), fade_xy.x);
    float n_xy = mix(n_x.x, n_x.y, fade_xy.y);
    return 2.3 * n_xy;
}

// Self-written referencing noise 2021 slide deck. https://cis566-procedural-graphics.github.io/noise-2021.pdf
float fbm(float nOctaves, vec2 pos) {
    float total = 0.;
    float persistence = 1.f / 2.f;

    for (float i = 0.f; i < nOctaves; ++i) {
        float frequency = pow(2.f, i);
        float amplitude = pow(persistence, i);

        total += amplitude * cnoise(pos * frequency);
    }
    return total;
}

float dot2( in vec2 v ) { return dot(v,v); }
float dot2( in vec3 v ) { return dot(v,v); }
float ndot( in vec2 a, in vec2 b ) { return a.x*b.x - a.y*b.y; }
vec3 rgb(float r, float g, float b) { return vec3(r / 255.0, g / 255.0, b / 255.0); }

vec2 rotatePoint2d(vec2 uv, vec2 center, float angle)
{
    vec2 rotatedPoint = vec2(uv.x - center.x, uv.y - center.y);
    float newX = cos(angle) * rotatedPoint.x - sin(angle) * rotatedPoint.y;
    rotatedPoint.y = sin(angle) * rotatedPoint.x + cos(angle) * rotatedPoint.y;
    rotatedPoint.x = newX;
    return rotatedPoint;
}

float sdfSphere(vec3 query_position, vec3 position, float radius)
{
    return length(query_position - position) - radius;
}

float sdSphere(vec3 p, float s)
{
    return length(p) - s;
}

float planeSDF(vec3 queryPos, float height)
{
    return queryPos.y - height;
}

float sdBox(vec3 p, vec3 b)
{
    vec3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

float sdRoundBox( vec3 p, vec3 b, float r )
{
    vec3 q = abs(p) - b;
    return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0) - r;
}

float sdEllipsoid(vec3 p, vec3 r)
{
    float k0 = length(p/r);
    float k1 = length(p/(r*r));
    return k0*(k0-1.0)/k1;
}

float capsuleSDF(vec3 queryPos, vec3 a, vec3 b, float r)
{
    vec3 pa = queryPos - a, ba = b - a;
    float h = clamp( dot(pa,ba)/dot(ba,ba), 0.0, 1.0 );
    return length( pa - ba*h ) - r;
}

float sdRoundCone(vec3 p, float r1, float r2, float h)
{
    vec2 q = vec2( length(p.xz), p.y );

    float b = (r1-r2)/h;
    float a = sqrt(1.0-b*b);
    float k = dot(q,vec2(-b,a));
    
    if( k < 0.0 ) return length(q) - r1;
    if( k > a*h ) return length(q-vec2(0.0,h)) - r2;

    return dot(q, vec2(a,b) ) - r1;
}

float sdRoundCone(vec3 p, vec3 a, vec3 b, float r1, float r2)
{
    // sampling independent computations (only depend on shape)
    vec3  ba = b - a;
    float l2 = dot(ba,ba);
    float rr = r1 - r2;
    float a2 = l2 - rr*rr;
    float il2 = 1.0/l2;
    
    // sampling dependant computations
    vec3 pa = p - a;
    float y = dot(pa,ba);
    float z = y - l2;
    float x2 = dot2( pa*l2 - ba*y );
    float y2 = y*y*l2;
    float z2 = z*z*l2;

    // single square root!
    float k = sign(rr)*rr*rr*x2;
    if( sign(z)*a2*z2 > k ) return  sqrt(x2 + z2)        *il2 - r2;
    if( sign(y)*a2*y2 < k ) return  sqrt(x2 + y2)        *il2 - r1;
                            return (sqrt(x2*a2*il2)+y*rr)*il2 - r1;
}

float smoothUnion( float d1, float d2, float k ) {
    float h = clamp( 0.5 + 0.5*(d2-d1)/k, 0.0, 1.0 );
    return mix( d2, d1, h ) - k*h*(1.0-h); }


float smoothSubtraction( float d1, float d2, float k ) 
{
    float h = clamp( 0.5 - 0.5*(d2+d1)/k, 0.0, 1.0 );
    return mix( d2, -d1, h ) + k*h*(1.0-h); 
}

float smoothIntersection( float d1, float d2, float k )
{
    float h = clamp( 0.5 - 0.5*(d2-d1)/k, 0.0, 1.0 );
    return mix( d2, d1, h ) + k*h*(1.0-h);
}

float smin( float a, float b, float k )
{
    float h = clamp( 0.5+0.5*(b-a)/k, 0.0, 1.0 );
    return mix( b, a, h ) - k*h*(1.0-h);
}

vec3 bendPoint(vec3 p, float k)
{
    float c = cos(k*p.y);
    float s = sin(k*p.y);
    mat2  m = mat2(c,-s,s,c);
    vec3  q = vec3(m*p.xy,p.z);
    return q;
}

float hemisphere(vec3 p, float r)
{
    float sphere = sdSphere(p, r);
    float plane = planeSDF(p, 0.0);
    return smoothSubtraction(plane, sphere, 0.25f);
}

float hill(vec3 p, float r, float plane)
{
    float sphere = sdSphere(p, r);
    return smoothSubtraction(plane, sphere, 0.25f);
}

// range = [0, 1]
float joeFalling()
{
    // range = [0, 0.5]
    float h = -1.0 * pow((u_Time - floor(u_Time)), 2.0) + 0.5;
    // float h = pow(-(u_Time - floor(u_Time)) * (u_Time - floor(u_Time)) + 0.5, 1.0);
    h *= 2.0;
    // if (h > 0.0) {
        return h;
    // }
    // return 0.0;
}

float joe(vec3 queryPos, vec3 pos) {
    float joe;

    pos.y *= joeFalling();
    vec3 joePos = queryPos - pos;
    vec2 rot = rotatePoint2d(joePos.xy, vec2(0.0, 0.0), joeFalling() - 0.1);
    joePos.x = rot.x;
    joePos.y = rot.y;

    vec3 bodyBot = vec3(0.1, 0.175, 0.0);
    vec3 bodyTop = vec3(-0.25, 0.2, 0.0);
    float body = capsuleSDF(joePos, bodyBot, bodyTop, 0.15f);

    vec3 pa = vec3(-.65, 0.4, 0.0);
    vec3 pb = vec3(-1.05, 0.6, 0.0);
    float r1 = 0.25;
    float r2 = 0.15;
    float head = sdRoundCone(joePos, pa, pb, r1, r2);

    // joe = body;
    // joe = head;
    joe = smoothUnion(body, head, 0.25);
    return joe;
}

hitObj sceneSDF(vec3 queryPos)
{

    hitObj obj = hitObj(-1.f, MAT_SKY);

    float boundingBoxHorizontal = sdBox(queryPos - vec3(0.0, 2.0, 0.0), vec3(30.0, 20.0, 28.0));
    if (boundingBoxHorizontal > EPSILON) {
        obj.distance_t = 10000.0;
        return obj;
    }

    float groundY = -2.0;
    float ground = planeSDF(queryPos - vec3(0.0, groundY, 0.0), 0.0f);
    
    float finalDist = ground;
    int finalMat = MAT_GROUND;

    float hillCenterRad = 20.0;
    float hillCenter = hemisphere(queryPos - vec3(0.0, groundY - hillCenterRad / 2.0, hillCenterRad + 20.0), hillCenterRad);
    if (hillCenter < finalDist) {
        finalMat = MAT_HILL;
    }
    finalDist = smoothUnion(finalDist, hillCenter, 0.25f);

    float hillLeftRad1 = 15.0;
    float hillLeft1 = hemisphere(queryPos - vec3(-10.0 - 3.0, groundY - 11.0, 19.0 + 4.5), hillLeftRad1);
    if (hillLeft1 < finalDist) {
        finalMat = MAT_HILL;
    }
    // finalDist = smoothUnion(finalDist, hillLeft1, 0.25f);

    float hillLeftBudRad1 = 12.5;
    float hillLeftBud1 = hemisphere(queryPos - vec3(-10.0 - 3.0, groundY - 9.2, 13.5 + 4.), hillLeftBudRad1);
    if (hillLeftBud1 < finalDist) {
        finalMat = MAT_HILL;
    }
    finalDist = smoothUnion(finalDist, smin(hillLeft1, hillLeftBud1, 0.25), 0.25f);

    float hillLeftRad2 = 12.0;
    float hillLeft2 = hemisphere(queryPos - vec3(-11.0 - 3.0, groundY - 9.5, 8.5), hillLeftRad2);
    if (hillLeft2 < finalDist) {
        finalMat = MAT_HILL;
    }
    // finalDist = smoothUnion(finalDist, hillLeft2, 0.25f);

    float hillLeftRadBud2 = 8.0;
    float hillLeftBud2 = hemisphere(queryPos - vec3(-8.7 - 3.0, groundY - 5.61, 3.5), hillLeftRadBud2);
    if (hillLeftBud2 < finalDist) {
        finalMat = MAT_HILL;
    }
    finalDist = smoothUnion(finalDist, smin(hillLeft2, hillLeftBud2, 0.25f), 0.25f);

    float hillLeftBackRad1 = 10.0;
    float hillLeftBack1 = hemisphere(queryPos - vec3(-26.45, groundY - 5.0, 21.0), hillLeftBackRad1);
    if (hillLeftBack1 < finalDist) {
        finalMat = MAT_HILL;
    }
    finalDist = smoothUnion(finalDist, hillLeftBack1, 0.25f);

    float hillLeftBackRad2 = 15.0;
    float hillLeftBack2 = hemisphere(queryPos - vec3(-26.95, groundY - 10.0, 15.0), hillLeftBackRad2);
    if (hillLeftBack2 < finalDist) {
        finalMat = MAT_HILL;
    }
    finalDist = smoothUnion(finalDist, hillLeftBack2, 0.25f);

    float hillLeftFrontRad = 10.0;
    float hillLeftFront = hemisphere(queryPos - vec3(-5.9 - 3.0, groundY - 8.45, -5.0), hillLeftFrontRad);
    if (hillLeftFront < finalDist) {
        finalMat = MAT_HILL;
    }
    finalDist = smoothUnion(finalDist, hillLeftFront, 0.25f);

    float hillRightRad1 = 15.0;
    float hillRight1 = hemisphere(queryPos - vec3(13.0, groundY - 11.0, 19.0 + 4.5), hillRightRad1);
    if (hillRight1 < finalDist) {
        finalMat = MAT_HILL;
    }
    // finalDist = smoothUnion(finalDist, hillRight1, 0.25f);
    
    float hillRightBudRad1 = 12.5;
    float hillRightBud1 = hemisphere(queryPos - vec3(13.5, groundY - 9.2, 13.5 + 4.), hillRightBudRad1);
    if (hillRightBud1 < finalDist) {
        finalMat = MAT_HILL;
    }
    finalDist = smoothUnion(finalDist, smin(hillRight1, hillRightBud1, 0.25), 0.25f);
    
    float hillRightRad2 = 12.3;
    float hillRight2 = hemisphere(queryPos - vec3(14.0, groundY - 9.5, 8.5), hillRightRad2);
    if (hillRight2 < finalDist) {
        finalMat = MAT_HILL;
    }
    // finalDist = smoothUnion(finalDist, hillRight2, 0.25f);

    float hillRightRadBud2 = 5.0;
    float hillRightBud2 = hemisphere(queryPos - vec3(10.15, groundY - 2.41, 2.5), hillRightRadBud2);
    if (hillRightBud2 < finalDist) {
        finalMat = MAT_HILL;
    }
    finalDist = smoothUnion(finalDist, min(hillRight2, hillRightBud2), 0.25f);

    float hillRightBackRad1 = 10.0;
    float hillRightBack1 = hemisphere(queryPos - vec3(26.45, groundY - 5.0, 21.0), hillRightBackRad1);
    if (hillRightBack1 < finalDist) {
        finalMat = MAT_HILL;
    }
    finalDist = smoothUnion(finalDist, hillRightBack1, 0.25f);

    float hillRightBackRad2 = 9.0;
    float hillRightBack2 = hemisphere(queryPos - vec3(25.55, groundY - 3.25, 15.0), hillRightBackRad2);
    if (hillRightBack2 < finalDist) {
        finalMat = MAT_HILL;
    }
    finalDist = smoothUnion(finalDist, hillRightBack2, 0.25f);
    
    float hillRightFrontRad = 8.0;
    float hillRightFront = hemisphere(queryPos - vec3(7.9, groundY - 6.45, -6.0), hillRightFrontRad);
    if (hillRightFront < finalDist) {
        finalMat = MAT_HILL;
    }
    finalDist = smoothUnion(finalDist, hillRightFront, 0.25f);

    vec3 portalLoc = vec3(0.0, groundY + 10.0, 9.5);
    vec3 portalDim = vec3(1.0, 0.001, .75);
    // float portal = sdBox(queryPos - portalLoc, portalDim);
    float portal = sdRoundBox(queryPos - portalLoc, portalDim, 0.05);
    if (portal < finalDist) {
        finalMat = MAT_PORTAL;
    }
    // finalDist = smoothUnion(finalDist, portal, 0.25f);

    vec3 joeLoc = vec3(0.0, groundY + 11.0, 9.5);
    float joe = joe(queryPos, joeLoc);
    if (joe < finalDist) {
        finalMat = MAT_JOE;
    }
    // finalDist = smoothUnion(finalDist, joe, 0.25f);
    finalDist = smoothUnion(finalDist, min(portal, joe), 0.25f);

    obj.distance_t = finalDist;
    obj.material_id = finalMat;
    return obj;
}

hitObj shadowSceneSDF(vec3 queryPos)
{
    hitObj obj = hitObj(-1.f, MAT_SKY);

    float boundingBoxHorizontal = sdBox(queryPos, vec3(30.0, 30.0, 30.0));
    if (boundingBoxHorizontal > EPSILON) {
        obj.distance_t = 10000.0;
        return obj;
    }

    float groundY = -2.0;
    float ground = planeSDF(queryPos - vec3(0.0, groundY, 0.0), 0.0f);
    
    float finalDist = ground;
    int finalMat = MAT_GROUND;

    float hillCenterRad = 20.0;
    float hillCenter = hemisphere(queryPos - vec3(0.0, groundY - hillCenterRad / 2.0, hillCenterRad + 20.0), hillCenterRad);
    if (hillCenter < finalDist) {
        finalMat = MAT_HILL;
    }
    finalDist = smoothUnion(finalDist, hillCenter, 0.25f);

    float hillLeftRad1 = 15.0;
    float hillLeft1 = hemisphere(queryPos - vec3(-10.0 - 3.0, groundY - 11.0, 19.0 + 4.5), hillLeftRad1);
    if (hillLeft1 < finalDist) {
        finalMat = MAT_HILL;
    }
    // finalDist = smoothUnion(finalDist, hillLeft1, 0.25f);

    float hillLeftBudRad1 = 12.5;
    float hillLeftBud1 = hemisphere(queryPos - vec3(-10.0 - 3.0, groundY - 9.2, 13.5 + 4.), hillLeftBudRad1);
    if (hillLeftBud1 < finalDist) {
        finalMat = MAT_HILL;
    }
    finalDist = smoothUnion(finalDist, smin(hillLeft1, hillLeftBud1, 0.25), 0.25f);

    float hillLeftRad2 = 12.0;
    float hillLeft2 = hemisphere(queryPos - vec3(-11.0 - 3.0, groundY - 9.5, 8.5), hillLeftRad2);
    if (hillLeft2 < finalDist) {
        finalMat = MAT_HILL;
    }
    // finalDist = smoothUnion(finalDist, hillLeft2, 0.25f);

    float hillLeftRadBud2 = 8.0;
    float hillLeftBud2 = hemisphere(queryPos - vec3(-8.7 - 3.0, groundY - 5.61, 3.5), hillLeftRadBud2);
    if (hillLeftBud2 < finalDist) {
        finalMat = MAT_HILL;
    }
    finalDist = smoothUnion(finalDist, smin(hillLeft2, hillLeftBud2, 0.25f), 0.25f);

    float hillLeftBackRad1 = 10.0;
    float hillLeftBack1 = hemisphere(queryPos - vec3(-26.45, groundY - 5.0, 21.0), hillLeftBackRad1);
    if (hillLeftBack1 < finalDist) {
        finalMat = MAT_HILL;
    }
    finalDist = smoothUnion(finalDist, hillLeftBack1, 0.25f);

    float hillLeftBackRad2 = 15.0;
    float hillLeftBack2 = hemisphere(queryPos - vec3(-26.95, groundY - 10.0, 15.0), hillLeftBackRad2);
    if (hillLeftBack2 < finalDist) {
        finalMat = MAT_HILL;
    }
    finalDist = smoothUnion(finalDist, hillLeftBack2, 0.25f);

    float hillLeftFrontRad = 10.0;
    float hillLeftFront = hemisphere(queryPos - vec3(-5.9 - 3.0, groundY - 8.45, -5.0), hillLeftFrontRad);
    if (hillLeftFront < finalDist) {
        finalMat = MAT_HILL;
    }
    finalDist = smoothUnion(finalDist, hillLeftFront, 0.25f);

    float hillRightRad1 = 15.0;
    float hillRight1 = hemisphere(queryPos - vec3(13.0, groundY - 11.0, 19.0 + 4.5), hillRightRad1);
    if (hillRight1 < finalDist) {
        finalMat = MAT_HILL;
    }
    // finalDist = smoothUnion(finalDist, hillRight1, 0.25f);
    
    float hillRightBudRad1 = 12.5;
    float hillRightBud1 = hemisphere(queryPos - vec3(13.5, groundY - 9.2, 13.5 + 4.), hillRightBudRad1);
    if (hillRightBud1 < finalDist) {
        finalMat = MAT_HILL;
    }
    finalDist = smoothUnion(finalDist, smin(hillRight1, hillRightBud1, 0.25), 0.25f);
    
    float hillRightRad2 = 12.3;
    float hillRight2 = hemisphere(queryPos - vec3(14.0, groundY - 9.5, 8.5), hillRightRad2);
    if (hillRight2 < finalDist) {
        finalMat = MAT_HILL;
    }
    // finalDist = smoothUnion(finalDist, hillRight2, 0.25f);

    float hillRightRadBud2 = 5.0;
    float hillRightBud2 = hemisphere(queryPos - vec3(10.15, groundY - 2.41, 2.5), hillRightRadBud2);
    if (hillRightBud2 < finalDist) {
        finalMat = MAT_HILL;
    }
    finalDist = smoothUnion(finalDist, min(hillRight2, hillRightBud2), 0.25f);

    float hillRightBackRad1 = 10.0;
    float hillRightBack1 = hemisphere(queryPos - vec3(26.45, groundY - 5.0, 21.0), hillRightBackRad1);
    if (hillRightBack1 < finalDist) {
        finalMat = MAT_HILL;
    }
    finalDist = smoothUnion(finalDist, hillRightBack1, 0.25f);

    float hillRightBackRad2 = 9.0;
    float hillRightBack2 = hemisphere(queryPos - vec3(25.55, groundY - 3.25, 15.0), hillRightBackRad2);
    if (hillRightBack2 < finalDist) {
        finalMat = MAT_HILL;
    }
    finalDist = smoothUnion(finalDist, hillRightBack2, 0.25f);
    
    float hillRightFrontRad = 8.0;
    float hillRightFront = hemisphere(queryPos - vec3(7.9, groundY - 6.45, -6.0), hillRightFrontRad);
    if (hillRightFront < finalDist) {
        finalMat = MAT_HILL;
    }
    finalDist = smoothUnion(finalDist, hillRightFront, 0.25f);

    obj.distance_t = finalDist;
    obj.material_id = finalMat;
    return obj;
}

Ray getRay(vec2 uv)
{
    Ray r;
    
    vec3 look = normalize(u_Ref - u_Eye);
    vec3 camera_RIGHT = normalize(cross(look, u_Up));
    vec3 camera_UP = cross(camera_RIGHT, look);
    
    float aspect_ratio = u_Dimensions.x / u_Dimensions.y;
    vec3 screen_vertical = u_Up * tan(FOV);
    vec3 screen_horizontal = camera_RIGHT * aspect_ratio * tan(FOV);
    vec3 screen_point = (look + uv.x * screen_horizontal + uv.y * screen_vertical);
    
    r.origin = u_Eye;
    r.direction = normalize(screen_point - u_Eye);

    return r;
}

Ray getRay2(vec2 uv)
{
    Ray ray;
    
    float len = tan(3.14159 * 0.125) * distance(u_Eye, u_Ref);
    vec3 H = normalize(cross(vec3(0.0, 1.0, 0.0), u_Ref - u_Eye));
    vec3 V = normalize(cross(H, u_Eye - u_Ref));
    V *= len;
    H *= len * u_Dimensions.x / u_Dimensions.y;
    vec3 p = u_Ref + uv.x * H + uv.y * V;
    vec3 dir = normalize(p - u_Eye);
    
    ray.origin = u_Eye;
    ray.direction = dir;
    return ray;
}


vec3 estimateJoeNorm(vec3 p)
{
    // vec2 d = vec2(0.f, EPSILON);
    vec2 d = vec2(0.f, 0.5);
    float x = sceneSDF(p + d.yxx).distance_t - sceneSDF(p - d.yxx).distance_t;
    float y = sceneSDF(p + d.xyx).distance_t - sceneSDF(p - d.xyx).distance_t;
    float z = sceneSDF(p + d.xxy).distance_t - sceneSDF(p - d.xxy).distance_t;
    
    return normalize(vec3(x, y, z));
}

vec3 estimateNorm(vec3 p)
{
    vec2 d = vec2(0.f, EPSILON);
    // vec2 d = vec2(0.f, 0.5);
    float x = sceneSDF(p + d.yxx).distance_t - sceneSDF(p - d.yxx).distance_t;
    float y = sceneSDF(p + d.xyx).distance_t - sceneSDF(p - d.xyx).distance_t;
    float z = sceneSDF(p + d.xxy).distance_t - sceneSDF(p - d.xxy).distance_t;
    
    return normalize(vec3(x, y, z));
}

Intersection getRaymarchedIntersection(vec2 uv)
{
    Intersection intersection;
    
    intersection.distance_t = -1.0;
    Ray ray = getRay2(uv);
    float distance_t = 0.f;
    for (int step = MIN_RAY_STEPS; step < MAX_RAY_STEPS; ++step) {
        vec3 queryPoint = ray.origin + ray.direction * distance_t;
        hitObj obj = sceneSDF(queryPoint);
        if (obj.distance_t < EPSILON) {
            intersection.position = queryPoint;
            intersection.distance_t = distance_t;
            intersection.material_id = obj.material_id;
            if (obj.material_id == MAT_PORTAL) {
                intersection.normal = estimateNorm(queryPoint);
            } else if (uv.y < 0.75 && obj.material_id == MAT_JOE) {
                // intersection.normal = estimateNorm(queryPoint);
                intersection.normal = estimateJoeNorm(queryPoint);
            } else {
                intersection.normal = estimateNorm(queryPoint);
            }
            return intersection;
        }
        distance_t += obj.distance_t;
    }
    intersection.distance_t = -1.0;
    intersection.material_id = MAT_SKY;
    return intersection;
}

float softShadow(vec3 rDir, vec3 rOrigin, float mint, float maxt, float k)
{
    float res = 1.0;
    for (float t = mint; t < maxt;) {
        hitObj h = shadowSceneSDF(rOrigin + rDir * t);
        if (h.distance_t < 0.001) {
            return 0.0;
        }
        res = min(res, k * h.distance_t / t);
        t += h.distance_t;
    }
    return res;
}

// float shadow(vec3 dir, vec3 origin, float min_t) {
//     return softShadow(dir, origin, min_t, float(MAX_RAY_STEPS), 6.0);
// }

// float hardShadow(vec3 dir, vec3 origin, float min_t) {
//     float t = min_t;
//     for(int i = 0; i < MAX_RAY_STEPS; ++i) {
//         float m = sceneMap3D(origin + t * dir);
//         if(m < 0.0001) {
//             return 0.0;
//         }
//         t += m;
//     }
//     return 1.0;
// }

// float softShadow(vec3 dir, vec3 origin, float min_t, float k) {
//     float res = 1.0;
//     float t = min_t;
//     for(int i = 0; i < MAX_RAY_STEPS; ++i) {
//         float m = sceneMap3D(origin + t * dir);
//         if(m < 0.0001) {
//             return 0.0;
//         }
//         res = min(res, k * m / t);
//         t += m;
//     }
//     return res;
// }

float shadow(vec3 dir, vec3 origin, float min_t) {
    // #if HARD_SHADOW
    // return hardShadow(dir, origin, min_t);
    // #else
    return softShadow(dir, origin, min_t, 100.0, 2.0);
    // #endif
}

vec3 palette( in float t, in vec3 a, in vec3 b, in vec3 c, in vec3 d )
{
    return a + b*cos( 6.28318*(c*t+d) );
}

vec3 computeMat(int mat_id, vec3 p, vec3 n) {
    float noise;
    vec3 out_col;
    switch(mat_id) {
        case MAT_HILL:
        // return rgb(76.0, 81.0, 200.0);
        return rgb(96.0, 96.0, 203.0);
        break;
        case MAT_GROUND:
        vec3 ground_col = rgb(45.0, 77.0, 162.0);
        vec3 light_ground = rgb(93.0, 176.0, 226.0);
        // noise = (fbm(5.0, p.xz) + 1.338) / 2.638;
        // noise = smoothstep(0.89, 0.99, noise);
        // ground_col = mix(ground_col, light_ground, noise);
        noise = rand3(p);
        if (noise < 0.9) {
            noise = 0.0;
        }
        out_col = mix(ground_col, rgb(255.0, 255.0, 255.0), noise);
        return out_col;
        break;
        case MAT_JOE:
        return rgb(100.0, 200.0, 255.0);
        break;
        case MAT_SKY:
        return rgb(255.0, 255.0, 255.0);
        break;
        default:
        return rgb(255.0, 0.0, 0.0);
        break;
    }
}

vec3 getSkyColor(vec2 uv) {
    float noise = (fbm(10.0, uv) + 1.338) / 2.638;
    vec3 blue = rgb(138.0, 140.0, 223.0);
    vec3 pink = rgb(246.0, 187.0, 244.0);
    float y_mix = smoothstep(0.3, 0.6, uv.y);
    vec3 col = mix(blue, pink, noise + 0.25);
    vec3 out_col = mix(col, blue, y_mix);
    // vec3 out_col = mix(col, blue, uv.y);
    return out_col;
}

vec3 getSceneColor2(vec2 uv)
{
    Intersection intersection = getRaymarchedIntersection(uv);
    if (intersection.material_id == MAT_SKY) {
        return getSkyColor(uv);
    }
    Ray r = getRay(uv);
    // vec3 isect = u_Eye + intersection.distance_t * r.direction;
    // vec3 nor = estimateNorm(intersection.position);
    // vec3 view = normalize(u_Eye - intersection.position);
    
    vec3 isect = intersection.position;
    vec3 nor = intersection.normal;
    vec3 mat = computeMat(intersection.material_id, isect, nor);
    
    vec3 warmDir = normalize(vec3(-1.0, 0.71, 0.0));
    vec3 coolDir = normalize(vec3(0, 0.5, 5.0));

    float warmDot = max(0.0, dot(nor, warmDir));
    float coolDot = max(0.0, dot(nor, coolDir));

    // vec3 warmLight = rgb(204.0, 150.0, 255.0);
    vec3 warmLight = rgb(255.0, 255.0, 255.0);
    // vec3 coolLight = vec3(0.05, 0.2, 0.5);
    vec3 coolLight = rgb(0.05, 0.2, 0.5) * 20.0;

    vec3 color = warmDot * warmLight * shadow(warmDir, isect, 0.1);
    color += coolDot * coolLight;
    color *= mat;
    color += SUN_AMBIENT_LIGHT;
    color = clamp(color + vec3(0.05, 0.1, 0.15), 0.0, 1.0);
    
    return color;
}

void main() {
    // Normalized pixel coordinates (from 0 to 1)
    vec2 uv = fs_Pos;
    
    // Make symmetric [-1, 1]
    // uv = uv * 2.0 - 1.0;

    // Time varying pixel color
    // vec3 col = getSceneColor(uv);
    vec3 col = getSceneColor2(uv);

    // Output to screen
    out_Col = vec4(col,1.0);
    // out_Col = vec4(0.5 * (fs_Pos + vec2(1.0)), 0.5 * (sin(u_Time * 3.14159 * 0.01) + 1.0), 1.0);
}
