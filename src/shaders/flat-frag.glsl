#version 300 es
precision highp float;

uniform vec3 u_Eye, u_Ref, u_Up;
uniform vec2 u_Dimensions;
uniform float u_Time;

in vec2 fs_Pos;
out vec4 out_Col;
const int MAX_RAY_STEPS = 128;
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
    int object;
    int material_id;
};

struct DirectionalLight
{
    vec3 dir;
    vec3 color;
};

//#define brideRed vec3(191.f / 255.f ,50.f / 255.f ,32.f / 255.f)
#define brideRed vec3(141.f / 255.f ,50.f / 255.f ,52.f / 255.f)
// #define waterBlue vec3(69.f / 255.f ,88.f / 255.f ,102.f / 255.f)
#define waterBlue vec3(0.15f, 0.22f, .58)
#define cityCol vec3(.566, .341, .678)
#define rockCol vec3(.40, .24, .32)
#define mainLightColor vec3(.8, .8, .5)
// Want sunlight to be brighter than 100% to emulate
// High Dynamic Range
#define SUN_KEY_LIGHT vec3(1., 1.0, 0.4) * 1.3
// Fill light is sky color, fills in shadows to not be black
#define SKY_FILL_LIGHT vec3(0.4, 0.4, 0.4) * 0.4
// Faking global illumination by having sunlight
// bounce horizontally only, at a lower intensity
#define SUN_AMBIENT_LIGHT vec3(0.6, 1.0, 0.5) * 0.2
#define OUTSIDE_BACKGROUND vec3(0.7, 0.2, 0.7) * 4.3
#define sunColor vec3(.85, .8, .6)
#define skyColor vec3(.556, .698, .753)
#define roadGrey vec3(.1, .1, .2)
#define RADIANS (3.14158 / 180.0)
#define SHADOW_HARDNESS 10.0
#define RAY_LENGTH 52.f
#define box1 sdBox(pos, vec3(-1.f, 0.f, 5.f), rotateY(30.f * RADIANS), vec3(2.5f, 4.f, 17.f))
#define box2 sdBox(pos, vec3(0.f), identity(), vec3(1.f))
#define groundPlane sdHeightField(pos, 2.f, vec3(0.f, -8.0, 1.0), rotateX(-7.0 * (3.14158 / 180.0)))
#define islandPlane sdBox(vec3(pos.x, pos.y + WorleyNoise(pos / 10.5), pos.z), vec3(-10.f, -.50f, -45.f),  rotateZ(-1.f * RADIANS) * rotateX(-15.f *  RADIANS) * rotateY(10.f * RADIANS),  vec3(45.f, .008f, 10.0f))
#define road sdRoad(pos, vec3(-1.f, 0.f, 3.f), rotateY(30.f * RADIANS))
#define triangleBridge sdBridgeTri(pos, vec3(1.05f, -1.05f, 0.f), rotateY(30.0 * RADIANS))
#define frontRocks rock(pos, vec3(0.f, 0.25f, 1.f), identity())
#define rotateWhole sdBridge(pos, vec3(-1.f, 0.f, 3.f), rotateY(30.f * RADIANS))
#define frontBigSquare sdRoundBox(pos, vec3(1.5f, .0f, -2.f), rotateY(25.0 * (3.14158 / 180.0)), vec3(.33f, 2.3f, .0001f), .1)
#define testSphere sdfSphere(pos, vec3(0.0, 0.0, 0.0), 1.0)


//noises
float random1( vec3 p ) {
  return fract(sin(dot(p, vec3(127.1, 311.7, 191.999))) * 43758.5453);
}

vec3 random3( vec3 p ) {
    return fract(sin(vec3(dot(p,vec3(127.1, 311.7, 191.999)),
                          dot(p,vec3(269.5, 183.3, 765.54)),
                          dot(p, vec3(420.69, 631.2,109.21))))
                 *43758.5453);
}

float mySmootherStep(float a, float b, float t) {
  t = t*t*t*(t*(t*6.0 - 15.0) + 10.0);
  return mix(a, b, t);
}

float interpNoise3D1(vec3 p) {
  vec3 pFract = fract(p);
  float llb = random1(floor(p));
  float lrb = random1(floor(p) + vec3(1.0,0.0,0.0));
  float ulb = random1(floor(p) + vec3(0.0,1.0,0.0));
  float urb = random1(floor(p) + vec3(1.0,1.0,0.0));

  float llf = random1(floor(p) + vec3(0.0,0.0,1.0));
  float lrf = random1(floor(p) + vec3(1.0,0.0,1.0));
  float ulf = random1(floor(p) + vec3(0.0,1.0,1.0));
  float urf = random1(floor(p) + vec3(1.0,1.0,1.0));

  float lerpXLB = mySmootherStep(llb, lrb, pFract.x);
  float lerpXHB = mySmootherStep(ulb, urb, pFract.x);
  float lerpXLF = mySmootherStep(llf, lrf, pFract.x);
  float lerpXHF = mySmootherStep(ulf, urf, pFract.x);

  float lerpYB = mySmootherStep(lerpXLB, lerpXHB, pFract.y);
  float lerpYF = mySmootherStep(lerpXLF, lerpXHF, pFract.y);

  return mySmootherStep(lerpYB, lerpYF, pFract.z);
}
float fbm(vec3 newP, float octaves) {
  float amp = 0.5;
  float freq = 6.0;
  float sum = 0.0;
  float maxSum = 0.0;
  for(float i = 0.0; i < 10.0; ++i) {
    if(i == octaves)
    break;
    maxSum += amp;
    sum += interpNoise3D1(newP * freq) * amp;
    amp *= 0.5;
    freq *= 2.0;
  }
  return (sum / maxSum);
} 


//worley noise
float WorleyNoise(vec3 pos)
{
    pos *= 3.0;
   vec3 uvInt = floor(pos);
    vec3 uvFract = fract(pos);
    float minDist = 1.0;
    vec3 closeOne;
    for(int z = -1; z <= 1; z++)
    {
    for(int y = -1; y <= 1; ++y)
    {
        for(int x = -1; x <= 1; ++x)
        {
           vec3 neighbor = vec3(float(x), float(y), float(z));
          vec3 point = random3(uvInt + neighbor);
            vec3 diff = neighbor + point - uvFract;
            float dist = length(diff);
            //finding the point that is the closest random point
            if(dist < minDist)
            {
                //getting the point into the correct uv coordinate space
                minDist = dist;
            }

        
        }
    }
    }
    return minDist;
  
}

float surflet(vec3 p, vec3 gridPoint) {
    // Compute the distance between p and the grid point along each axis, and warp it with a
    // quintic function so we can smooth our cells
    vec3 t2 = abs(p - gridPoint);
    vec3 pow1 = vec3(pow(t2.x, 5.f), pow(t2.y, 5.f), pow(t2.z, 5.f));
    vec3 pow2 = vec3(pow(t2.x, 4.f), pow(t2.y, 4.f), pow(t2.z, 4.f)); 
    vec3 pow3 = vec3(pow(t2.x, 3.f), pow(t2.y, 3.f), pow(t2.z, 3.f));
    vec3 t = vec3(1.f) - 6.f * pow1
        + 15.f * pow2 
        - 10.f * pow3;
    // Get the random vector for the grid point (assume we wrote a function random2
    // that returns a vec2 in the range [0, 1])
    vec3 gradient = random3(gridPoint) * 2.f - vec3(1,1,1);
    // Get the vector from the grid point to P
    vec3 diff = p - gridPoint;
    
    float height = dot(diff, gradient);
    // Scale our height field (i.e. reduce it) by our polynomial falloff function
    return height * t.x * t.y * t.z;
}


//PERLIN NOISE

float perlinNoise3D(vec3 p) {
	float surfletSum = 0.f;
	// Iterate over the four integer corners surrounding uv
	for(int dx = 0; dx <= 1; ++dx) {
		for(int dy = 0; dy <= 1; ++dy) {
            for (int dz = 0; dz <= 1; ++dz) {
			surfletSum += surflet(p, floor(p) + vec3(dx, dy, dz));
            }
		}
	}
	return surfletSum;
}
//https://inspirnathan.com/posts/54-shadertoy-tutorial-part-8/
// Rotation matrix around the X axis.
mat3 rotateX(float theta) {
    float c = cos(theta);
    float s = sin(theta);
    return mat3(
        vec3(1, 0, 0),
        vec3(0, c, -s),
        vec3(0, s, c)
    );
}

// Rotation matrix around the Y axis.
mat3 rotateY(float theta) {
    float c = cos(theta);
    float s = sin(theta);
    return mat3(
        vec3(c, 0, s),
        vec3(0, 1, 0),
        vec3(-s, 0, c)
    );
}

// Rotation matrix around the Z axis.
mat3 rotateZ(float theta) {
    float c = cos(theta);
    float s = sin(theta);
    return mat3(
        vec3(c, -s, 0),
        vec3(s, c, 0),
        vec3(0, 0, 1)
    );
}

// Identity matrix.
mat3 identity() {
    return mat3(
        vec3(1, 0, 0),
        vec3(0, 1, 0),
        vec3(0, 0, 1)
    );
}


vec3 opCheapBend(in vec3 p, float k)
{
   k = .8;
    float c = cos(k*p.y);
    float s = sin(k*p.y);
    mat2  m = mat2(c,-s,s,c);
    vec3  q = vec3(m*p.xy,p.z);
    return q;
} 


vec3 opSymX( in vec3 p)
{
    p.z = abs(p.z);
    return p;
}


vec3 opRepLim(in vec3 p, in float c, in vec3 l)
{
    vec3 q = p-c*clamp(round(p/c),-l,l);
    return q;
}
float opSmoothUnion( float d1, float d2, float k ) {
    float h = clamp( 0.5 + 0.5*(d2-d1)/k, 0.0, 1.0 );
    return mix( d2, d1, h ) - k*h*(1.0-h); }

float opSmoothSubtraction( float d1, float d2, float k ) {
    float h = clamp( 0.5 - 0.5*(d2+d1)/k, 0.0, 1.0 );
    return mix( d2, -d1, h ) + k*h*(1.0-h); }

float opSmoothIntersection( float d1, float d2, float k ) {
    float h = clamp( 0.5 - 0.5*(d2-d1)/k, 0.0, 1.0 );
    return mix( d2, d1, h ) + k*h*(1.0-h); }

float smin( float a, float b, float k )
{
    float h = clamp( 0.5+0.5*(b-a)/k, 0.0, 1.0 );
    return mix( b, a, h ) - k*h*(1.0-h);
}

float easeInQuadratic(float f)
{
  return f * f;
}

float sdCappedTorus(in vec3 p, in vec2 sc, in float ra, in float rb)
{
  p.x = abs(p.x);
  float k = (sc.y*p.x>sc.x*p.y) ? dot(p.xy,sc) : length(p.xy);
  return sqrt( dot(p,p) + ra*ra - 2.0*ra*k ) - rb;
}

float sdfSphere(vec3 query_position, vec3 position, float radius)
{
    return length(query_position - position) - radius;
}
//capsule
float sdCapsule( vec3 p, vec3 a, vec3 b, float r )
{
  vec3 pa = p - a, ba = b - a;
  float h = clamp( dot(pa,ba)/dot(ba,ba), 0.0, 1.0 );
  return length( pa - ba*h ) - r;
}

float sdPlane( vec3 p, vec3 n, float h, vec3 offset, mat3 transform)
{
  // n must be normalized
 // if(p.z < -1.f)
 // {
     float hPlus = fbm(p, 3.f);
     p.y += hPlus + 5.f;
     //h *= hPlus;
     p = (p - offset) *transform;
     return dot(p,n) + h;
 // }
 // else
 // {
   // return 10.f;
 // }
 
}
//cylinder
float sdCappedCylinder( vec3 p, float h, float r )
{
  vec2 d = abs(vec2(length(p.xz),p.y)) - vec2(h,r);
  return min(max(d.x,d.y),0.0) + length(max(d,0.0));
}

float sdVerticalCapsule( vec3 p, float h, float r )
{
  p.y -= clamp( p.y, 0.0, h );
  return length( p ) - r;
}
float sdBox( vec3 p, vec3 offset, mat3 transform, vec3 b )
{
  p = (p - offset) *transform;
  vec3 q = abs(p) - b;
  return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0);
}

float sdRoundBox( vec3 p, vec3 offset, mat3 transform, vec3 b, float r )
{
  p = (p - offset) *transform;
  vec3 q = abs(p) - b;
  return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0) - r;
}

float sdCone( vec3 p, vec2 c, float h, vec3 offset, mat3 transform)
{
  p = (p - offset) * transform;
  float q = length(p.xz);
  return max(dot(c.xy,vec2(q,p.y)),-h-p.y);
}

float sdVerticalCables(vec3 p, vec3 offset, mat3 transform)
{
    p = (p - offset) *transform * (1.f /  vec3(1.f, 1.f, 1.f));
    vec3 newP = opRepLim(p, .9f, vec3(12.f, 0.f, 0.f));
    float pole = sdVerticalCapsule(newP, 3.f, .01f);
    return pole;
}
float extraCable(vec3 p)
{
  vec3 newP = (p - vec3(-3.95f, 9.5f, 7.5f)) * rotateY(120.f * RADIANS) * rotateZ(180.f * RADIANS) * (1.f /  vec3(1.f, 1.2f, 1.f));
  float an = 42.f * RADIANS;
  vec2 c = vec2(sin(an),cos(an));
  float cable = sdCappedTorus(newP, c, 8.f, .01);
  vec3  newP2 = (p - vec3(-3.4f, 9.5f, 7.9f)) * rotateY(120.f * RADIANS) * rotateZ(180.f * RADIANS) * (1.f /  vec3(1.f, 1.2f, 1.f));
  float cable2 = sdCappedTorus(newP2, c, 8.f, .01);
  
  //cable = min(cable, subtractSphere);
  return min(cable, cable2);
}
float sdCables(vec3 p, vec3 offset, mat3 transform)
{
    p = (p - offset) *transform * (1.f /  vec3(1.08f, 1.f, 1.f));
    float an = 42.f * RADIANS;
    vec2 c = vec2(sin(an),cos(an));

    vec3 newP = opSymX(p);
    float topCable = sdCappedTorus(p, c, 13.f,.03f);
    topCable = smin(topCable, sdVerticalCables(p, vec3(-1.f, 10.f, 0.f), identity()), .08);
    topCable = smin(topCable, sdVerticalCables(p, vec3(-1.f, 10.f, .5f), identity()), .08);
    vec3 newpP= p * (1.f / vec3(1.42f, 1.05f, 1.f));
    //float subtractSphere = sdfSphere(p, vec3(0.f, 6.6f, 0.f), 6.f);
    newP = newP - vec3(0.f, 3.0f, 0.f);
    float subtractSphere = sdCappedTorus(newP, c, 8.f, 2.);
    float subtractSphere2 = sdCappedTorus((newP - vec3(-14.5f, 1.4f, -1.f)), c, 6.f, 2.f);
    //float subtractSphere2 = sdfSphere(p, vec3(-7.8f, 10.1f, 0.5f), 1.6f);
    //float subtractSphere2 = sdfSphere((p + vec3(), vec3(0.f, 6.6f, 0.f), 6.f);
   // topCable = min(subtractSphere, topCable);
   // topCable = min(subtractSphere2, topCable);
    topCable = opSmoothSubtraction(subtractSphere, topCable, .25);
    topCable = opSmoothSubtraction(subtractSphere2, topCable, .25);
    topCable = min(topCable, sdCappedTorus((p - vec3(0.f, 0.f, .5f)), c, 13.f, .03f));
    topCable = min(topCable, sdCappedTorus((p - vec3(-17.5f, 0.f, 0.f)), c, 13.f, .02f));
    topCable = min(topCable, sdCappedTorus((p - vec3(-17.5f, 0.f, .5f)), c, 13.f, .02f));
    //subraction sphere
    
    //float topCable2 = opSmoothSubtraction(subtractSphere2, topCable, .25);
    //topCable = min(subtractSphere2, topCable);
    return topCable;   
}
float sdHeightField(vec3 pos, float planeHeight, vec3 offset, mat3 transform)
{
  float waveHeight = .5;
  float waveFrequency = .50f;
  pos = (pos - offset) * transform * ( 1.f / vec3(1.f, 1.f, 1.f));
  float w = perlinNoise3D(pos / 5.5);

  
  return mix(pos.y, pos.y + (w * .45), cos(u_Time * .01));

}
float rock(vec3 pos, vec3 offset, mat3 transform)
{
   pos = (pos - offset) *transform * (1.f /  vec3(1.0f, 1.f, 1.f));
   
   float w = fbm(pos.yzz * 2.f, 4.0) * .02;
   //pos += w;
   float rock = sdfSphere(pos,  vec3(-1.7f, -2.6f, 6.5f), 2.f);
   rock += w;
   return rock;
  // return smin(rock, curvePart, .25);
}
float sdBridgeTri(vec3 pos, vec3 offset, mat3 transform)
{
  pos = (pos - offset) * transform * ( 1.f / vec3(1.f, 1.f, 1.f));
  vec3 newPos = opRepLim(pos, .28, vec3(0.f, 0.f, 40.f)); 
  float tri1 = sdBox(newPos, vec3(0.f), rotateX(40.0 * RADIANS), vec3(.005f, .1f, .02f));
  float tri2 = sdBox(newPos, vec3(0.f, 0.f, 0.1f), rotateX(-40.0 * RADIANS), vec3(.005, .1, .02));
  float min1 = min(tri2, tri1);
  return min1;
  
}
float sdRoadSide(vec3 pos, vec3 offset, mat3 transform)
{
  pos = (pos - offset) * transform * ( 1.f / vec3(1.f, 1.f, 1.f));
  float bottom = sdBox(pos, vec3(0.25f, -1.15f, -8.f), identity(), vec3(.03f, .02f, 12.f));
  float bottom2 = sdBox(pos, vec3(0.31f, -.98f, -8.f), identity(), vec3(.03f, .02f, 11.f));
  float bottom3 = sdBox(pos, vec3(-0.31f, -.98f, -8.f), identity(), vec3(.03f, .02f, 11.f));
  float min1 = min(bottom, bottom2);
  min1 = min(min1, bottom3);
  return min1;
}
float sdRoad(vec3 pos, vec3 offset, mat3 transform)
{
  pos = (pos - offset) * transform * ( 1.f / vec3(1.f, 1.f, 1.f));
  float newRoad = sdBox(pos, vec3(0.f, -.99f, -9.f), identity(), vec3(.30, .02f, 11.0));
  return newRoad;
}
float sdCross(vec3 pos, vec3 offset, mat3 transform)
{
  pos = (pos - offset) * transform * ( 1.f / vec3(1.f, 1.f, 1.f));
  float segment1 = sdBox(pos, vec3(0.f, -1.4f, 0.f), rotateZ(55.0 * RADIANS), vec3(.03, .4, .03));
  float segment2 = sdBox(pos, vec3(0.f, -1.4f, 0.f), rotateZ(-55.0 * RADIANS), vec3(.03, .4, .03));
  float segment3 = sdBox(pos, vec3(0.f, -1.7f, 0.f), rotateZ(-90.0 * RADIANS), vec3(.03, .4, .03));
  float cross1 = min(segment1, segment2);
  float bottom = min(cross1, segment3);
  return bottom;
}
float sdBridgeEnd(vec3 pos, vec3 offset, mat3 transform)
{
  vec3 p = pos;
  pos = (pos - offset) * transform * ( 1.f / vec3(1.f, 1.f, 1.f));
  float bigBase = sdRoundBox(pos, vec3(0.f, -.15, 0.f), identity(), vec3(.33f, 2.5f, .0001f), .08);
  float topSquare = sdRoundBox(pos, vec3(0.f, 1.9f, 0.0), identity(), vec3(.15, .15, .01), .1);
  float top2Square = sdRoundBox(pos, vec3(0.f, 1.15f, 0.0), identity(), vec3(.15, .15, .01), .1);
  float middleSquare = sdRoundBox(pos, vec3(0.f, .3f, 0.0), identity(), vec3(.15, .21, .01), .1);
  float bottomSquare = sdRoundBox(pos, vec3(0.f, -1.55f, 0.0), identity(), vec3(.15, 1.1, .01), .1);
  float subtractTop2 = opSmoothSubtraction(middleSquare, bigBase, .25);
  float subtractTop1 = opSmoothSubtraction(topSquare, subtractTop2, .25);
  float subtractTop  = opSmoothSubtraction(top2Square, subtractTop1, .25);
  float subtractBottom = opSmoothSubtraction(bottomSquare, subtractTop, .25);
  float addCross = min(subtractBottom, sdCross(pos, vec3(0.f, 0.f, 0.f), identity()));
  float addCross2 = min(addCross, sdCross(pos, vec3(0.f, -.6f, 0.f), identity()));
  return addCross2;
  
}

float sdBridge(vec3 pos, vec3 offset, mat3 transform)
{
  vec3 p = pos;
  pos = (pos - offset) * transform * ( 1.f / vec3(1.f, 1.f, 1.f));
  vec3 newPos = opRepLim(pos, 19.f, vec3(0.f, 0.f, 1.f));
  float bridgeFront = sdBridgeEnd(newPos, vec3(0.f), identity());
  float bridge = min(bridgeFront, sdRoadSide(pos, vec3(0.f), identity()));
  bridge = min(bridge, sdCables(pos, vec3(0.3f, 12.f, -9.5f), rotateX(-180.f * RADIANS) * rotateY(90.f * RADIANS)));
  return bridge;
}


float sceneSDF(vec3 pos)
{
  float t = groundPlane;
  if(box1 < t)
  {
      t = min(t, rotateWhole);
  }
 
  if(pos.y < 0.5f)
  {
      t = min(t, islandPlane);
  }
 if(pos.x < 1.f && pos.y < 2.f)
  {
      
      t = min(t, frontRocks);
   }

  t = min(t, road);
  t = min(t, triangleBridge);
  return t;
}
void sceneSDF(vec3 pos, out float t, out int obj, vec3 lightPos) 
{
    t = groundPlane;
    float t2;
    obj = 0;
    if(box1 < t)
    {
         if((t2 = rotateWhole) < t)
        {
          t = t2;
          obj = 1;
        } 
    }
   
    if((t2 = triangleBridge) < t)
    {
      t = t2;
      obj = 1;
    }
    if(pos.x < 1.f && pos.y < 2.f)
    {
        if((t2 = frontRocks) < t)
        {
          t = t2;
          obj = 2;
        } 
    }
    if(pos.y < .5f)
   {
      if((t2 = islandPlane) < t)
      {
      t = t2;
      obj = 4;
      }
    }
    if((t2 = road) < t)
    {
      t = t2;
      obj = 3;
    }
    
}

float softShadow(vec3 dir, vec3 origin, float min_t, float k) {
    float res = 1.0;
    for(float t = min_t; t < 128.f;) {
        float m = sceneSDF(origin + t * dir);
        if(m < 0.001) {
           return 0.0;
         } 
        res = min(res, k * m / t);
        t += m;
    }
    return res;
}

Ray getRay(vec2 uv)
{
    Ray r;

    float sx = uv.x;
    float sy = uv.y;
    vec3 localForward = normalize(u_Ref - u_Eye);
    vec3 localRight = cross(localForward, vec3(0.f, 1.f, 0.f));
    vec3 localUp = cross(localRight, localForward);
    float len = length(u_Ref - u_Eye);
    float fov = 45.0;
    fov = fov * (3.14159265358972 / 180.f);
    float tant = tan(fov/2.f);
    float aspect_ratio = u_Dimensions.x / u_Dimensions.y;
    vec3 V = normalize(localUp) * len * tant;

    vec3 H =  normalize(localRight) * len * aspect_ratio * tant;


    vec3 p = u_Ref + sx * H + sy * V;
    vec3 d = normalize(p - u_Eye);
    r.origin = u_Eye;
    r.direction = d; 
  
   
    return r;
}


vec3 estimateNormal(vec3 p)
{
  vec2 d = vec2(0., .01);
  float x = sceneSDF(p + d.yxx) - sceneSDF(p - d.yxx);
  float y = sceneSDF(p + d.xyx) - sceneSDF(p - d.xyx);
  float z = sceneSDF(p + d.xxy) - sceneSDF(p - d.xxy);

  return normalize(vec3(x, y, z));
}
Intersection getRaymarchedIntersection(vec2 uv)
{
    Intersection intersection;    
    intersection.distance_t = -1.0;

    Ray r = getRay(uv);
    float distancet = 0.f;

    for(int step; step < MAX_RAY_STEPS; step++)
    {
      
      if(distancet > RAY_LENGTH)
      {
        return intersection;
      }
      vec3 point = r.origin + r.direction * distancet;
      if(isinf(point.x) || isinf(point.y) || isinf(point.z))
      {
        break;
      }
      float currDistance;
      int obj;
      vec3 lightPos = vec3(0.f);
      sceneSDF(point, currDistance, obj, lightPos);
      if(currDistance < 0.001)
      {
        //wohoo intersection
        intersection.distance_t = currDistance;
        intersection.normal = estimateNormal(point);
        intersection.position = point;
        intersection.material_id = obj;
        return intersection;
      
      }
      distancet += currDistance;
    }
    return intersection;
}

vec4 getSceneColor(vec2 uv, vec3 lightPos)
{
      DirectionalLight lights[3];
    Intersection intersection = getRaymarchedIntersection(uv);
    vec3 albedo = vec3(0.f);
    vec3 diffuseCol = vec3(0.f);
    if (intersection.distance_t > 0.0)
    { 
          lights[0] = DirectionalLight(lightPos, SUN_KEY_LIGHT);
          lights[1] = DirectionalLight(vec3(-6., 2., -1.f), SKY_FILL_LIGHT);
          lights[2] = DirectionalLight(vec3(0.f, 1.f, -5.f), SUN_AMBIENT_LIGHT);
         if(intersection.material_id == 0)
         {
            float w = WorleyNoise(intersection.position.yyz / 10.f);
            albedo = (waterBlue) + sin(u_Time * .1) * w * .05;
            vec3 av = lightPos +  u_Eye;
            vec3 avg = av / 2.f;
            float specularIntensity = max(pow(dot(normalize(avg) , normalize(intersection.normal)), 8.f), 0.f);
            albedo += specularIntensity;
          
         } 
         else if(intersection.material_id == 1)
         {
            albedo = vec3(brideRed);
           
         }
         else if(intersection.material_id == 2)
         {
            albedo = rockCol + fbm(intersection.position.yzz * 2.f, 4.0) * .2;
        

         } 
          else if(intersection.material_id == 3)
         {
            albedo = roadGrey;

         } 
         else if(intersection.material_id == 4)
         {
            albedo = cityCol + fbm(intersection.position / .3, 3.f) * .3;

         } 
          vec3 color = albedo *
                 lights[0].color *
                 (clamp(dot(intersection.normal, lightPos), 0.0, 1.0) + 0.20) * 
                 softShadow(lights[0].dir, intersection.position, 0.1, 10.f);
    for(int i = 1; i < 3; ++i) {
        color += albedo *
                 lights[i].color *
                 (clamp(dot(intersection.normal, lights[i].dir), 0.0, 1.0) + 0.20) * 
                 softShadow(lights[i].dir, intersection.position, 0.1, 10.f);
    }  
        return vec4(color, distance(intersection.position, u_Eye));
         //return intersection.normal;
    }
    else
    {
      vec3 newsunColor = mix(vec3(.6, .2, .2), sunColor, smoothstep(0.f, .1, uv.y + .4));
      return vec4(mix(newsunColor, vec3(skyColor), smoothstep(0.f, .4f, uv.y) + .5), 0.f);
    }
    
}


void main() {
vec2 uv = fs_Pos;

  Ray r = getRay(fs_Pos);

  //out_Col = vec4(0.5 * (r.direction + vec3(1.0, 1.0, 1.0)), 1.0);
  vec3 lightPos = vec3(5.0, 1.0, -1.0);
  vec3 indirectLight = vec3(-5.0, 1.0, -1.f);
  vec4 sceneColDist = getSceneColor(uv, lightPos);
  float dist = sceneColDist[3];
  float fogT = smoothstep(30.0, 60.0, dist);
  vec3 col = vec3(getSceneColor(uv, lightPos));
  vec3 newsunColor = mix(vec3(.6, .2, .2), sunColor, smoothstep(0.f, .1, uv.y + .4));
  newsunColor = mix(newsunColor, vec3(skyColor), smoothstep(0.f, .4f, uv.y) + .5);
  col = mix(col, newsunColor, fogT);
  col = pow(col, vec3(1.1, 1.2, 1.1));
  out_Col = vec4(col, 1.f);
  //out_Col = vec4(0.5 * (fs_Pos + vec2(1.0)), 0.5 * (sin(u_Time * 3.14159 * 0.01) + 1.0), 1.0);
}
