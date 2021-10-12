#version 300 es
precision highp float;

uniform vec3 u_Eye, u_Ref, u_Up;
uniform vec2 u_Dimensions;
uniform float u_Time;

uniform vec3 u_CameraPos;

in vec2 fs_Pos;
in vec4 fs_Pos4;

out vec4 out_Col;

const int MAX_MARCHING_STEPS = 255;
const float MIN_DIST = 0.0;
const float MAX_DIST = 200.0;

const int MAX_RAY_STEPS = 128;
const float FOV = 3.141569 * 0.30;
const float EPSILON = 1e-5;


#define BLUE_CUBE 1
#define BLUE_PLANK 2
#define BLUE_SABER 3
#define BLUE_SIDE 4
#define INSIDE 5
#define RED_CUBE 11
#define RED_SABER 12
#define WHITE_TRIANGLE 233
#define WHITE_GLOW 666

#define TO_RADIAN 3.14159/180.0
#define TIME u_Time

const float DELTA = 0.085;
const float K = 2.;

// The larger the DISTORTION, the smaller the glow
const float DISTORTION = 0.2;
// The higher GLOW is, the smaller the glow of the subsurface scattering
const float GLOW = 5.0;
// The higher the BSSRDF_SCALE, the brighter the scattered light
const float BSSRDF_SCALE = 3.0;
// Boost the shadowed areas in the subsurface glow with this
const float AMBIENT = 0.1;

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


//noise from https://www.shadertoy.com/view/MtcyWr
float n21 (vec3 uvw)
{
    return fract(sin(uvw.x*23.35661 + uvw.y*6560.65 + uvw.z*4624.165)*2459.452);
}

float smoothNoise (vec3 uvw)
{
    float fbl = n21(floor(uvw));
    float fbr = n21(vec3(1.0,0.0,0.0)+floor(uvw));
    float ful = n21(vec3(0.0,1.0,0.0)+floor(uvw));
    float fur = n21(vec3(1.0,1.0,0.0)+floor(uvw));
    
    float bbl = n21(vec3(0.0,0.0,1.0)+floor(uvw));
    float bbr = n21(vec3(1.0,0.0,1.0)+floor(uvw));
    float bul = n21(vec3(0.0,1.0,1.0)+floor(uvw));
    float bur = n21(vec3(1.0,1.0,1.0)+floor(uvw));
    
    uvw = fract(uvw);
    vec3 blend = uvw;
    blend = (blend*blend*(3.0 -2.0*blend)); // cheap smoothstep
    
    return mix(	mix(mix(fbl, fbr, blend.x), mix(ful, fur, blend.x), blend.y),
        		mix(mix(bbl, bbr, blend.x), mix(bul, bur, blend.x), blend.y),
               	blend.z);
}

float perlinNoise3D (vec3 uvw)
{
    float blended = smoothNoise(uvw*4.0);
    blended += smoothNoise(uvw*8.0)*0.5;
    blended += smoothNoise(uvw*16.0)*0.25;
    blended += smoothNoise(uvw*32.0)*0.125;
    blended += smoothNoise(uvw*64.0)*0.0625;
    
    blended /= 2.0;
    //blended = fract(blended*2.0)*0.5+0.5;
    blended *= pow(0.8-abs(uvw.y),2.0);
    return blended;
}

float sdfSphere(vec3 query_position, vec3 position, float radius)
{
    return length(query_position - position) - radius;
}

float sdBox( vec3 p, vec3 b )
{
  vec3 q = abs(p) - b;
  return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0);
}

float sdSphere( vec3 p, float s )
{
  return length(p)-s;
}

float sdRoundBox( vec3 p, vec3 b, float r )
{
  vec3 q = abs(p) - b;
  return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0) - r;
}

float sdCappedCylinder( vec3 p, float h, float r )
{
  vec2 d = abs(vec2(length(p.xz),p.y)) - vec2(h,r);
  return min(max(d.x,d.y),0.0) + length(max(d,0.0));
}

float sdTriPrism( vec3 p, vec2 h )
{
  vec3 q = abs(p);
  return max(q.z-h.y,max(q.x*0.866025+p.y*0.5,-p.y)-h.x*0.5);
}

float sdCapsule( vec3 p, vec3 a, vec3 b, float r )
{
  vec3 pa = p - a, ba = b - a;
  float h = clamp( dot(pa,ba)/dot(ba,ba), 0.0, 1.0 );
  return length( pa - ba*h ) - r;
}


float dot2( in vec2 v ) { return dot(v,v); }
float dot2( in vec3 v ) { return dot(v,v); }
float ndot( in vec2 a, in vec2 b ) { return a.x*b.x - a.y*b.y; }

float udTriangle( vec3 p, vec3 a, vec3 b, vec3 c )
{
  vec3 ba = b - a; vec3 pa = p - a;
  vec3 cb = c - b; vec3 pb = p - b;
  vec3 ac = a - c; vec3 pc = p - c;
  vec3 nor = cross( ba, ac );

  return sqrt(
    (sign(dot(cross(ba,nor),pa)) +
     sign(dot(cross(cb,nor),pb)) +
     sign(dot(cross(ac,nor),pc))<2.0)
     ?
     min( min(
     dot2(ba*clamp(dot(ba,pa)/dot2(ba),0.0,1.0)-pa),
     dot2(cb*clamp(dot(cb,pb)/dot2(cb),0.0,1.0)-pb) ),
     dot2(ac*clamp(dot(ac,pc)/dot2(ac),0.0,1.0)-pc) )
     :
     dot(nor,pa)*dot(nor,pa)/dot2(nor) );
}

float smin( float a, float b, float k )
{
    float h = clamp( 0.5+0.5*(b-a)/k, 0.0, 1.0 );
    return mix( b, a, h ) - k*h*(1.0-h);
}

float opUnion( float d1, float d2 ) { return min(d1,d2); }

float opSmoothUnion( float d1, float d2, float k ) {
    float h = clamp( 0.5 + 0.5*(d2-d1)/k, 0.0, 1.0 );
    return mix( d2, d1, h ) - k*h*(1.0-h); }

float opSubtraction( float d1, float d2 ) { return max(-d1,d2); }

float opSmoothSubtraction( float d1, float d2, float k ) {
    float h = clamp( 0.5 - 0.5*(d2+d1)/k, 0.0, 1.0 );
    return mix( d2, -d1, h ) + k*h*(1.0-h); }

float opIntersection( float d1, float d2 ) { return max(d1,d2); }


vec3 rotateX(vec3 p, float theta) {
    float c = cos(theta);
    float s = sin(theta);
    return mat3(
        vec3(1, 0, 0),
        vec3(0, c, -s),
        vec3(0, s, c)
    ) * p;
}

vec3 rotateZ(vec3 p, float theta) {
    float c = cos(theta);
    float s = sin(theta);
    return mat3(
        vec3(c, -s, 0),
        vec3(s, c, 0),
        vec3(0, 0, 1.)
    ) * p;
}
    
vec3 rotateY(vec3 p, float theta) {
    float c = cos(theta);
    float s = sin(theta);
    return mat3(
        vec3(c, 0, s),
        vec3(0, 1, 0),
        vec3(-s, 0, c)
    ) * p;
}

float bias(float b, float t) {
    return pow(t,log(b)/log(0.5f));
}

float gain(float g, float t) {
    if (t < 0.5f) 
        return bias(1.0-g, 2.0*t) / 2.0;
     else 
        return 1.0 - bias(1.0-g, 2.0-2.0*t) / 2.0;
}

float ease_in_quadratic(float t){
    return t*t;
}

float ease_in_out_quadratic(float t) {
    if (t<0.5)
        return ease_in_quadratic(t*2.0)/2.0;
    else  
        return 1.0 - ease_in_quadratic((1.0-t)*2.0);
}

float rand(vec2 n) { 
	return fract(sin(dot(n, vec2(12.9898, 4.1414))) * 43758.5453);
}

float noise(vec2 p){
	vec2 ip = floor(p);
	vec2 u = fract(p);
	u = u*u*(3.0-2.0*u);
	
	float res = mix(
		mix(rand(ip),rand(ip+vec2(1.0,0.0)),u.x),
		mix(rand(ip+vec2(0.0,1.0)),rand(ip+vec2(1.0,1.0)),u.x),u.y);
	return res*res;
}

#define NUM_OCTAVES 5

float fbm(vec2 x) {
	float v = 0.0;
	float a = 0.5;
	vec2 shift = vec2(100);
	// Rotate to reduce axial bias
    mat2 rot = mat2(cos(0.5), sin(0.5), -sin(0.5), cos(0.50));
	for (int i = 0; i < NUM_OCTAVES; ++i) {
		v += a * noise(x);
		x = rot * x * 2.0 + shift;
		a *= 0.5;
	}
	return v;
}

#define ATTENUATION 0
float subsurface(vec3 lightDir, vec3 normal, vec3 viewVec, float thinness) {
    vec3 scatteredLightDir = lightDir + normal * DISTORTION;
    float lightReachingEye = pow(clamp(dot(viewVec, -scatteredLightDir), 0.0, 1.0), GLOW) * BSSRDF_SCALE;
    float attenuation = 1.0;
    #if ATTENUATION
    attenuation = max(0.0, dot(normal, lightDir) + dot(viewVec, -lightDir));
    #endif
	float totalLight = attenuation * (lightReachingEye + AMBIENT) * thinness;
    return totalLight;
}


#define P1 vec3(0.f,8.f,-100.f)
#define P2 vec3(-9.f,19.f,-21.f)
#define P3 vec3(9.f,19.f,-21.f)
#define PLANK1 sdBox(queryPos + P1,vec3(10.f,1.f,80.f))
#define PLANK2 sdBox(queryPos + P2,vec3(1.f,10.f,1.f))
#define PLANK3 sdBox(queryPos + P3,vec3(1.f,10.f,1.f))

#define BC1 vec3(-8.f,0.f,-10.f + ctime)
#define BC2 vec3(2.f,-1.2f,-15.f + ctime)
#define RC1 vec3(-2.f,-5.f,-7.f + ctime)
#define RC2 vec3(2.f,2.f,-15.f + ctime)

// #define BT1 vec3(1.f,4.f,-0.6f)
#define BT1 BC1 + vec3(0.8f,0.f,1.4f)
#define BT2 BC2 + vec3(-0.8f,0.f,1.4f)
#define RT1 RC1 + vec3(0.f,-0.8f,1.4f)
#define RT2 RC2 + vec3(-0.8f,0.f,1.4f)

#define BS vec3(-0.f,3.f,-1.f) + rotateY(vec3(1.f,1.f,1.f), 90.0*TO_RADIAN*ease_in_quadratic(cos(time))) 
#define RS vec3(-6.f,5.f,-1.f) + rotateZ(vec3(1.f,1.f,1.f), 90.0*TO_RADIAN*sin(time)) 

// #define BS vec3(-0.f,3.f,-1.f) + rotateY(vec3(1.f,1.f,1.f), (90.0+stime)*TO_RADIAN) 
// #define RS vec3(-6.f,5.f,-1.f) + rotateZ(vec3(1.f,1.f,1.f), (90.0+stime)*TO_RADIAN) 

// #define BS vec3(-0.f,3.f,-1.f)
// #define RS vec3(-6.f,5.f,-1.f)


#define BS1 vec3(9.8f,6.5f,-20.f)
#define RS1 vec3(-9.8f,6.5f,-20.f)

#define BCUBE1 sdRoundBox(queryPos + BC1,vec3(1.f,1.f,1.f),0.5)
#define BCUBE2 sdRoundBox(queryPos + BC2,vec3(1.f,1.f,1.f),0.5)
#define RCUBE1 sdRoundBox(queryPos + RC1,vec3(1.f,1.f,1.f),0.5)
#define RCUBE2 sdRoundBox(queryPos + RC2,vec3(1.f,1.f,1.f),0.5)
#define TRI11 sdTriPrism(queryPos + BT1, vec2(1,0.2))
#define TRI1 sdTriPrism(rotateZ(queryPos + BT1, 270.*TO_RADIAN), vec2(0.8,0.2))
#define TRI2 sdTriPrism(rotateZ(queryPos + BT2, 90.*TO_RADIAN), vec2(0.8,0.2))
#define TRI3 sdTriPrism(rotateZ(queryPos + RT1, 180.*TO_RADIAN), vec2(0.8,0.2))
#define TRI4 sdTriPrism(rotateZ(queryPos + RT2, 90.*TO_RADIAN), vec2(0.8,0.2))
#define BCUBE11 opSmoothUnion(BCUBE1, TRI1,0.5)
#define BCUBE22 opSmoothUnion(BCUBE2, TRI2,0.5)
#define RCUBE11 opSmoothUnion(RCUBE1, TRI3,0.5)
#define RCUBE22 opSmoothUnion(RCUBE2, TRI4,0.5)

#define DP rotateX(rotateZ(queryPos + vec3(0.f,0.f,-80.f), 90.*TO_RADIAN), 90.*TO_RADIAN)
// #define DP queryPos + vec3(0.f,0.f,-80.f)
#define DISK1 sdCappedCylinder(DP,30.f,0.4f)
#define DISK2 sdSphere(DP,12.f)
#define DISK opSubtraction(DISK2, DISK1)

#define BSABER sdCapsule(queryPos + BS, vec3(0.2f,0.2f,1.f),rotateZ(vec3(5.f,10.f,1.f), 90.f*TO_RADIAN*sin(time)),0.2)
#define RSABER sdCapsule(queryPos + RS, vec3(1.f,1.f,1.f),rotateY(vec3(-10.f,5.f,2.f), 90.f*TO_RADIAN*sin(time)),0.2)
// #define BSABER_B sdCapsule(queryPos + BS, vec3(0.2f,0.2f,1.f),vec3(5.f,10.f,1.f),0.2)
// #define RSABER_B sdCapsule(queryPos + RS, vec3(1.f,1.f,1.f),vec3(-10.f,5.f,2.f),0.2)
// #define BSABER opUnion(BSABER_U,BSABER_B)
// #define RSABER opUnion(RSABER_U,RSABER_B)

#define BSIDE1 sdCapsule(queryPos + BS1, vec3(0.2f,0.2f,60.f),vec3(0.f,0.f,0.f),0.2)
#define BSIDE2 sdCapsule(queryPos + RS1, vec3(0.2f,0.2f,60.f),vec3(0.f,0.f,0.f),0.2)


float sceneSDF(vec3 queryPos) 
{
    float ctime = -80.f + float(int(TIME*5.f)%150);
    // float stime = 30.f * sin(u_Time*0.2f);
    float stime = 0.f;
    float time = TIME/30.f;
    float t, t2;
    t = PLANK1;
    t2 = PLANK2;
    t = min(t,t2);
    t2 = PLANK3;
    t = min(t,t2);
    t2 = BCUBE11;
    t = min(t,t2);
    t2 = BCUBE22;
    t = min(t,t2);
    t2 = RCUBE11;
    t = min(t,t2);
    t2 = RCUBE22;
    t = min(t,t2);
    t2 = BSABER;
    t = min(t,t2);
    t2 = RSABER;
    t = min(t,t2);
    t2 = BSIDE1;
    t = min(t,t2);
    t2 = BSIDE2;
    t = min(t,t2);
    // t2 = DISK;
    // t = min(t,t2);
    return t;
}

float sceneSDF(vec3 queryPos, out int id) 
{
    float ctime = -80.f + float(int(TIME)%150);
    // float stime = 30.f * sin(u_Time*0.2f);
    float stime = 0.f;
    float time = TIME/30.f;
    float t, t2;
    t = PLANK1;
    id = BLUE_PLANK;
    // 1. Evaluate all SDFs as material groups
    float white_t = min(min(TRI1,TRI4), min(TRI2, TRI3));
    float darkBlue_t = min(min(PLANK2, PLANK1), min(PLANK3,DISK));
    float bluecube_t = min(BCUBE1, BCUBE2);
    float redcube_t = min(RCUBE1, RCUBE2);
    float side_t = min(BSIDE1, BSIDE2);
    if(white_t < t) {
        t = white_t;
        id = WHITE_GLOW;
    }
    if(darkBlue_t < t) {
        t = darkBlue_t;
        id = BLUE_PLANK;
    }
    if(bluecube_t < t) {
        t = bluecube_t;
        id = BLUE_CUBE;
    }
    if(redcube_t < t){
        t = redcube_t;
        id = RED_CUBE;
    }
    // if((t2 = BSABER_B) < t){
    //     t = t2;
    //     id = BLUE_PLANK;
    // } 
    // if((t2 = RSABER_B) < t){
    //     t = t2;
    //     id = BLUE_PLANK;
    // } 
    if((t2 = BSABER) < t){
        t = t2;
        id = BLUE_SABER;
    } 
    if((t2 = RSABER) < t){
        t = t2;
        id = RED_SABER;
    } 
    if((t2 = side_t) < t){
        t = t2;
        id = BLUE_SIDE;
    }      
    if((t2 = DISK2) < t){
        t = t2;
        id = INSIDE;
    }   
    return t;
}

// compute normal of arbitrary scene by using the gradient    
vec3 computeNormal(vec3 pos)
{
    vec3 epsilon = vec3(0.0, 0.001, 0.0);
    return normalize( vec3( sceneSDF(pos + epsilon.yxx) - sceneSDF(pos - epsilon.yxx),
                            sceneSDF(pos + epsilon.xyx) - sceneSDF(pos - epsilon.xyx),
                            sceneSDF(pos + epsilon.xxy) - sceneSDF(pos - epsilon.xxy)));
}

//transform from uv space to ray space
Ray getRay(vec2 uv)
{
    Ray r;
    
    vec3 ref = u_Ref;
    vec3 eye = u_Eye;
    
    vec3 F = normalize(ref - eye);
    vec3 U = u_Up;
    vec3 R = cross(F, U);
    float len = length(vec3(ref - eye));
    float alpha = FOV/2.f;
    vec3 V = U * len * tan(alpha);
    float aspect = u_Dimensions.x / u_Dimensions.y;
    vec3 H = R*len*aspect*tan(alpha);
    float sx = fs_Pos.x ;
    float sy = fs_Pos.y ;
    vec3 p = ref + sx * H + sy * V;

    vec3 dir = normalize(p - eye);

    r.origin = eye;
    r.direction = dir;
   
    return r;
}

float shadow(vec3 dir, vec3 origin, float min_t, float k, vec3 lightPos) {
    float res = 1.0;
    float t = min_t;
    for(int i = 0; i < MAX_RAY_STEPS; ++i) {
        float m = sceneSDF(origin + t * dir);
        if(m < 0.0001) {
            return 0.;
        }
        res = min(res, k * m / t);
        t += m;
    }
    return res;
}

Intersection getRaymarchedIntersection(vec2 uv)
{
    Intersection intersection;
    intersection.distance_t = -1.0;
    int material_id = -1;
    Ray r = getRay(uv);
    float t = EPSILON; 
    for(int step; step < MAX_RAY_STEPS; ++step){
      vec3 queryPoint = r.origin + r.direction * t;
      
      float currDistance = sceneSDF(queryPoint, material_id);
      if (currDistance < EPSILON) {
        //if we hit something
        intersection.distance_t = t;
        intersection.normal = computeNormal(queryPoint);
        intersection.material_id = material_id;
        intersection.position = queryPoint;
        return intersection;
      }
      t += currDistance;
      // Stop marching after we get too far away from camera
      if(t > MAX_DIST) {
          return intersection;
      }
    }

    return intersection;
}

vec3 rgb(int r, int g, int b) {
  return vec3(float(r) / 255.f, float(g) / 255.f, float(b) / 255.f);
}

float depthOfField(Intersection isect) {
        //compute depth of field blur attribute for each pixel
    float focalLength = 20.;// * cos(iTime)* 3.14159;
    float focalRange = 7.;//
    float distFromCamera = abs(dot(normalize(u_Ref - u_Eye), isect.position - u_Eye));
    float dofBlurAmount = min(1.0, abs(distFromCamera - focalLength)/focalRange);
    return dofBlurAmount;
}



vec4 getSceneColor(vec2 uv)
{
    Intersection i = getRaymarchedIntersection(uv);
    int blinn = 0;
    vec3 diffuseColor = vec3(1.f);

        //lambert shading
    vec3 lightPos = vec3(0.f, 10.f, -10.f);
    vec3 lightPos2 = vec3(0.f, 10.f, -10.f);
    vec3 lightPos3 = vec3(0.f, 10.f, -10.f);
    vec3 lightDir = lightPos - i.position;

    float diffuseTerm = dot(normalize(i.normal), normalize(lightDir));
    diffuseTerm = clamp(diffuseTerm, 0.f, 1.f);
    float ambientTerm = 0.5;
    float lightIntensity = (diffuseTerm + ambientTerm);

    float dist = 1.0/length(uv);
    dist *= 0.1;
    dist = pow(dist,0.9);
    vec3 mist = dist * vec3(0.25, 0.5, 0.8);
    mist = 1.0 - exp( -mist );
    switch(i.material_id) {
        case BLUE_PLANK: 
        diffuseColor = rgb(5,23,44);
        blinn = 1;
        break;

        case BLUE_CUBE:
        diffuseColor = rgb(2,70,122);
        break;

        case RED_CUBE:
        diffuseColor = rgb(102,9,9);
        break;

        case WHITE_TRIANGLE:
        diffuseColor = rgb(255,255,255);
        break;

        case BLUE_SABER:
        diffuseColor = rgb(6,81,133);
        float n1 = n21(fs_Pos4.xyz);
        diffuseColor = n1 > 0.9? diffuseColor + n1 : diffuseColor;
        break;

        case BLUE_SIDE:
        vec3 c1 = rgb(138,210,227);
        vec3 c2 = rgb(59,127,171);
        diffuseColor = c1;
        diffuseColor += smoothstep(c1, c2, vec3(abs(sin(TIME/30.f))));
        break;

        case RED_SABER:
        diffuseColor = rgb(174,36,44);
        float n2 = n21(fs_Pos4.xyz);
        diffuseColor = n2 > 0.9? diffuseColor + n2 : diffuseColor;
        break;

        case WHITE_GLOW:
        float d = length(uv-vec2(0.6,0.5));
        vec3 glow = vec3(0.98,0.97,0.95)*(1.0-0.1*smoothstep(0.2,0.5,1.f));
        vec3 col2 = vec3(0.8);
        col2 += 0.8*glow*exp(-4.0*d)*vec3(1.1,1.0,0.8);
        col2 += 0.2*glow*exp(-2.0*d);
        glow *= 0.85+0.15*smoothstep(0.25,0.7,1.0);
        col2 = mix( col2, glow, 1.0-smoothstep(0.2,0.22,d) );
        return vec4(col2,1);

        case INSIDE:
        mist += perlinNoise3D(vec3(fs_Pos4.xyz));
        return vec4(mist,1);

        default:
        return vec4(mist,1);
     }

    //blinn shading
    if(blinn == 1){
        vec3 H = (lightDir + u_CameraPos) / 2.f;
        H = normalize(H);
        float exp = 80.f;
        // Material base color (before shading)
        diffuseColor += max(pow(dot(normalize(H.xyz), normalize(i.normal)), exp), 0.0);
    }
    float K = 100.f;
    float sh = shadow(lightDir, i.position, 0.1, K, lightPos);
    vec3 col = diffuseColor.rgb * lightIntensity * sh;
    //col = sh > 0.5 ? vec3(1.) : vec3(1., 0., 1.);

    // col = i.normal * 0.5 + vec3(0.5);
    float dofBlurAmount = depthOfField(i);
    return vec4(col, dofBlurAmount);
}


void main() {
    vec2 uv = fs_Pos;
    vec2 p = uv;
    // camera
    float time = mod( TIME, 60.0 );
    // p += vec2(1.0,3.0)*0.001*2.0*cos( u_Time*5.0 + vec2(0.0,1.5) );    
    // p += vec2(1.0,3.0)*0.001*1.0*cos( time*9.0 + vec2(1.0,4.5) );    
    // float an = 0.3*sin( 0.1*time );
    // float co = cos(an);
    // float si = sin(an);
    // p = mat2( co, -si, si, co )*p*0.85;
    // uv = vec2(1.0,3.0)*0.001*1.0;
    out_Col = getSceneColor(uv);
}