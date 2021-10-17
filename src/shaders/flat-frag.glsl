#version 300 es
precision highp float;

uniform vec3 u_Eye, u_Ref, u_Up;
uniform vec2 u_Dimensions;
uniform float u_Time;

in vec2 fs_Pos;
out vec4 out_Col;

const int MAX_RAY_STEPS = 100;
const float FOV = 45.0;
const float EPSILON = 0.0001;

#define STAR_ANIM_SPEED .5

const vec3 EYE = vec3(0.0, 0.0, 10.0);
const vec3 ORIGIN = vec3(0.0, 0.0, 0.0);
const vec3 WORLD_UP = vec3(0.0, 1.0, 0.0);
const vec3 WORLD_RIGHT = vec3(-1.0, 0.0, 0.0);
const vec3 WORLD_FORWARD = vec3(0.0, 0.0, 1.0);

#define SHAKING vec3(sin(u_Time * .2 * STAR_ANIM_SPEED) * .1, cos(u_Time * .4 * STAR_ANIM_SPEED) * .1, sin(((u_Time + 100.0) * STAR_ANIM_SPEED) * .3))

#define BACKLIGHT_POS normalize(vec3(1.2, 1.0, -.75)) * 5.0  - SHAKING
#define EYELIGHT_POS vec3(0.1, .3, 1.0) - SHAKING

#define STARLIGHT_BACKLIGHT_POS vec3(0.0, 0.0, -1.0)
#define STARLIGHT_GLOW_POS vec3(-0.1,-1., 0.05) - SHAKING

#define STAR_ARM_MAT 1
#define FEET_MAT 2
#define BODY_MAT 3
#define EYE_MAT 4
#define ARM_MAT 5
#define STAR_CENTER_MAT 6
#define MOUTH_MAT 7
#define CHEEK_MAT 8
#define EYELIGHT_MAT 9

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

struct SDF
{
    float t;
    int material_id;
};

float sdSphere( vec3 p, float s )
{
  return length(p)-s;
}

float sdEllipsoid( vec3 p, vec3 r )
{
  float k0 = length(p/r);
  float k1 = length(p/(r*r));
  return k0*(k0-1.0)/k1;
}

float sdRoundCone( vec3 p, float r1, float r2, float h )
{
  vec2 q = vec2( length(p.xz), p.y );
    
  float b = (r1-r2)/h;
  float a = sqrt(1.0-b*b);
  float k = dot(q,vec2(-b,a));
    
  if( k < 0.0 ) return length(q) - r1;
  if( k > a*h ) return length(q-vec2(0.0,h)) - r2;
        
  return dot(q, vec2(a,b) ) - r1;
}

float sdCapsule( vec3 p, vec3 a, vec3 b, float r )
{
  vec3 pa = p - a, ba = b - a;
  float h = clamp( dot(pa,ba)/dot(ba,ba), 0.0, 1.0 );
  return length( pa - ba*h ) - r;
}

float sdVertCapsule( vec3 p, float h, float r )
{
  p.y -= clamp( p.y, 0.0, h );
  return length( p ) - r;
}

float ndot(vec2 a, vec2 b ) { return a.x*b.x - a.y*b.y; }

float sdRhombus(vec3 p, float la, float lb, float h, float ra)
{
  p = abs(p);
  vec2 b = vec2(la,lb);
  float f = clamp( (ndot(b,b-2.0*p.xz))/dot(b,b), -1.0, 1.0 );
  vec2 q = vec2(length(p.xz-0.5*b*vec2(1.0-f,1.0+f))*sign(p.x*b.y+p.z*b.x-b.x*b.y)-ra, p.y-h);
  return min(max(q.x,q.y),0.0) + length(max(q,0.0));
}

vec3 rotateX(vec3 p, float a) {
    return vec3(p.x, cos(a) * p.y - sin(a) * p.z, sin(a) * p.y + cos(a) * p.z);
}

vec3 rotateY(vec3 p, float a) {
    return vec3(cos(a) * p.x + sin(a) * p.z, p.y, -sin(a) * p.x + cos(a) * p.z);
}

vec3 rotateZ(vec3 p, float a) {
    return vec3(cos(a) * p.x - sin(a) * p.y, sin(a) * p.x + cos(a) * p.y, p.z);
}

float opRound( float p, float rad )
{
    return p - rad;
}

float smin( float a, float b, float k )
{
    float h = clamp( 0.5+0.5*(b-a)/k, 0.0, 1.0 );
    return mix( b, a, h ) - k*h*(1.0-h);
}

float opUnion( float d1, float d2 ) { return min(d1,d2); }

float opSmoothSub( float d1, float d2, float k ) {
    float h = clamp( 0.5 - 0.5*(d2+d1)/k, 0.0, 1.0 );
    return mix( d2, -d1, h ) + k*h*(1.0-h); }

vec3 opCheapBend( vec3 p )
{
    const float k = 1.; // or some other amount
    float c = cos(k*(p.y - .4));
    float s = sin(k*(p.y - .4));
    mat2  m = mat2(c,-s,s,c);
    vec3  q = vec3(m*p.xy,p.z);
    return q;
}

float bias( float value, float biasVal)
{
  return (value / ((((1.0/biasVal) - 2.0)*(1.0 - value))+1.0));
}

float gain(float value, float gainVal)
{
  if(value < 0.5)
    return bias(value * 2.0,gainVal)/2.0;
  else
    return bias(value * 2.0 - 1.0,1.0 - gainVal)/2.0 + 0.5;
}

float remapVal(float val, float min1, float max1, float min2, float max2) {
    return val - (min1 - min2) * (max2 - min2) / (max1 - min1);
}

float kirbyBounce(float val) {
    return bias(gain(val, .8), .1);
}

#define KIRBY_ROT_VAL_X -.2
#define KIRBY_ROT_VAL_Y .4
#define KIRBY_ROT_VAL_Z .0
#define KIRBY_ANIM_SPEED .7

SDF starSDF(vec3 queryPos) 
{   
    float scale = .6;
    float starRot = 1.25;
    vec3 starCenter = rotateX(queryPos, -.2);
    vec3 starOffset = scale * vec3(-1.0, 0.0, 0.0);
    float axis1 = 1. * scale;
    float axis2 = .7 * scale;
    float thick = .02 * scale;
    float round = .02 * scale;

    vec3 armPos1 = starCenter - starOffset;
    vec3 armPos2 = rotateY(starCenter, starRot) - starOffset;
    vec3 armPos3 = rotateY(starCenter, starRot * 2.0) - starOffset;
    vec3 armPos4 = rotateY(starCenter, starRot * 3.0) - starOffset;
    vec3 armPos5 = rotateY(starCenter, starRot * 4.0) - starOffset;
    
    float arm1 = sdRhombus(armPos1, axis1, axis2, thick, round);
    float arm2 = sdRhombus(armPos2, axis1, axis2, thick, round);
    float arm3 = sdRhombus(armPos3, axis1, axis2, thick, round);
    float arm4 = sdRhombus(armPos4, axis1, axis2, thick, round);
    float arm5 = sdRhombus(armPos5, axis1, axis2, thick, round);

    float centerBulge = sdEllipsoid(starCenter, scale * vec3(1.1, .25, 1.1));

    float star = smin(arm1, arm2, .02);
    star = smin(star, arm3, .02);
    star = smin(star, arm4, .02);
    star = smin(star, arm5, .02);
    star = smin(star, centerBulge, .1);

    if (centerBulge <= EPSILON + .125) {
        return SDF(opRound(star, .1), STAR_CENTER_MAT);
    }
    return SDF(opRound(star, .1), STAR_ARM_MAT);
}

SDF kirbyStarSDF(vec3 queryPos) {
    vec3 starOffset = vec3(0.0, -.70, 0.0);

    float armDownRemap = remapVal(sin(u_Time * .5 * KIRBY_ANIM_SPEED) * .3, -.3, .3, 0.0, 1.0);
    float armBobDown = kirbyBounce(armDownRemap) * 1.5;
    float armUpRemap = remapVal(sin(u_Time * .5 * KIRBY_ANIM_SPEED) * .2, -.2, .2, 0.0, 1.0);
    float armBobUp = kirbyBounce(armUpRemap) * 1.5;

    float bodyDeformTime = sin(u_Time * .5 * KIRBY_ANIM_SPEED) * .05;
    float bodyDeform = kirbyBounce(bodyDeformTime);

    vec3 bodyPos = rotateZ(rotateY(rotateX(queryPos + vec3(0.0, -bodyDeform, 0.0), KIRBY_ROT_VAL_X), KIRBY_ROT_VAL_Y), KIRBY_ROT_VAL_Z);
    vec3 feetBasePos = rotateZ(rotateY(rotateX(queryPos, KIRBY_ROT_VAL_X), KIRBY_ROT_VAL_Y), KIRBY_ROT_VAL_Z);
    
    vec3 leftEyePos = rotateY(bodyPos - normalize(vec3(-.19, -0.3 + bodyDeform, 1.0)) * .6, 1.5);
    vec3 rightEyePos = rotateY(bodyPos - normalize(vec3(.19, -0.3 + bodyDeform, 1.0)) * .6, 1.5);

    vec3 leftEyeLightPos = bodyPos - normalize(vec3(-.19, -0.2 + bodyDeform, 1.0)) * .6;
    vec3 rightEyeLightPos = bodyPos - normalize(vec3(.19, -0.2 + bodyDeform, 1.0)) * .6;

    vec3 leftCheekBasePos = vec3(-.4, -.3 + bodyDeform, 1.0);
    vec3 rightCheekBasePos = vec3(.4, -.3 + bodyDeform, 1.0);

    vec3 leftCheekPos = rotateY(bodyPos - normalize(leftCheekBasePos) * .65, .25);
    vec3 rightCheekPos = rotateY(bodyPos - normalize(rightCheekBasePos) * .65, -.25);
    
    vec3 armDownPos = rotateX(rotateY(bodyPos - normalize(vec3(-1.5, -.75 + armBobDown, 1.2)) * .65, .3), -.3);
    vec3 armUpPos = rotateX(rotateY(bodyPos - normalize(vec3(1.5, 1.0 + armBobUp, -1.0)) * .65, .6), -.3);
    
    vec3 leftFootPos = rotateZ(rotateX(feetBasePos - normalize(vec3(-1., -.9, 0.2)) * .6, -2.3), -.9);
    vec3 rightFootPos = rotateZ(rotateX(feetBasePos - normalize(vec3(1., -.9, 0.2)) * .6, -2.3), .9);

    vec3 mouthPos = bodyPos - normalize(vec3(0.0, -.75, 1.0)) * .65;

    vec3 bodyScale = vec3(0.65, 0.6 + bodyDeform, 0.65);
    vec3 eyeScale = vec3(.15, .2, .05);
    vec3 armScale = vec3(.15, .15, .3);

    float kirbyBody = sdEllipsoid(bodyPos, bodyScale);

    float kirbyLeftEye = sdVertCapsule(opCheapBend(leftEyePos), .25 + bodyDeform, .06);
    float kirbyRightEye = sdVertCapsule(opCheapBend(rightEyePos), .25 + bodyDeform, .06);
    float kirbyDownArm = sdEllipsoid(armDownPos, armScale);
    float kirbyUpArm = sdEllipsoid(armUpPos, armScale);
    float kirbyLeftFoot = sdRoundCone(leftFootPos, .22, .15, .2);
    float kirbyRightFoot = sdRoundCone(rightFootPos, .22, .15, .2);
    float kirbyMouth = sdSphere(mouthPos, .1);
    float kirbyLeftCheek = sdCapsule(leftCheekPos, -vec3(.05, 0.0, 0.0), vec3(0.0), .05);
    float kirbyRightCheek = sdCapsule(rightCheekPos, vec3(.05, 0.0, 0.0), vec3(0.0), .05);

    float leftEyeLight = sdSphere(leftEyeLightPos, .125);
    float rightEyeLight = sdSphere(rightEyeLightPos, .125);

    leftEyeLight = max(leftEyeLight, kirbyLeftEye);
    rightEyeLight = max(rightEyeLight, kirbyRightEye);
     
    SDF star = starSDF(feetBasePos - starOffset);

    float kirby = smin(kirbyBody, kirbyDownArm, .01);
    kirby = smin(kirby, kirbyLeftFoot, .01);
    kirby = smin(kirby, kirbyRightFoot, .01);    
    kirby = opUnion(kirby, kirbyLeftEye);
    kirby = opUnion(kirby, kirbyRightEye);
    kirby = smin(kirby, kirbyUpArm, .01);
    kirby = opSmoothSub(kirbyMouth, kirby, .01);
    kirby = opUnion(kirby, star.t);

    if (star.t <= EPSILON) {
        return star;
    }
    if (kirbyLeftFoot <= EPSILON || kirbyRightFoot <= EPSILON) {
        return SDF(kirby, FEET_MAT);
    }
    if (leftEyeLight <= EPSILON || rightEyeLight <= EPSILON) {
        return SDF(kirby, EYE_MAT);
    }
    if (kirbyLeftEye <= EPSILON || kirbyRightEye <= EPSILON) {
        return SDF(kirby, EYELIGHT_MAT);
    }
    if (kirbyDownArm <= EPSILON || kirbyUpArm <= EPSILON) {
        return SDF(kirby, ARM_MAT);
    }
    if (kirbyMouth <= EPSILON) {
        return SDF(kirby, MOUTH_MAT);
    }
    if (kirbyLeftCheek <= EPSILON || kirbyRightCheek <= EPSILON) {
        return SDF(kirby, CHEEK_MAT);
    }
    return SDF(kirby, BODY_MAT);
}


SDF sceneSDF(vec3 queryPos) 
{
    float boundSphere = sdSphere(queryPos, 3.0);
    if (boundSphere <= EPSILON) {
        SDF kirbyStar = kirbyStarSDF(queryPos + SHAKING);
        return kirbyStar;
    }
    return SDF(1.0, 0);
}

Ray getRay(vec2 uv)
{
    Ray r;
    
    vec3 look = normalize(u_Ref - u_Eye);
    vec3 camera_RIGHT = normalize(cross(look, u_Up));
    
    float aspect_ratio = u_Dimensions.x / u_Dimensions.y;
    vec3 screen_vertical = u_Up * tan(FOV); 
    vec3 screen_horizontal = camera_RIGHT * aspect_ratio * tan(FOV);
    vec3 screen_point = (look + uv.x * screen_horizontal + uv.y * screen_vertical);
    
    r.origin = u_Eye;
    r.direction = normalize(screen_point - u_Eye);
   
    return r;
}

vec3 getNormal(vec3 point) {
    vec2 dVec = vec2(0.0, EPSILON);
    float x = sceneSDF(point + dVec.yxx).t - sceneSDF(point - dVec.yxx).t;
    float y = sceneSDF(point + dVec.xyx).t - sceneSDF(point - dVec.xyx).t;
    float z = sceneSDF(point + dVec.xxy).t - sceneSDF(point - dVec.xxy).t;

    return normalize(vec3(x, y, z));
}

Intersection getRaymarchedIntersection(vec2 uv)
{
    Ray ray = getRay(uv);
    Intersection intersection;
    
    intersection.distance_t = -1.0;
    float t = 0.0;
    SDF currDist;

    for (int step = 0; step < MAX_RAY_STEPS; ++step) {
        vec3 queryPos = ray.origin + ray.direction * t;
            SDF currDist = sceneSDF(queryPos);
            if (currDist.t < EPSILON) {
            intersection.distance_t = t;
            intersection.normal = getNormal(queryPos);
            intersection.position = queryPos;
            intersection.material_id = currDist.material_id;
            return intersection;
        }
        t += currDist.t;
    }
    return intersection;
}

float softShadow( in vec3 ro, in vec3 rd, float maxt, float k )
{
    float res = 1.0;
    for( float t=0.015; t<maxt; )
    {
        float h = sceneSDF(ro + rd*t).t;
        if( h< .001 )
            return 0.0;
        res = min( res, k*h/t );
        t += h;
    }
    return res * res;
}

vec3 rgb(vec3 rgb) {
    return rgb / 255.0;
}

vec4 permute(vec4 x){return mod(((x*34.0)+1.0)*x, 289.0);}

//	Classic Perlin 2D Noise 
//	by Stefan Gustavson
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

float rand(vec2 co){
    return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

// Adjust these to alter where the subsurface glow shines through and how brightly
const float FIVETAP_K = 1.0;
const float AO_DIST = 0.01;

// The larger the DISTORTION, the smaller the glow
const float DISTORTION = 0.5;
// The higher GLOW is, the smaller the glow of the subsurface scattering
const float GLOW = 2.3;
// The higher the BSSRDF_SCALE, the brighter the scattered light
const float BSSRDF_SCALE = 2.0;
// Boost the shadowed areas in the subsurface glow with this
const float AMBIENT = 0.05;
// Toggle this to affect how easily the subsurface glow propagates through an object

float subsurface(vec3 lightDir, vec3 normal, vec3 viewVec, float thickness) {
    vec3 scatteredLightDir = lightDir + normal * DISTORTION;
    float lightReachingEye = pow(clamp(dot(viewVec, -scatteredLightDir), 0.0, 1.0), GLOW) * BSSRDF_SCALE;
	float totalLight = (lightReachingEye + AMBIENT) * thickness;
    return totalLight;
}

float fiveTapAO(vec3 p, vec3 n, float k) {
    float aoSum = 0.0;
    for(float i = 0.0; i < 5.0; ++i) {
        float coeff = 1.0 / pow(2.0, i);
        aoSum += coeff * (i * AO_DIST - sceneSDF(p + n * i * AO_DIST).t);
    }
    return 1.0 - k * aoSum;
}

float lambertian(vec3 lightDir, vec3 normal) {
    return max(dot(lightDir, normal), 0.0);
}

#define EYE_SHINY 5.0
const vec3 eyeLightColor = vec3(1.0, 1.0, 1.0);
const float eyeLightPower = 10.0;
#define eyeSpecColor rgb(vec3(255.0, 246.0, 156.0))

vec3 eyeReflection(vec3 normal, vec3 lightDir, vec3 pos, vec3 color) {
    float distance = length(lightDir);
    distance = distance * distance;
    lightDir = normalize(lightDir);
    float lambert = lambertian(lightDir, normal);
    float specular = 0.0;

    if (lambert > 0.0) {
        vec3 viewDir = normalize(-pos);

        // this is blinn phong
        vec3 halfDir = normalize(lightDir + viewDir);
        float specAngle = max(dot(halfDir, normal), 0.0);
        specular = pow(specAngle, EYE_SHINY);
    }
    vec3 diffuseColor = color;
    vec3 colorLinear = diffuseColor * eyeLightColor / distance * distance +
             eyeSpecColor * specular * eyeLightColor * eyeLightPower * eyeLightPower / distance;
    return colorLinear;
}

#define STAR_SHINY 100.0
const float starLightPower = 9.0;

float starReflection(vec3 normal, vec3 lightDir, vec3 pos) {
    float distance = length(lightDir);
    distance = distance * distance;
    lightDir = normalize(lightDir);
    float specular = 0.0;

    vec3 viewDir = normalize(vec3(-0.19, 1.0, 1.0));

    // this is blinn phong
    vec3 halfDir = normalize(lightDir + viewDir);
    float specAngle = max(dot(halfDir, normal), 0.0);
    specular = pow(specAngle, STAR_SHINY);
    float colorLinear = specular * starLightPower / distance;
    return colorLinear;
}

vec3 getMatColor(int matID, Intersection isect)
{
    float shading;
    vec3 yellowLight = rgb(vec3(255.0, 253.0, 171.0));
    vec3 starColor = rgb(vec3(255.0, 240.0, 94.0));
    vec3 starGlowColor = rgb(vec3(255.0, 246.0, 156.0));
    vec3 starLightGlowPos = STARLIGHT_GLOW_POS - isect.position;
    float bodyStarGlow = lambertian(starLightGlowPos, isect.normal) / pow(length(starLightGlowPos), 1.5);
    float armStarGlow = lambertian(starLightGlowPos, isect.normal) / (length(starLightGlowPos) * 2.0);
    float thickness;
    float starSubsurface;
    vec3 starBaseColor;
    switch (matID) {
        case STAR_ARM_MAT:
            thickness = fiveTapAO(isect.position, -isect.normal, FIVETAP_K);
            starSubsurface = clamp(subsurface(STARLIGHT_BACKLIGHT_POS, isect.normal, normalize(u_Eye - isect.position), thickness), 0.3, 1.0);
            return mix(vec3(1.2), starColor, starSubsurface);
        
        case STAR_CENTER_MAT:
            thickness = fiveTapAO(isect.position, -isect.normal, FIVETAP_K);
            float starLerp = starReflection(isect.normal, (isect.position + vec3(0.0, 2.5, 0.01)) - isect.position, isect.position + vec3(0.1, 0.0, -.5) + SHAKING);
            starSubsurface = clamp(subsurface(STARLIGHT_BACKLIGHT_POS, isect.normal, normalize(u_Eye - isect.position), thickness), 0.3, 1.0);
            starBaseColor = mix(vec3(1.2), starColor, starSubsurface);
            return mix(starBaseColor, vec3(1.0), starLerp);
        
        case BODY_MAT:
            shading = softShadow(isect.position, normalize(BACKLIGHT_POS - isect.position), .1, 1.75) + .5;
            return mix(rgb(vec3(255.0, 168.0, 225.0)) * shading * yellowLight, starGlowColor, bodyStarGlow);
        
        case FEET_MAT:
            shading = softShadow(isect.position, normalize(BACKLIGHT_POS - isect.position), .1, 1.75) + .5;
            return mix(rgb(vec3(255.0, 94.0, 199.0)) * shading * yellowLight, starGlowColor, bodyStarGlow);
        
        case ARM_MAT:
            shading = softShadow(isect.position, normalize(BACKLIGHT_POS - isect.position), .1, 1.75) + .5;
            return mix(rgb(vec3(255.0, 168.0, 225.0)) * shading * yellowLight, starGlowColor, armStarGlow);
        
        case EYE_MAT:
            vec3 eyeColor = rgb(vec3(0.0, 8.0, 46.0));
            return eyeReflection(isect.normal, EYELIGHT_POS - isect.position, isect.position + SHAKING, eyeColor);
        
        case EYELIGHT_MAT:
            shading = softShadow(isect.position, normalize(BACKLIGHT_POS - isect.position), .1, 1.75) + .5;
            vec3 eyeshine = vec3(1.0) * shading;
            return eyeReflection(isect.normal, EYELIGHT_POS - isect.position, isect.position + SHAKING, eyeshine);

        case MOUTH_MAT:
            return vec3(0.0);
        
        case CHEEK_MAT:
            shading = softShadow(isect.position, normalize(BACKLIGHT_POS - isect.position), .1, 1.75) + .5;
            return mix(rgb(vec3(255.0, 94.0, 171.0)) * shading * yellowLight, starGlowColor, bodyStarGlow);

    }
    return vec3(0.0);
}

vec3 getSceneColor(vec2 uv)
{
    Intersection intersection = getRaymarchedIntersection(uv);
    if (intersection.distance_t > 0.0)
    {
        int matID = intersection.material_id;
        return getMatColor(matID, intersection);
    }
    vec3 skyColor = rgb(vec3(69.0, 53.0, 48.0));
    float cloudBound = (fbm(7.0, vec2((uv.x - u_Time * .15) * .3, (uv.y + sin(u_Time * .02)) * .5)) + 1.338) / 2.638;
    float baseNoise = (fbm(7.0, vec2(uv.x - u_Time * .15, uv.y + sin(u_Time * .02))) + 1.338) / 2.638; // fbm mapped from 0 to 1
    vec3 cloudColor = vec3(1.0);

    vec3 bgCol = mix(skyColor, skyColor + cloudColor * baseNoise, smoothstep(.4, .5, cloudBound));

    float streakBound = sin(-(uv.y + cos(u_Time * .01 + uv.x) * .1) * 5.0 + cos(-uv.y * .5 * 5.0)) + cos(u_Time * .4) * .04;
    if (streakBound > -1. && streakBound < 0.5) {
        float distAcross = -cos(uv.y + u_Time * .05) * 2.0 * uv.y + uv.x + 2.5 + sin((u_Time + uv.y) * .025) * .5 + cos(u_Time * .12) * .05;
        if (distAcross > 1.0) {
            vec3 starColor = rgb(vec3(255.0, 246.0, 156.0));
            vec3 lightColor = mix(vec3(1.0), starColor, pow(((streakBound + .25) * 4.0), 2.0));
            vec3 mixEdge1 = mix(bgCol, bgCol + lightColor, gain(smoothstep(-1., -.5, streakBound), .7));
            vec3 mixEdge2 = mix(mixEdge1, bgCol, gain(smoothstep(0.0, .5, streakBound), .7));
            bgCol = mixEdge2;
        }
    }

    vec2 noisedUV = vec2((uv.x  + u_Time)* 30.0, (uv.y + SHAKING.y) * 30.0 );
    float yBoundHigh = -.5 + SHAKING.y + uv.x * .5;
    float yBoundLow = -.7 + SHAKING.y - uv.x * .15;
    if (uv.y < yBoundHigh && uv.y > yBoundLow && uv.x > SHAKING.x) {
        float sparkleNoise = fbm(7.0, noisedUV);
        if (sparkleNoise > -.2) {
            vec3 sparkleBaseCol = rgb(vec3(255.0, 247.0, 184.0));
            vec3 trailCol = mix(bgCol, vec3(1.0) + sparkleBaseCol, gain(smoothstep(-.1, .9, sparkleNoise * sparkleNoise), .7));
            vec3 up = mix(bgCol, trailCol, smoothstep(yBoundLow, yBoundLow + .1, uv.y));
            bgCol = mix(up, bgCol, smoothstep(yBoundHigh - .1, yBoundHigh, uv.y));
        }
    }
    return bgCol;
}

void main() {
    out_Col = vec4(getSceneColor(fs_Pos.xy), 1.0);
}
