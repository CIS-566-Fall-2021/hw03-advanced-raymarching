#version 300 es
precision highp float;

uniform vec3 u_Eye, u_Ref, u_Up;
uniform vec2 u_Dimensions;
uniform float u_Time;

in vec2 fs_Pos;
out vec4 out_Col;


/// ============================ CONTROLS ================================== ///

/* -------------- Scene Globals -------------- */
const int MAX_RAY_STEPS = 250;
const int MAX_RAY_LENGTH = 75;
const float FOV = 45.0;
const float EPSILON = 1e-2;
const float MAX_FLT = 1e10;

/* -------------- Material IDs ---------------- */
#define GROUND_MAT_ID 0
#define TREE_MAT_ID 1
#define PATH_MAT_ID 2
#define TEMPLE_MAT_ID 3
#define MUSHROOM_MAT_ID 4
#define MAGIC_MAT_ID 5
#define CANDLE_MAT_ID 6
#define CANDLE_FLAME_ID 7

/* -------------- Light Controls -------------- */
const vec3 GUIDE_LIGHT_POS = vec3(-1.6, 0.0, 6.9); // point light to represent player
const vec3 GUIDE_LIGHT_COLOR = vec3(255.0, 200.0, 100.0) / 255.0;

const vec3 SKY_LIGHT_POS = vec3(-5.1, 3.0, -4.0);
const vec3 SKY_LIGHT_COLOR = vec3(1.0);
const float SKY_LIGHT_RADIUS = 7.5;

/* -------------- Atmosphere Controls --------- */
const vec4 SKY_COLOR = vec4(173.0, 229.0, 240.0, 255.0) / 255.0;
const vec4 FOG_COLOR = vec4(133.0, 190.0, 220.0, 255.0) / 255.0;
const float RAIN_WIDTH = 0.007;
const float MAX_RAIN_HEIGHT = 1.0;
const float MIN_RAIN_HEIGHT = 0.5;

/* -------------- Terrain Controls ------------ */
const float GROUND_HEIGHT = -1.0;
const vec3 GROUND_COLOR = vec3(0.5, 0.9, 0.6);
const vec3 RAISED_GROUND_POS = vec3(-4.0, 1.0, 10.0);
const vec3 RAISED_GROUND_SCALE = vec3(2.2, 0.01, 2.2);

const float PATH_OFFSET_X = -0.9;                          // place path in center of screen
const float PATH_OFFSET_Z = -1.5;                         // where (along z) to start path wave
const float PATH_COLOR_WIDTH = 0.4;                       // how wide the colored portion of the path is
const float PATH_PAVE_WIDTH = PATH_COLOR_WIDTH + 0.3;     // distance over which to interpolate b/w hills and flat path
const float PATH_WAVE_FREQ = 2.5;                         // frequency of path curves
const float PATH_WAVE_AMP = 0.78;                         // amplitude of path curves
const vec3 PATH_COLOR = vec3(207.0, 183.0, 153.0) / 255.0;

const float HILL_FREQ = 4.5;                              
const float HILL_OFFSET = 2.0;                            
const float HILL_HEIGHT = 1.2;                      

/* -------------- Asset Controls -------------- */
const vec3 TEMPLE_POS = vec3(-3.7, 0.0, 10.0);
const vec3 TEMPLE_COLOR = vec3(0.0);
#define TEMPLE_BB sdBox(templePos, vec3(6.0, 5.0, 6.0))

const float TEMPLE_SCALE = 0.9;
const float TEMPLE_ROT_Y = 247.0;
const vec3 TREE_COLOR = vec3(161.0, 120.0, 104.0) / 255.0;

struct Tree {
  vec3 pos;
  float radius;
  float height;
};
const Tree R_TREES[2] = Tree[2](  Tree(vec3(-2.7, -7.0, -6.0), 1.0, 10.0),    // first tree right
                                  Tree(vec3(-3.6, -7.0, -1.0), 0.9, 10.0) );  // second tree right
#define R_TREES_BB sdBox(queryPt + vec3(-3.0, 0.0, -4.0), vec3(3.0, 15.0, 6.0))

const Tree L_TREES[4] = Tree[4](  Tree(vec3( 3.6, -7.0, -6.8), 0.7, 10.0),  // first tree left
                                  Tree(vec3( 4.1, -7.0, -4.0), 0.7, 10.0),  // second tree left
                                  Tree(vec3( 3.9, -7.0, -1.5), 0.7, 10.0),  // third tree left
                                  Tree(vec3( 3.3, -7.0,  3.0), 0.9, 10.0) );// fourth tree left
const vec3 L_TREES_BB_LOW = vec3(-5.0, -2.0, -0.5);
const vec3 L_TREES_BB_HIGH = vec3(-1.0, 10.0, 15.0);

const Tree FAR_TREES[4] = Tree[4]( Tree(vec3(-0.5, 0.0, 25.0), 0.8, 22.0),
                                   Tree(vec3(-2.1, 0.0, 18.0), 1.1, 22.0),
                                   Tree(vec3(-5.5, 0.0, 19.0), 0.9, 22.0),
                                   Tree(vec3( 5.5, 0.0, 40.0), 0.8, 22.0));

#define FAR_TREES_BB sdBox(queryPt + vec3(-4.0, 0.0, 30.0), vec3(11.0, 23.0, 21.0))

const vec3 MUSHROOM_COLOR = vec3(1.0, 1.0, 1.0);
const vec3 MAGIC_COLOR = vec3(1.0, 1.0, 0.0);

struct Candle {
  vec3 pos;
  float lightRad;
  float height;
  float radius;
  bool isOn;
};

const Candle CANDLES[4] = Candle[4]( Candle(vec3(-2.0, -0.35, 9.0),  1.5, 0.45, 0.07, false), 
                                     Candle(vec3(-2.5,  0.6, -2.0),  1.5, 0.25, 0.035, true),
                                     Candle(vec3(-2.2,  0.7, -2.4), 1.5, 0.14, 0.025, true),
                                     Candle(vec3(-1.7, -0.35,  8.5), 1.5, 0.18, 0.035, true) );

float mushDist = 0.0;
bool isFlame = false;
float flameT = 0.0;

/// ============================ STRUCTS =================================== ///
struct Ray {
    vec3 origin;
    vec3 direction;
};

struct Intersection {
    vec3 position;
    vec3 normal;
    float distance_t;
    int material_id;
    int material_id2; // so that transparent objs know what's behind it
};


/// ============================ UTILITIES ================================= ///

/* -------------- General ----------------- */
float toRad(float deg){
  return deg * 3.14159 / 180.0;
}
// take the radius and height and find the angle in radians
float getConeAngle(float h, float r){
  float hyp = sqrt(h*h + r*r);
  return acos(h / hyp);
}
vec3 rotateX(vec3 p, float a){
    a = a * 3.14159 / 180.0;
    return vec3(p.x, cos(a) * p.y - sin(a) * p.z, sin(a) * p.y + cos(a) * p.z);
}
vec3 rotateY(vec3 p, float a){
    a = a * 3.14159 / 180.0;
    return vec3(cos(a) * p.x + sin(a) * p.z, p.y, -sin(a) * p.x + cos(a) * p.z);
}
vec3 rotateZ(vec3 p, float a){
    a = a * 3.14159 / 180.0;
    return vec3(cos(a) * p.x - sin(a) * p.y, sin(a) * p.x + cos(a) * p.y, p.z);
}
vec2 rotate(vec2 p, float a){
  a = a * 3.14159 / 180.0;
  return vec2(cos(a) * p.x - sin(a) * p.y, sin(a) * p.x + cos(a) * p.y);
}
vec2 random2( vec2 p ) {
    return fract(sin(vec2(dot(p,vec2(127.1, 311.7)),
                          dot(p,vec2(269.5, 183.3))))
                 *43758.5453);
}
vec3 random3( vec3 p ) {
    return fract(sin(vec3(dot(p,vec3(127.1, 311.7, 191.999)),
                          dot(p,vec3(269.5, 183.3, 765.54)),
                          dot(p, vec3(420.69, 631.2,109.21))))
                 *43758.5453);
}

/* ----------- Transition Funcs ------------ */
float bias(float t, float b){
  return pow(t, log(b) / log(0.5));
}
float easeOutQuad(float x){
  return 1.0 - (1.0 - x) * (1.0 - x);
}
float easeInQuad(float x){
  return x * x;
}
float easeInOutQuad(float x) {
  return x < 0.5 ? 2.0 * x * x : 1.0 - ((-2.0*x + 2.0)*(-2.0*x + 2.0)) / 2.0;
}
float easeOutCubic(float x) {
  return 1.0 - pow(1.0 - x, 3.0);
}
float easeInCubic(float x) {
  return x * x ;
}
float cubicPulse(float c, float w, float x){
  x = abs(x-c);
  if (x>w) return 0.0;
  x /= w;
  return 1.0 - x*x*(3.0 - 2.0*x);
}
float easeOutExpo(float x) {
  return x == 1.0 ? 1.0 : 1.0 - pow(2.0, -10.0 * x);
}
float easeInExpo(float x) {
return x == 0.0 ? 0.0 : pow(2.0, 10.0 * x - 10.0);
}
float easeInQuart(float x) {
return x * x * x * x;
}

/* --------- SDFS & Geometry Funcs ---------- */
float sdfSphere(vec3 query_position, vec3 position, float radius){
    return length(query_position - position) - radius;
}
float sdCone( vec3 p, vec2 c, float h ){
    float q = length(p.xz);
    return max(dot(c.xy,vec2(q,p.y)),-h-p.y);
}
float sdBox( vec3 p, vec3 b ){
  vec3 q = abs(p) - b;
  return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0);
}
float sdBox( in vec2 p, in vec2 b ){
    vec2 d = abs(p)-b;
    return length(max(d,0.0)) + min(max(d.x,d.y),0.0);
}
float sdRoundBox( vec3 p, vec3 b, float r ){
  vec3 q = abs(p) - b;
  return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0) - r;
}
float sdCappedCylinder( vec3 p, float h, float r ){
  vec2 d = abs(vec2(length(p.xz),p.y)) - vec2(h,r);
  return min(max(d.x,d.y),0.0) + length(max(d,0.0));
}
float sdCircle( vec2 p, float r )
{
    return length(p) - r;
}

float opSubtraction( float d1, float d2 ) { return max(-d1,d2); }
float smin( float a, float b, float k ){
    float h = clamp( 0.5+0.5*(b-a)/k, 0.0, 1.0 );
    return mix( b, a, h ) - k*h*(1.0-h);
}
vec3 opSymXZ( in vec3 p ){
    p.xz = abs(p.xz);
    return p;
}
vec3 opCheapBend( in vec3 p, float k ){
    float c = cos(k*p.x);
    float s = sin(k*p.x);
    mat2  m = mat2(c,-s,s,c);
    vec3  q = vec3(m*p.xy,p.z);
    return q;
}

vec3 opRep( in vec3 p, in vec3 c){
    vec3 q = mod(p+0.5*c,c)-0.5*c;
    return q;
}

/* -------------- Noise funcs --------------- */
float surflet(vec2 p, vec2 gridPoint) {
    // Compute the distance between p and the grid point along each axis, and warp it with a
    // quintic function so we can smooth our cells
    vec2 t2 = abs(p - gridPoint);
    vec2 t = vec2(1.0) - 6.0 * vec2(pow(t2.x, 5.0), pow(t2.y, 5.0)) + 
                         15.0 * vec2(pow(t2.x, 4.0), pow(t2.y, 4.0)) - 
                         10.0 * vec2(pow(t2.x, 3.0), pow(t2.y, 3.0));

    vec2 gradient = random2(gridPoint) * 2.0 - vec2(1.0);
    // Get the vector from the grid point to P
    vec2 diff = p - gridPoint;
    // Get the value of our height field by dotting grid->P with our gradient
    float height = dot(diff, gradient);
    // Scale our height field (i.e. reduce it) by our polynomial falloff function
    return height * t.x * t.y;
}
float perlinNoise2D(vec2 p) {
	float surfletSum = 0.0;
	// Iterate over the four integer corners surrounding uv
	for(int dx = 0; dx <= 1; ++dx) {
		for(int dy = 0; dy <= 1; ++dy) {
				surfletSum += surflet(p, floor(p) + vec2(dx, dy));
		}
	}
	return surfletSum;
}
float surflet(vec3 p, vec3 gridPoint) {
    // Compute the distance between p and the grid point along each axis, and warp it with a
    // quintic function so we can smooth our cells
    vec3 t2 = abs(p - gridPoint);
    vec3 t = vec3(1.0) - 6.0 * vec3(pow(t2.x, 5.0), pow(t2.y, 5.0), pow(t2.z, 5.0)) + 15.0 * vec3(pow(t2.x, 4.0), pow(t2.y, 4.0), pow(t2.z, 4.0)) - 10.0 * vec3(pow(t2.x, 3.0), pow(t2.y, 3.0), pow(t2.z, 3.0));

    vec3 gradient = random3(gridPoint) * 2.0 - vec3(1.0);
    // Get the vector from the grid point to P
    vec3 diff = p - gridPoint;
    // Get the value of our height field by dotting grid->P with our gradient
    float height = dot(diff, gradient);
    // Scale our height field (i.e. reduce it) by our polynomial falloff function
    return height * t.x * t.y * t.z;
}

float perlinNoise3D(vec3 p) {
	float surfletSum = 0.0;
	// Iterate over the four integer corners surrounding uv
	for(int dx = 0; dx <= 1; ++dx) {
		for(int dy = 0; dy <= 1; ++dy) {
			for(int dz = 0; dz <= 1; ++dz) {
				surfletSum += surflet(p, floor(p) + vec3(dx, dy, dz));
			}
		}
	}
	return surfletSum;
}
float Worley3D(vec3 p) {
    // Tile the space
    vec3 pointInt = floor(p);
    vec3 pointFract = fract(p);

    float minDist = 1.0; // Minimum distance initialized to max.

    // Search all neighboring cells and this cell for their point
    for(int z = -1; z <= 1; z++){
        for(int y = -1; y <= 1; y++){
            for(int x = -1; x <= 1; x++){
                vec3 neighbor = vec3(float(x), float(y), float(z));

                // Random point inside current neighboring cell
                vec3 point = random3(pointInt + neighbor);

                // Compute the distance b/t the point and the fragment
                // Store the min dist thus far
                vec3 diff = neighbor + point - pointFract;
                float dist = length(diff);
                minDist = min(minDist, dist);
            }
        }
    }
    return minDist;
}
float Worley2D(vec2 p, out float sparkleSize) {
    // Tile the space
    vec2 pointInt = floor(p);
    vec2 pointFract = fract(p);

    float minDist = 1.0; // Minimum distance initialized to max.

    // Search all neighboring cells and this cell for their point
    for(int y = -1; y <= 1; y++){
        for(int x = -1; x <= 1; x++){
            vec2 neighbor = vec2(float(x), float(y));

            // Random point inside current neighboring cell
            vec2 point = random2(pointInt + neighbor);

            // Compute the distance b/t the point and the fragment
            // Store the min dist thus far
            vec2 diff = neighbor + point - pointFract;
            float dist = length(diff);

            if (dist < minDist){
              minDist = dist;
              sparkleSize = random2(point).x;
            }
            
        }
    }
    return minDist;
}

/// ========================== SCENE SDFS ================================== ///

float getGrassHeight(vec2 uv){
  float randHeight = 0.0;
  float worleyDist = Worley2D(8.0*uv, randHeight);

  randHeight = mix(0.05, 0.3, randHeight);
  if (worleyDist < 0.15){
    return mix(randHeight, 0.0, easeOutCubic(worleyDist / 0.15));
  }
  return 0.0;
}
float getTerrainHeight(vec2 uv, out bool isPath, float ptY){
  isPath = false;

  float maxTerrainHeight = 0.0;
  //return sdBox(vec3(uv.x, ptY, uv.y) - vec3(0.0, -3.0, 0.0), vec3(6.0, 2.0, 15.0));
  if (sdBox(vec3(uv.x, ptY, uv.y) - vec3(0.0, -3.0, 0.0), vec3(6.0, 5.5, 15.0)) <= EPSILON){
    //return sdBox(vec3(uv.x, ptY, uv.y) - vec3(0.0, 1.0, 0.0), vec3(30.0, 2.0, 30.0));
    // create hills
    float perlinDeform = /*uv[1] > -10.0 && uv.x < 5.0 && uv.x > -6.0 ?*/ perlinNoise2D((uv / HILL_FREQ) + HILL_OFFSET) /*: 0.f*/;
    float deformedHeight = HILL_HEIGHT * perlinDeform + GROUND_HEIGHT;

    // displace path in shape of sin wave
    float wavyPath = PATH_OFFSET_X - PATH_WAVE_AMP * sin((uv.y - PATH_OFFSET_Z) / PATH_WAVE_FREQ);

    // find distance to path to determine color & amount of hill deformation
    float distToPath = abs(uv.x - wavyPath);
    if (distToPath < PATH_PAVE_WIDTH){    
      if (distToPath < PATH_COLOR_WIDTH){
        isPath = true;
        //deformedHeight = deformedHeight + getGrassHeight(uv);
      }  
      return mix(ptY - GROUND_HEIGHT, ptY - deformedHeight, easeInOutQuad(distToPath / PATH_PAVE_WIDTH));
    }
    //float grassSDF = ptY - (deformedHeight + getGrassHeight(uv));
    //float grassHeight = 1.1;
    //float grassRadius = 0.03;
    //float grassSDF2 = sdCone(opRep(vec3(uv.x, ptY - deformedHeight, uv.y), vec3(1.0, 0.0, 1.0)), vec2(cos(getConeAngle(grassHeight, grassRadius)), sin(getConeAngle(grassHeight, grassRadius))), grassHeight);
    return /*smin(*/ptY - deformedHeight/*, grassSDF, 0.01)*/;
  }
  return MAX_FLT;
}

float raisedGroundSDF(vec3 queryPt, float rotY, float rotZ){
  return sdRoundBox(rotateZ(rotateY(queryPt + RAISED_GROUND_POS, rotY),rotZ), RAISED_GROUND_SCALE, 1.0);
}

// the distant trees with less detail
float fakeTreeSDF(vec3 queryPt, Tree t){
  float treeTrunk = sdCappedCylinder(queryPt + t.pos, t.radius, t.height);
  return treeTrunk;
}

float branchSDF(vec3 queryPt, vec3 pos, float rotY){
  vec3 p = queryPt + pos;
  p = rotateY(p, rotY);

  float base = sdCappedCylinder(rotateZ(p, -40.0), 0.25, 1.0);

  float coneH = 13.5;
  float coneR = 0.25;
  vec2 angles = vec2(cos(getConeAngle(coneH, coneR)), sin(getConeAngle(coneH, coneR)));

  float cone = sdCone(p + vec3(0.7, -14.3, 0.0), angles, coneH);
  return smin(base, cone, 0.7);
}

float treeSDF(vec3 queryPt, float rotY, float rotZ, Tree t){
  vec3 p = rotateY(rotateZ(queryPt + t.pos, rotZ), rotY);

  if (sdBox(p, vec3(4.0, 35.0, 4.0)) <= EPSILON){
    //return sdBox(p, vec3(1.0, 20.0,1.0));
    // tree knot controls
    float treeKnotRadius = 0.8 * t.radius;
    float treeKnotHeight = 0.25 * t.height;
    float treeKnotSmoothFactor = 0.7;

    // get angles to create tree knot cones
    float treeKnotAngle = getConeAngle(treeKnotHeight, treeKnotRadius);
    vec2 treeKnotAngles = vec2(cos(treeKnotAngle), sin(treeKnotAngle));

    // find tree knot displacements (relative to trunk)
    vec3 treeKnotDisplacement1 = vec3(t.radius - 0.29*treeKnotRadius, t.height - treeKnotHeight, t.radius - 0.29*treeKnotRadius);
    vec3 treeKnotDisplacement2 = vec3(-treeKnotDisplacement1.x, treeKnotDisplacement1.yz);
    vec3 treeKnotDisplacement3 = vec3(-treeKnotDisplacement1.x, treeKnotDisplacement1.y, -treeKnotDisplacement1.z);
    vec3 treeKnotDisplacement4 = vec3(treeKnotDisplacement1.x, treeKnotDisplacement1.y, -treeKnotDisplacement1.z);
  
    // tree knot sdf definitions
    float treeKnot1 = sdCone(p + treeKnotDisplacement1, treeKnotAngles, treeKnotHeight);
    float treeKnot2 = sdCone(p + treeKnotDisplacement2, treeKnotAngles, treeKnotHeight);
    float treeKnot3 = sdCone(p + treeKnotDisplacement3, treeKnotAngles, treeKnotHeight);
    float treeKnot4 = sdCone(p + treeKnotDisplacement4, treeKnotAngles, treeKnotHeight);
    float treeTrunk = sdCappedCylinder(p, t.radius, t.height);
  
    // smooth SDF between trunk and knots
    float res = smin(treeTrunk, treeKnot1, treeKnotSmoothFactor);
    res = smin(res, treeKnot2, treeKnotSmoothFactor);
    res = smin(res, treeKnot3, treeKnotSmoothFactor);
    res = smin(res, treeKnot4, treeKnotSmoothFactor);

    float worleyFactor = 0.1*perlinNoise3D(vec3(0.9)*p);

    return res + worleyFactor;
  }
  return MAX_FLT;
}

float forestSDF(vec3 queryPt){
  float minSDF = MAX_FLT;

  if (R_TREES_BB <= EPSILON){
    //minSDF = min(minSDF, sdBox(queryPt + vec3(-3.0, 0.0, -4.0), vec3(2.0, 14.0, 3.0)));
    for (int i = 0; i < R_TREES.length(); i++){
      float rand = clamp(random2(vec2(i + 1, i)).x, 0.0, 1.0);
      float rotZ = mix(-2.0, 2.0, rand);
      float rotY = mix(-180.0, 180.0, rand);
      minSDF = min(minSDF, treeSDF(queryPt, rotY, rotZ, R_TREES[i]));
    }
  }
  
  if (sdBox(queryPt + vec3(3.0, 0.0, -2.0), vec3(2.5, 15.0, 6.0)) <= EPSILON){
    //minSDF = min(minSDF, sdBox(queryPt + vec3(3.0, 0.0, -2.0), vec3(2.0, 13.0, 4.0)));
    for (int i = 0; i < L_TREES.length(); i++){
      float rand = clamp(random2(vec2(i + 1, i)).x, 0.0, 1.0);
      float rotZ = mix(-2.0, 2.0, rand);
      float rotY = mix(-180.0, 180.0, rand);
      minSDF = min(minSDF, treeSDF(queryPt, rotY, rotZ, L_TREES[i]));
    }
  }
    if (FAR_TREES_BB <= EPSILON){
        for (int i = 0; i < FAR_TREES.length(); i++){
        minSDF = min(minSDF, fakeTreeSDF(queryPt, FAR_TREES[i]));
      }
    }

    float branch1SDF = branchSDF(queryPt, vec3(0.5, -5.0, 25.0), 0.0);
    float branch2SDF = branchSDF(queryPt, vec3(4.5, -7.0, 3.0), 0.0);
    float branch3SDF = branchSDF(queryPt, vec3(-6.5, -10.0, 19.0), 180.0);
    minSDF = smin(minSDF, branch1SDF, 0.3);
    minSDF = smin(minSDF, branch2SDF, 0.2);
    minSDF = smin(minSDF, branch3SDF, 0.4);

  return minSDF;
}

bool getRainColor(vec2 uv){
  uv = uv * 2.0;
  uv.y = uv.y + u_Time * 0.3;

  // if I want to add wind in future, here's a start
    /*float amtWindTime = 0.3;
    float windT = abs(sin(u_Time*0.01));
    uv = rotate(uv, mix(0.0, -10.0, cubicPulse(0.5, amtWindTime, windT)));
    uv.y += u_Time*0.3 * mix(1.0, 1.5, cubicPulse(0.5, amtWindTime, windT));*/

  // use worley method to setup cell centers and see if points fall in rectangle
  // sdf with cell center as rectangle center
  vec2 pointInt = floor(uv);
  vec2 pointFract = fract(uv);
  vec2 boxDims = vec2(RAIN_WIDTH, MIN_RAIN_HEIGHT);

  float minDist = 1.0;
  vec2 minDiff = vec2(0.0);
  vec2 minCellCenter = vec2(0.0);

  // Search all neighboring cells and this cell for their point
  for(int y = -1; y <= 1; y++){
    for(int x = -1; x <= 1; x++){
      vec2 neighbor = vec2(float(x), float(y));

      // Random point inside current neighboring cell
      vec2 point = pointInt + neighbor;
      vec2 cellCenter = random2(point);

      // Compute the distance b/t the point and the fragment
      // Store the min dist thus far
      vec2 diff = neighbor + cellCenter - pointFract;
      float dist = length(diff);
      if (dist < minDist){
        minDist = dist;
        minDiff = diff;
        minCellCenter = cellCenter;
      }
    }
  }

  // randomize rain height (based on which cell center related to)
  boxDims.y = mix(MIN_RAIN_HEIGHT, MAX_RAIN_HEIGHT, random2(minCellCenter).x);

  // in box if x and y values are smaller than box dimensions
  bool inBox = abs(minDiff.x) <= (boxDims.x / 2.0) && abs(minDiff.y) <= (boxDims.y / 2.0);

  // ensure smaller than some value to avoid artifacts
  if (minDist < 0.5 && inBox){
      return true;
    }

  return false;
}

float columnSDF(vec3 queryPt, vec3 columnPos){
  vec3 columnPt = queryPt + columnPos;

  float baseH = 0.1, baseW = 0.44;
  float stone1H = 0.56, stone1W = 0.28;
  float stone2H = 0.58, stone2W = 0.16;
  float stone3H = 0.1, stone3W = 0.25;

  float minSDF = sdBox(columnPt, vec3(0.44, 0.1, 0.44));
  minSDF = min( minSDF, sdRoundBox(columnPt + vec3(0.0, -(baseH + stone1H), 0.0), vec3(stone1W, stone1H, stone1W), 0.1) );
  minSDF = min( minSDF, sdRoundBox(columnPt + vec3(0.0, -(baseH + stone1H + stone2H + 0.6), 0.0), vec3(stone2W, stone2H, stone2W), 0.1) );
  minSDF = min( minSDF, sdRoundBox(columnPt + vec3(0.0, -(baseH + stone1H + stone2H + stone3H + 1.2), 0.0), vec3(stone3W, stone3H, stone3W), 0.05) );

  return minSDF;
}

float templeSDF(vec3 queryPt){

  vec3 templePos = rotateY(queryPt + TEMPLE_POS, TEMPLE_ROT_Y) / TEMPLE_SCALE;

  if (TEMPLE_BB <= EPSILON){
    float minSDF = sdRoundBox(templePos, vec3(2.7, 0.15, 2.7), 0.05);

    // columns
    float columnPadding = 1.8;

    // columns symmetrical around xz planes
    minSDF = min(minSDF, columnSDF(opSymXZ(templePos), vec3(-columnPadding, -0.3, -columnPadding))); 

    // temple top
    minSDF = min( minSDF, sdRoundBox(templePos + vec3(0.0, -3.1, 0.0), vec3(2.2, 0.13, 2.2), 0.05) );
    minSDF = min( minSDF, sdRoundBox(templePos + vec3(0.0, -3.5, 0.0), vec3(2.5, 0.3, 2.5), 0.05) );
    minSDF = min( minSDF, sdRoundBox(templePos + vec3(0.0, -4.1, 0.0), vec3(1.9, 0.3, 1.9), 0.05) );
    minSDF = min( minSDF, sdRoundBox(templePos + vec3(0.0, -4.5, 0.0), vec3(1.5, 0.18, 1.5), 0.1) );

    return minSDF;
  }
  return MAX_FLT;
}

float mushroomSDF(vec3 queryPt, vec3 pos, float scale){
  //return sdBox(queryPt - pos, vec3(scale));
  if (sdBox(queryPt - pos, vec3(scale + 1.0)) <= EPSILON){
    vec3 p = queryPt - pos;
    p = p/scale;
    vec3 bentPtZ = opCheapBend(p, -0.3);
    vec3 rotY = rotateY(bentPtZ, 90.0);
    vec3 bentPtX = opCheapBend(rotY, -0.3);
    float minSDF = sdCappedCylinder(bentPtX, 0.9, 0.02);
    return minSDF;
  }
  return MAX_FLT;
}

float candleSDF(vec3 queryPt, Candle candle, out int candleMat) {
  //return sdBox(queryPt + candle.pos, vec3(candle.radius + 0.1, candle.height*2.0, candle.radius + 0.1));
  if (sdBox(queryPt + candle.pos, vec3(candle.radius + 0.7, candle.height*3.2, candle.radius + 0.7)) <= EPSILON){
    vec3 p = queryPt + candle.pos;

  float base = sdCappedCylinder(p, candle.radius, candle.height);
  float flame = MAX_FLT;
  
  if (candle.isOn){
    flame = sdfSphere(queryPt, -candle.pos + vec3(0.0, candle.height +0.1, 0.0), candle.radius*0.8);
    float flameTop = sdCone(queryPt + candle.pos - vec3(0.0, candle.height +0.25, 0.0), vec2(cos(getConeAngle(0.08, 0.01)), sin(getConeAngle(0.08, 0.01))), 0.08f);

    flame = smin(flame, flameTop, 0.1);
  }
 
  if (flame < base){
    candleMat = CANDLE_FLAME_ID;
  }
  else{
    candleMat = CANDLE_MAT_ID;
  }
  return min(base, flame);
  }
  return MAX_FLT;
}

float allCandlesSDF(vec3 queryPt, out int candleMat){
  float minSDF = MAX_FLT;

  for (int i = 0; i < CANDLES.length(); i++){
    float candleSDF = candleSDF(queryPt, CANDLES[i], candleMat);
    if (CANDLES[i].isOn && candleMat == CANDLE_FLAME_ID && candleSDF <= EPSILON) {
      isFlame = true;
      if (flameT == 0.0){
        flameT = length(queryPt - (-CANDLES[i].pos + vec3(0.0, CANDLES[i].height +0.12, 0.0)));
      }
      return MAX_FLT;
    }
    minSDF = min(minSDF, candleSDF);
  }
 
  candleMat = CANDLE_MAT_ID;
  return minSDF;
}

float sceneSDF(vec3 queryPt, out int material_id, out int material_id2, out bool terminateRaymarch, out bool isMagic, out bool isMushroom) {
    bool isPath;
    terminateRaymarch = false;
    isMagic = false;

    float minSDF = getTerrainHeight(queryPt.xz, isPath, queryPt.y);
    minSDF = smin(minSDF, raisedGroundSDF(queryPt, 240.0, -3.0), 0.9);
    material_id = isPath ? PATH_MAT_ID : GROUND_MAT_ID;

    // if pt - terrainHeight is negative, pt is under land, terminate early
    /*if (minSDF < 0.0){
      terminateRaymarch = true;
      return -1.0;
    }*/

    float forestSDF = forestSDF(queryPt);
    if (forestSDF < minSDF){
      material_id = TREE_MAT_ID;
    }

    minSDF = smin(minSDF, forestSDF, 0.4);

    float templeSDF = templeSDF(queryPt);
    if (templeSDF < minSDF){
      minSDF = templeSDF;
      material_id = TEMPLE_MAT_ID;
    }

    int candleMat = CANDLE_MAT_ID;
    float candleSDF = allCandlesSDF(queryPt, candleMat); 
    if (candleSDF < minSDF){
      minSDF = candleSDF;
      material_id = candleMat;
    }

    float magicMushroomSDF = mushroomSDF(queryPt, vec3(-3.6, 0.4, 3.8), 1.0);
    float magicMushroomSDF2 = mushroomSDF(queryPt, vec3(-2.5, 0.3, -2.7), 1.0);
    float magicMushroomSDF3 = mushroomSDF(queryPt, vec3(-3.5, 1.5, -2.7), 1.0);

    if (magicMushroomSDF < EPSILON*10.0 || magicMushroomSDF2 < EPSILON*10.f || magicMushroomSDF3 < EPSILON*10.f){
        isMagic = true;
      }

    if (magicMushroomSDF <= EPSILON || magicMushroomSDF2 <= EPSILON || magicMushroomSDF3 <= EPSILON){
      isMushroom = true;
      if (magicMushroomSDF <= EPSILON && mushDist == 0.0){
        mushDist = length(queryPt -vec3(-3.6, 0.4, 3.8));
      }
      else if (magicMushroomSDF2 <= EPSILON && mushDist == 0.0){
        mushDist = length(queryPt - vec3(-2.5, 0.3, -2.7));
      }
      else if (magicMushroomSDF3 <= EPSILON && mushDist == 0.0){
        mushDist = length(queryPt - vec3(-3.5, 1.5, -2.7));
      }
      
    }
    else if (magicMushroomSDF < minSDF || magicMushroomSDF2 < minSDF || magicMushroomSDF3 < minSDF){
      minSDF = min(min(magicMushroomSDF, magicMushroomSDF2), magicMushroomSDF3);
    }

    return minSDF;   
}

// For normal calcs -- no material ids returned
float sceneSDF(vec3 queryPt) {
    bool isPath;
    float minSDF = getTerrainHeight(queryPt.xz, isPath, queryPt.y);
    minSDF = smin(minSDF, raisedGroundSDF(queryPt, 240.0, -3.0), 0.9);
    minSDF = min(minSDF, templeSDF(queryPt));
    //minSDF = min(minSDF, mushroomSDF(queryPt, vec3(-3.5, 0.3, 3.7), 1.0));
    return min(minSDF, forestSDF(queryPt));
    
}

/// ========================== SCENE EVALUATION ============================ ///
Ray getRay(vec2 uv) {
    Ray r;
    
    vec3 look = normalize(u_Ref - u_Eye);
    float len = length(u_Ref - u_Eye);
    vec3 camera_RIGHT = normalize(cross(look, u_Up));
    vec3 camera_UP = cross(camera_RIGHT, look);
    
    float aspect_ratio = u_Dimensions.x / u_Dimensions.y;
    vec3 screen_vertical = camera_UP * len * tan(FOV / 2.0); 
    vec3 screen_horizontal = camera_RIGHT * len * aspect_ratio * tan(FOV / 2.0);
    vec3 screen_point = (u_Ref + uv.x * screen_horizontal + uv.y * screen_vertical);
    
    r.origin = u_Eye;
    r.direction = normalize(screen_point - u_Eye);
   
    return r;
}

vec3 getNormal(vec3 queryPt){
  vec2 d = vec2(0.0, EPSILON);
  float x = sceneSDF(queryPt + d.yxx) - sceneSDF(queryPt - d.yxx);
  float y = sceneSDF(queryPt + d.xyx) - sceneSDF(queryPt - d.xyx);
  float z = sceneSDF(queryPt + d.xxy) - sceneSDF(queryPt - d.xxy);
  return normalize(vec3(x,y,z));
}

Intersection getRaymarchedIntersection(vec2 uv, out bool isMagicExpanded, out bool isMushroom) {
    Intersection isect;    
    isect.distance_t = -1.0;
    isMagicExpanded = false;

    Ray r = getRay(uv);
    float dist_t = EPSILON;

    // values to be filled by sceneSDF
    bool terminateRaymarch = false;
    int material_id = -1;
    int material_id2 = -1;

    for (int step = 0; step < MAX_RAY_STEPS; ++step){
      if (dist_t > float(MAX_RAY_LENGTH)){
        return isect;
      }
      // raymarch
      vec3 queryPt = r.origin + dist_t * r.direction;
      bool isMagic = false;
      float curDist = sceneSDF(queryPt, material_id, material_id2, terminateRaymarch, isMagic, isMushroom);

      if (isMagic) isMagicExpanded = true;

      // if ray is under terrain, terminate marching
      if (terminateRaymarch){
        return isect;
      }

      // if we hit something, return intersection
      if (curDist < EPSILON){
        isect.distance_t = dist_t;
        isect.position = queryPt;
        isect.normal = getNormal(queryPt);
        isect.material_id = material_id;
        isect.material_id2 = material_id2;
        return isect;
      }
      dist_t += curDist;
    }
    return isect;
}

float isInShadow(vec3 p){
  Ray r = Ray(p, normalize(SKY_LIGHT_POS - p));

  float t = EPSILON;
  float res = 1.0;

  for (int step = 0; step < MAX_RAY_STEPS; ++step){
      // raymarch
      vec3 queryPt = r.origin + t * r.direction;
      float h = sceneSDF(queryPt);

      // if we hit something, return intersection
      if (h < EPSILON){
        return 0.0;
      }
      res = min(res, 150.0*h/t);
      t += h;
  }
  return res;
}

float getDiffuseTerm(vec3 p, vec3 n){
  vec3 lightVec = SKY_LIGHT_POS - p;
  float lengthToSkyLight = length(lightVec);
  
  float diffuseTerm = 0.02; // don't make it too low -- we want to see some color
  float falloffDist = 5.0;  // sky light falloff dist

  // if outside light radius, in shadow
  if (lengthToSkyLight < SKY_LIGHT_RADIUS + falloffDist){
    diffuseTerm = dot(normalize(lightVec), n);

    // if outside radius, but in falloff range, interpolate
    if (lengthToSkyLight > SKY_LIGHT_RADIUS){
      diffuseTerm = mix(diffuseTerm, 0.02, (lengthToSkyLight - SKY_LIGHT_RADIUS) / falloffDist);
    }
  }

  // handle candles
  for (int i = 0; i < CANDLES.length(); i++){
    float distToLight = length(p + CANDLES[i].pos - vec3(0.0, CANDLES[i].height + 0.15 + (CANDLES[i].radius / 2.f), 0.0));

    if (distToLight < CANDLES[i].lightRad && CANDLES[i].isOn){
      diffuseTerm += mix(1.5, 0.0, easeOutCubic(distToLight / CANDLES[i].lightRad));
    }
  }
  return clamp(diffuseTerm, 0.0, 1.5);
}

vec4 applyFog(float zDepth, vec4 lambert_color, int material_id){
  float fogStart = 7.0;
  float fogEnd = -15.0;
  float fogAlphaEnd = -55.0;

  // if z value is between end and alpha end, interpolate between transparency 0 and 1
  if (zDepth < fogEnd && zDepth > fogAlphaEnd){
    return mix(FOG_COLOR, SKY_COLOR, abs(zDepth - fogEnd) / abs(fogAlphaEnd - fogEnd));
  }
  // if z depth less than alphaEnd (furthest away), return sky color
  if (zDepth < fogAlphaEnd){
    return SKY_COLOR;
  }
  // if z depth is beyond the start z value, interpolate between lambert and fog color
  if (zDepth < fogStart){
    // to make candles more red even though there's fog
    if (material_id == CANDLE_MAT_ID){
      return mix(lambert_color, FOG_COLOR - vec4(0.0, 0.05, 0.05, 0.0), easeOutQuad(abs(zDepth - fogStart) / abs(fogStart - fogEnd)));
    }
    return mix(lambert_color, FOG_COLOR, easeOutQuad(abs(zDepth - fogStart) / abs(fogStart - fogEnd)));
  }
  return lambert_color;
}

vec4 getMaterial(vec3 n, int material_id, int material_id2, float zDepth, vec3 isectPt, bool isMushroom){

  float diffuseTerm = 0.05;

  // calc shadow; if in shadow, add faint blue shadow
  float softShadowTerm = /*isInShadow(isectPt + 0.005 * n)*/ 0.0;

  diffuseTerm = getDiffuseTerm(isectPt, n);
  
  // calc lambert color
  vec4 materialCol;
  switch(material_id){
    case(GROUND_MAT_ID):
      materialCol = vec4(GROUND_COLOR, 1.0);
      break;
    case(TREE_MAT_ID):
      materialCol = vec4(TREE_COLOR, 1.0);
      break;
    case(PATH_MAT_ID):
      materialCol = vec4(PATH_COLOR, 1.0);
      break;
    case(TEMPLE_MAT_ID):
      materialCol = vec4(TEMPLE_COLOR, 1.0);
      break;
    case(CANDLE_MAT_ID):
      materialCol = vec4(1.0, 0.0, 0.0, 1.0);
      break;
    case(MUSHROOM_MAT_ID):
      vec3 behindColor = SKY_COLOR.rgb;
      if (material_id2 == GROUND_MAT_ID) behindColor = GROUND_COLOR;
      if (material_id2 == TREE_MAT_ID) behindColor = TREE_COLOR;
      if (material_id2 == PATH_MAT_ID) behindColor = PATH_COLOR;
      if (material_id2 == TEMPLE_MAT_ID) behindColor = TEMPLE_COLOR;
      materialCol = vec4(behindColor, 1.0);
      break;
    default:
      materialCol = vec4(0.0, 0.0, 1.0, 1.0);
  }

  /*float guideLightRadius = 1.5;
  float distToGuideLight = length(isectPt - GUIDE_LIGHT_POS);
  float guideLightT = easeOutQuad(distToGuideLight / guideLightRadius);
  vec3 guideLightFactor = distToGuideLight < guideLightRadius ? 
                          mix(GUIDE_LIGHT_COLOR, vec3(0.0), guideLightT) : vec3(0.0);*/
  
  vec4 ambientTerm = vec4(0.03, 0.07, 0.09, 0.0);
  vec4 lambert_color = vec4(materialCol.rgb * diffuseTerm /*+ 2.0*guideLightFactor*/, materialCol.a) + ambientTerm;

  if (material_id == MUSHROOM_MAT_ID){
      vec3 mushroomCenter = vec3(-3.5, 0.3, 3.7);
      float distToCenter = length(mushroomCenter - isectPt);
      vec4 mushroomCol = mix(lambert_color, vec4(MUSHROOM_COLOR, 1.0), /*easeInCubic(distToCenter) / 0.9*/ 0.3);
      lambert_color = mix(mushroomCol, lambert_color, 0.5);
  }

  if (isFlame){
    vec4 flameColor = mix(vec4(1.9, 1.5, 0.5, 1.0), vec4(1.0, 0.77, 0.5, 1.0), 1.0 -cubicPulse(0.35, 0.4, clamp(flameT / 0.09, 0.0, 1.0)));
    lambert_color = mix(flameColor, lambert_color, 1.0 -cubicPulse(0.7, 0.4, clamp(flameT / 0.09, 0.0, 1.0)));

    /*if (flameT < 0.05){
      lambert_color = vec4(1.0);
    }*/
  }
  if (isMushroom){
    lambert_color = mix(vec4(1.0), lambert_color + vec4(0.05), easeOutExpo(1.f - (mushDist*1.1f)));
  }

  vec4 shadowCol = mix(lambert_color, vec4(0.01, 0.0, 0.15, 1.0), 0.3);
  lambert_color = mix(shadowCol, lambert_color, softShadowTerm);

  // calc fog
  vec4 res = applyFog(zDepth, lambert_color, material_id);

  return res;
}

vec4 getSceneColor(vec2 uv, out bool isMagic){
  bool isMushroom = false;
  Intersection intersection = getRaymarchedIntersection(uv, isMagic, isMushroom);
  
  if (intersection.distance_t > 0.0)
  { 
      return getMaterial(intersection.normal, intersection.material_id, intersection.material_id2,
                         intersection.position.z, intersection.position, isMushroom);
      return vec4(intersection.normal, 1.0);
  }
  return SKY_COLOR;
}

void main() {
  // get ndcs
  vec2 uv = fs_Pos.xy;

  // get the scene color
  bool isMagic = false;
  vec4 col = getSceneColor(uv, isMagic);
  //Ray r = getRay(uv);
  
  bool isRain = getRainColor(uv);
  //bool isRain = false;
  if (isRain){
      out_Col = mix(col, vec4(1.0), 0.20);
  }
  else if (isMagic){
    float sparkleSize = 0.0;
    float freqMix = uv.x > -0.43 ? 55.0 : 30.0;
    float worley = Worley2D(freqMix*uv, sparkleSize);
    sparkleSize = mix(0.2, 0.7, easeInExpo(sparkleSize));
    if (worley < sparkleSize){
      out_Col = mix(vec4(1.0, 1.0, 0.1, 0.5), col, easeOutCubic(worley / sparkleSize));
    }
    else{
      out_Col = col;
    }
  }
  else{ 
      out_Col = col;  
  }
  
  //out_Col = vec4(0.5 * (r.direction + vec3(1.0, 1.0, 1.0)), 1.0);
}
