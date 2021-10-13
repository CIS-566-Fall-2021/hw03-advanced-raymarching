#version 300 es
precision highp float;

uniform vec3 u_Eye, u_Ref, u_Up;
uniform vec2 u_Dimensions;
uniform float u_Time;

in vec2 fs_Pos;
out vec4 out_Col;

const int MAX_RAY_STEPS = 70;
const float FOV = 45.0;
const float EPSILON = 1e-5;
const float BOX_EPSILON = 0.9;
const float MAX_RAY_Z = 40.0;
#define DIST_LIMIT 1
// const vec3 EYE = vec3(0.0, 0.0, 10.0);
const vec3 ORIGIN = vec3(0.0, 0.0, 0.0);
// const vec3 WORLD_UP = vec3(0.0, 1.0, 0.0);
const vec3 WORLD_RIGHT = vec3(-1.0, 0.0, 0.0);
const vec3 WORLD_FORWARD = vec3(0.0, 0.0, 1.0);


//AO

const int AO_SAMPLES = 256;
const float AO_DIST = 0.2;
const float FIVETAP_K = 2.0;

// LIGHTING
const vec3 LIGHT_DIR = vec3(-1.0, 2.0, 15.0);
const float SHADOW_HARDNESS = 6.0;
// Want sunlight to be brighter than 100% to emulate
// High Dynamic Range
vec3 KEY_LIGHT_COLOUR = vec3(1, 1, 0.96) ;
vec3 KEY_LIGHT_POS = normalize(vec3(-3., 3., 15.0));
// Fill light is sky color, fills in shadows to not be black
vec3 FILL_LIGHT_COLOUR = vec3(0.11, 0.25, 0.46);
vec3 FILL_LIGHT_POS  = normalize(vec3(-6., 3., 15.0));
// Faking global illumination by having sunlight
// bounce horizontally only, at a lower intensity
vec3 AMBIENT_LIGHT_COLOUR = vec3(1, 0.9, 0.88) ; // * 0.2
vec3 AMBIENT_LIGHT_POS = normalize(vec3(6., 0., 15.0));

vec3 WATERFALL_LIGHT_COLOUR = vec3(0.21, 0.4, 0.58) ; // * 0.2
vec3 WATERFALL_LIGHT_POS = normalize(vec3(-5., 6., 3.0));

vec3 FOG_COLOR = vec3(0.78, 0.66, 1) ;
vec3 SKY_COLOR = vec3(1, 1, 0.96) ;
// SDF CONSTANTS
const int BACKGROUND = 0;
const int FLOOR = 1;
const int TOWER = 2;
const int DETAILS = 3;
const int BIRD = 4;
const int ROOF = 5;
const int WATERFALL = 6;

struct Ray {
  vec3 origin;
  vec3 direction;
};

struct Intersection {
  vec3 position;
  vec3 normal;
  float distance_t;
  int material_id;
};

struct DirectionalLight
{
  vec3 dir;
  vec3 color;
};


/*
NOISE FUNCTIONS
*/

float random1( vec3 p ) {
  return fract(sin((dot(p, vec3(127.1,
  311.7,
  191.999)))) *
  18.5453);
}

float smootherStep(float a, float b, float t) {
    t = t*t*t*(t*(t*6.0 - 15.0) + 10.0);
    return mix(a, b, t);
}

float interpNoise3D(float x, float y, float z) {
  x *= 2.;
  y *= 2.;
  z *= 2.;
  float intX = floor(x);
  float fractX = fract(x);
  float intY = floor(y);
  float fractY = fract(y);
  float intZ = floor(z);
  float fractZ = fract(z);
  float v1 = random1(vec3(intX, intY, intZ));
  float v2 = random1(vec3(intX + 1., intY, intZ));
  float v3 = random1(vec3(intX, intY + 1., intZ));
  float v4 = random1(vec3(intX + 1., intY + 1., intZ));

  float v5 = random1(vec3(intX, intY, intZ + 1.));
  float v6 = random1(vec3(intX + 1., intY, intZ + 1.));
  float v7 = random1(vec3(intX, intY + 1., intZ + 1.));
  float v8 = random1(vec3(intX + 1., intY + 1., intZ + 1.));

  float i1 = smootherStep(v1, v2, fractX);
  float i2 = smootherStep(v3, v4, fractX);
  float result1 = smootherStep(i1, i2, fractY);
  float i3 = smootherStep(v5, v6, fractX);
  float i4 = smootherStep(v7, v8, fractX);
  float result2 = smootherStep(i3, i4, fractY);
  return smootherStep(result1, result2, fractZ);
}

float fbm(float x, float y, float z, float octaves) {
  float total = 0.;
  float persistence = 0.5f;
  for(float i = 1.; i <= octaves; i++) {
    float freq = pow(2., i);
    float amp = pow(persistence, i);
    total += interpNoise3D(x * freq, y * freq, z * freq) * amp;
  }
  return total;
}

vec3 random3 ( vec3 p ) {
    return fract(sin(vec3(dot(p,vec3(127.1, 311.7, 288.99)),
                          dot(p,vec3(303.1, 183.3, 800.2)),
                          dot(p, vec3(420.69, 655.0,109.21))))
                 *43758.5453);
}

float surflet(vec3  p, vec3 gridPoint) {
    vec3 t2 = abs(p - gridPoint);
    vec3 t;
    t.x = 1.f - 6.f * pow(t2.x, 5.f) + 15.f * pow(t2.x, 4.f) - 10.f * pow(t2.x, 3.f);
    t.y = 1.f - 6.f * pow(t2.y, 5.f) + 15.f * pow(t2.y, 4.f) - 10.f * pow(t2.y, 3.f);
    t.z = 1.f - 6.f * pow(t2.z, 5.f) + 15.f * pow(t2.z, 4.f) - 10.f * pow(t2.z, 3.f);

    vec3 gradient = random3(gridPoint) * 2. - vec3(1.);

    vec3 diff = p - gridPoint;
    float height = dot(diff, gradient);
    return height * t.x * t.y * t.z;
}


float summedPerlin(vec4 p)
{
    float sum = 0.0;
    for(int dx = 0; dx <= 1; ++dx) {
        for (int dy = 0; dy <= 1; ++dy) {
           for (int dz = 0; dz <= 1; ++dz) {
               sum += surflet(vec3(p), floor(vec3(p)) + vec3(dx, dy, dz));
           } 
        }
    }
    
    return sum;
}

/*
TRANSFORMATION FUNCTIONS
*/
#define DEG_TO_RAD 3.141592 / 180.

mat4 inverseRotate(vec3 rotate) { 
    rotate.x = radians(rotate.x);
    rotate.y = radians(rotate.y);
    rotate.z = radians(rotate.z);
    mat4 r_x;
    r_x[0] = vec4(1., 0., 0., 0.);
    r_x[1] = vec4(0., cos(rotate.x), sin(rotate.x), 0.);
    r_x[2] = vec4(0., -sin(rotate.x), cos(rotate.x), 0.);
    r_x[3] = vec4(0., 0., 0., 1.);                            
    mat4 r_y;
    r_y[0] = vec4(cos(rotate.y), 0., -sin(rotate.y), 0.);
    r_y[1] = vec4(0., 1, 0., 0.);
    r_y[2] = vec4(sin(rotate.y), 0., cos(rotate.y), 0.);
    r_y[3] = vec4(0., 0., 0., 1.);
    mat4 r_z;
    r_z[0] = vec4(cos(rotate.z), sin(rotate.z), 0., 0.);
    r_z[1] = vec4(-sin(rotate.z), cos(rotate.z), 0., 0.);
    r_z[2] = vec4(0., 0., 1., 0.);
    r_z[3] = vec4(0., 0., 0., 1.);
    return r_x * r_y * r_z;
}

vec3 rotateX(in vec3 p, float a) {
    a = DEG_TO_RAD * a;
	float c = cos(a);
	float s = sin(a);
	return vec3(p.x, c * p.y - s * p.z, s * p.y + c * p.z);
}

vec3 rotateY(vec3 p, float a) {
    a = DEG_TO_RAD * a;
	float c = cos(a);
	float s = sin(a);
	return vec3(c * p.x + s * p.z, p.y, -s * p.x + c * p.z);
}

vec3 rotateZ(in vec3 p, float a) {
    a = DEG_TO_RAD * a;
	float c = cos(a);
	float s = sin(a);
	return vec3(c * p.x - s * p.y, s * p.x + c * p.y, p.z);
}

float GetBias(float x, float bias)
{
  return (x / ((((1.0/bias) - 2.0)*(1.0 - x))+1.0));
}

/*
SDF FUNCTIONS
*/

float dot2(vec2 v) {
  return dot(v, v);
}

float dot2(vec3 v) {
  return dot(v, v);
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

float opSubtraction( float d1, float d2 ) { return max(-d1,d2); }

float opUnion( float d1, float d2 ) { return min(d1,d2); }

vec3 bendPoint(vec3 p, float k)
{
    float c = cos(k*p.y);
    float s = sin(k*p.y);
    mat2  m = mat2(c,-s,s,c);
    vec3  q = vec3(m*p.xy,p.z);
    return q;
}

float sdCapsule( vec3 queryPos, vec3 a, vec3 b, float r )
{
  vec3 pa = queryPos - a, ba = b - a;
  float h = clamp( dot(pa,ba)/dot(ba,ba), 0.0, 1.0 );
  return length( pa - ba*h ) - r;
}



/*
SDF FORMULAS
*/

float sdBox( vec3 p, vec3 b )
{
  vec3 q = abs(p) - b;
  return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0);
}

float sdCappedCone( vec3 p, float h, float r1, float r2 )
{
  vec2 q = vec2( length(p.xz), p.y );
  vec2 k1 = vec2(r2,h);
  vec2 k2 = vec2(r2-r1,2.0*h);
  vec2 ca = vec2(q.x-min(q.x,(q.y<0.0)?r1:r2), abs(q.y)-h);
  vec2 cb = q - k1 + k2*clamp( dot(k1-q,k2)/dot2(k2), 0.0, 1.0 );
  float s = (cb.x<0.0 && ca.y<0.0) ? -1.0 : 1.0;
  return s*sqrt( min(dot2(ca),dot2(cb)) );
}

float sdCappedCylinder( vec3 p, float h, float r )
{
  vec2 d = abs(vec2(length(p.xz),p.y)) - vec2(h,r);
  return min(max(d.x,d.y),0.0) + length(max(d,0.0));
}


float sdfSphere(vec3 query_position, vec3 position, float radius) {
  return length(query_position - position) - radius;
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

float sdEllipsoid( vec3 p, vec3 r )
{
  float k0 = length(p/r);
  float k1 = length(p/(r*r));
  return k0*(k0-1.0)/k1;
}

float sdTorus( vec3 p, vec2 t )
{
  vec2 q = vec2(length(p.xz)-t.x,p.y);
  return length(q)-t.y;
}

/*
DRAW SDF
*/

//TOWER

float sdTower(vec3 queryPos) {
  // bounding box
  float box = sdBox(queryPos, vec3(2., 6., 2.5));
  if (box > BOX_EPSILON) {
    return box;
  }

  float tower_neck =  sdCappedCone(queryPos, 1.5, 0.6, 0.4);
  float tower_window = sdBox(vec3(vec4(queryPos, 1.0) * inverseRotate(vec3(0., 60., 0.))) + vec3(0., -2.5, 0.0), vec3(1.3, .25, .2));
  float tower_room = sdCappedCone(queryPos + vec3(0., -1.6, 0.), 0.4, 0.4, 1.1);
  float neck_room_blend = opSmoothUnion(tower_neck, tower_room, 1.3);
  float tower_cyl = sdCappedCylinder(queryPos + vec3(0., -2.5, 0.), 1.2, 0.6);
  float tower_subtract = opSubtraction(tower_window, tower_cyl);
  float cyl_room_blend = opSmoothUnion(tower_subtract, neck_room_blend, 0.5);

  float bottom = sdCappedCone(queryPos + vec3(0., 3., 0.), 2., 1.5, 0.48);
  float bottom_2 = sdCappedCone(queryPos + vec3(0., 4.5, 0.), .3, 2., 1.2);
  float bottom_blend = opSmoothUnion(bottom, bottom_2, 1.1);
  float neck_bottom_blend = opSmoothUnion(bottom_blend,tower_neck, 0.01);

  float tower_connect = opSmoothUnion(cyl_room_blend, neck_bottom_blend, 0.5);
  
  return tower_connect;
}

float sdRoof(vec3 queryPos) {
  // bounding box
  float box = sdBox(queryPos + vec3(0., -3.5, 0.), vec3(2., 2.5, 2.5));
  if (box > BOX_EPSILON) {
    return box;
  }
  float tower_roof = sdCappedCone(queryPos + vec3(0., -3.4, 0.), 0.3, 1.6, 0.6);
  float tower_tip = sdCappedCone(queryPos + vec3(0., -4.5, 0.), 1.5, 0.7, 0.01);
  float tower_top = opSmoothUnion(tower_roof, tower_tip, 0.5);
  return tower_top;
}

// TOWER DETAILS

float sdTowerDetails(vec3 queryPos) {
  // bounding box
  float box = sdBox(queryPos + vec3(0., -2. ,0.), vec3(1.5, 1.5, 1.5));
  if (box > BOX_EPSILON) {
    return box;
  }

  float tower_ring_2 = sdTorus(queryPos + vec3(0., -1., 0.0), vec2(0.8, 0.1));
  float tower_ring_1 =  sdTorus(queryPos + vec3(0., -1.9, 0.0), vec2(1.25, 0.1));
  float tower_ring_12 = opUnion(tower_ring_2, tower_ring_1);
  float tower_ring_3 = sdTorus(queryPos + vec3(0., -2.2, 0.0), vec2(1.25, 0.08));
  float tower_ring_123 = opUnion(tower_ring_12, tower_ring_3);
//#define TOWER_DEETS opUnion(TOWER_RING_123, TOWER_CONNECT)
  float tower_chimney = sdBox(vec3(vec4(queryPos, 1.0) * inverseRotate(vec3(0., 60., 0.))) + vec3(-0.1, -3.5, -1.35), vec3(0.1, 0.4, 0.1));
  float tower_side_1 = sdBox(vec3(vec4(queryPos, 1.0) * inverseRotate(vec3(0., 20., 0.))) + vec3(-0.0, -2.6, -1.3), vec3(0.1, 0.7, 0.05));
  float tower_side_connect =  opUnion(tower_ring_123, tower_side_1);
  float tower_chimney_connect = opUnion(tower_side_connect, tower_chimney);

  vec3 tower_diag_base = rotateX(queryPos, -23.);
  float tower_diag_1 = sdBox(rotateZ(rotateY(rotateX(queryPos, -23.), 0.), 0.)  + vec3(-0.0, -1.7, -0.39), vec3(0.1, 0.5, 0.05));
  float tower_diag_2 = sdBox(rotateZ(rotateY(rotateX(queryPos, -28.), 30.), -10.)  + vec3(0.2, -1.7, -0.37), vec3(0.1, 0.5, 0.05));
  float tower_diag_3 = sdBox(rotateZ(rotateY(rotateX(queryPos, -28.), -30.), 10.)  + vec3(-0.2, -1.7, -0.37), vec3(0.1, 0.5, 0.05));
  float tower_d = opUnion(tower_diag_1, tower_diag_2);
  float tower_d1 = opUnion(tower_d, tower_diag_3);

  float tower_d_connect = opUnion(tower_d1, tower_chimney_connect);

  return tower_d_connect;
}

//FLOOR

float sdFloor(vec3 queryPos) {
  // bounding box
  float box = sdBox(queryPos + vec3(0., 5., -2.3), vec3(9., 2., 1.5));
  if (box > BOX_EPSILON) {
    return box;
  }

  float rock_fbm = fbm(queryPos.x / 15., queryPos.y / 15., queryPos.z / 15., 6.);
  float rock_fbm_2 = fbm(queryPos.x / 10., queryPos.y / 10., queryPos.z / 10., 6.);
  float front_rock = sdEllipsoid(vec3(vec4(queryPos + vec3(4., 6., 0.), 1.) * inverseRotate(vec3(0., 0., -10.))), vec3(10., 2., 3.));// + rock_fbm;
  float front_right =  sdEllipsoid(vec3(vec4(queryPos + vec3(-4., 7., 0.), 1.) * inverseRotate(vec3(0., 0., -7.))), vec3(7., 2., 3.));// + rock_fbm;
  float front_floor = opSmoothUnion(front_rock, front_right, 0.5);
  float front_connecting =  sdEllipsoid(vec3(vec4(queryPos + vec3(2., 6., 0.), 1.) * inverseRotate(vec3(0., 0., 10.))), vec3(4., 2., 3.));// + rock_fbm;
  float front_connecting_floor = opSmoothUnion(front_connecting, front_floor, 0.5);
//#define TOWER_FLOOR opSmoothUnion(TOWER_DEETS, FRONT_CONNECTING_FLOOR, 1.5)

  float rock_1 = sdEllipsoid(rotateY(queryPos + vec3(-0.8, 7.5, -0.8), 20.), vec3(1., 1.2, 1.));// + rock_fbm_2;
  float rock_2 = sdEllipsoid(rotateY(queryPos + vec3(1.2, 6.5, -1.2), 20.), vec3(0.6, 1., 0.6));// + rock_fbm_2;
  float rock_c1 = opSmoothUnion(rock_1, rock_2, 0.3);
  float fin_front = opSmoothUnion(rock_c1, front_connecting_floor, 3.1);

  return fin_front;
}


// BACKGROUND

float sdBackground(vec3 queryPos) {
  // bounding box
  float box = sdBox(queryPos + vec3(0., 0., 12.3), vec3(17., 14., 13.5));
  if (box > BOX_EPSILON) {
    return box;
  }
  float rock_fbm = fbm(queryPos.x / 15., queryPos.y / 15., queryPos.z / 15., 6.);
  float wall = sdBox(queryPos + vec3(0., 0., 12.3), vec3(17., 14., 10.5));
  float carveOut = sdCappedCylinder(queryPos + vec3(0., 0, 3.), 3., 10.);
  float fin_wall = opSmoothSubtraction(carveOut, wall, 4.5);
  float carveOut2 = sdCappedCylinder(queryPos + vec3(4., 0, 2.), 3., 10.);
  float fin_wall2 = opSmoothSubtraction(carveOut2, fin_wall, 4.5);
  float carveOut3 = sdCappedCylinder(queryPos + vec3(-6., 0, 2.), 4., 10.);
  float fin_wall3 = opSmoothSubtraction(carveOut3, fin_wall2, 2.5);
  float addOn = sdCappedCylinder(queryPos + vec3(9., 0, 1.), 1., 10.);
  float fin_wall4 = opSmoothUnion(addOn, fin_wall3, 8.5);
  float addOn2 = sdCappedCylinder(queryPos + vec3(-11., 0, 1.), 2., 10.);
  float fin_wall5 = opSmoothUnion(addOn2, fin_wall4, 8.5) + rock_fbm;

  return fin_wall5;

}

//BIRDS

float sdBird(vec3 queryPos, float amp, float y, float z) {

  float xShift = (u_Time * 0.001 * amp - floor(u_Time * 0.001 * amp)) * 30.;
  float yShift = 2. * sin(u_Time / 200.);
  yShift = GetBias(u_Time, yShift);
  vec3 birdTranslate = queryPos - vec3(16., y, z) + vec3(xShift, yShift, 0.);
  // bounding box
  float box = sdBox(birdTranslate, vec3(0.5, 0.5, 0.5));
  if (box > BOX_EPSILON) {
    return box;
  }
  float birdBody = sdEllipsoid(birdTranslate, vec3(0.3, 0.1, 0.081));
  float birdWingBase1 = sdEllipsoid(rotateX(birdTranslate,  -30. * sin(u_Time/ 15.)) + vec3(0.0, 0.0, -0.2), vec3(0.1, 0.06, 0.35)) ;
  float birdWingBase2  = sdEllipsoid(rotateX(birdTranslate, 30. * sin(u_Time/ 15.)) + vec3(0.0, 0.0, 0.2), vec3(0.1, 0.06, 0.35));
  float birdCom1 = opUnion(birdWingBase2, birdWingBase1);
  float birdCom = opSmoothUnion(birdCom1, birdBody, 0.1);
  return birdCom;
}

float sdWaterfall(vec3 queryPos) {
  float waterfall = sdRoundCone(queryPos + vec3(-6., 11., 5.), 0.8, 0.2, 25.);
  return waterfall;
}


float sceneSDF(vec3 queryPos, out int objHit) {

  float x = 1e+6;
  // bounding box
  float t = sdBox(queryPos, vec3(13., 15., 17.));
  if (t <= BOX_EPSILON) {
    t = sdBackground(queryPos); // back wall
    if (t < x) {
      x = t;
      objHit = BACKGROUND;
    }
    t = sdFloor(queryPos); // floor
    if (t < x) {
      x = t;
      objHit = FLOOR;
    }
    t = sdTower(queryPos); // main tower
    if (t < x) {
      x = t;
      objHit = TOWER;
    }
    t = sdTowerDetails(queryPos); // tower details
    if (t < x) {
      x = t;
      objHit = DETAILS;
    }
    t = sdRoof(queryPos); // roof
    if (t < x) {
      x = t;
      objHit = ROOF;
    }
    t = sdBird(queryPos, 6., 2.,  3.);
    if (t < x) {
      x = t;
      objHit = BIRD;
    }
    t = sdBird(queryPos, 5., -2., 4.);
    if (t < x) {
      x = t;
      objHit = BIRD;
    }

    t = sdBird(queryPos, 4., 4., 5.);
    if (t < x) {
      x = t;
      objHit = BIRD;
    }
    t = sdWaterfall(queryPos);
    if (t < x) {
      x = t;
      objHit = WATERFALL;
    }
  } else {
    if (t < x) {
      t = x;
    }
    objHit = -1;
  }
  

  return x;
}

Ray getRay(vec2 uv) {
  Ray r;
  vec3 F = normalize(u_Ref - u_Eye);
  vec3 R = normalize(cross(F, u_Up));
  float len = length(vec3(u_Ref - u_Eye));
  float alpha = FOV / 2.f;
  vec3 V = u_Up * len * tan(alpha);
  float aspect = u_Dimensions.x / u_Dimensions.y;
  vec3 H = R * len * aspect * tan(alpha);
  vec3 p = u_Ref + fs_Pos.x * H + fs_Pos.y * V;
  r.origin = u_Eye;
  r.direction = normalize(p - u_Eye);

  return r;
}

vec3 estimateNormals(vec3 p) {
  vec2 d = vec2(0., EPSILON);
  int obj;
  float x = sceneSDF(p + d.yxx, obj) - sceneSDF(p - d.yxx, obj);
  float y = sceneSDF(p + d.xyx, obj) - sceneSDF(p - d.xyx, obj);
  float z = sceneSDF(p + d.xxy, obj) - sceneSDF(p - d.xxy, obj);

  return normalize(vec3(x, y, z));

}

bool isRayTooLong(vec3 queryPoint, vec3 origin)
{
    return length(queryPoint - origin) > MAX_RAY_Z;
}


Intersection getRaymarchedIntersection(vec2 uv) {
  Intersection intersection;
  float distanceT = 0.0;

  intersection.distance_t = -1.0;
  Ray r = getRay(uv);
  for(int step; step <= MAX_RAY_STEPS; ++step) {
    vec3 queryPoint = r.origin + r.direction * distanceT;
    int objHit;
    #if DIST_LIMIT
    if(isRayTooLong(queryPoint, r.origin)) break;
    #endif
    float sdf = sceneSDF(queryPoint, objHit);
    if(sdf < EPSILON) {
      intersection.distance_t = distanceT;
      intersection.normal = estimateNormals(queryPoint);
      intersection.position = queryPoint;
      intersection.material_id = objHit;
      return intersection;
    }
    distanceT += sdf;
  }
  return intersection;
}

float hardShadow(vec3 dir, vec3 origin) {
    float distanceT = 0.001;
    for(int i = 0; i < MAX_RAY_STEPS; ++i) {
        vec3 queryPoint = origin + dir * distanceT;
        int objHit;
        float m = sceneSDF(queryPoint, objHit);
        if(m < EPSILON) {
            return 0.0;
        }
        distanceT += m;
    }
    return 1.0;
}

float softShadow(vec3 dir, vec3 origin, float min_t, float k) {
    float res = 1.0;
    float t = min_t;
    for(int i = 0; i < MAX_RAY_STEPS; ++i) {
        vec3 queryPoint = origin + dir * t;
        int objHit;
        float m = sceneSDF(queryPoint, objHit);
        if(m < EPSILON) {
            return 0.0;
        }
        res = min(res, k * m / t);
        t += m;
    }
    return res;
}

float fiveTapAO(vec3 p, vec3 n, float k) {
    float aoSum = 0.0;
    for(float i = 0.0; i < 5.0; ++i) {
        float coeff = 1.0 / pow(2.0, i);
        int objHit;
        aoSum += coeff * (i * AO_DIST - sceneSDF(p + n * i * AO_DIST, objHit));
    }
    return 1.0 - k * aoSum;
}

float n21(vec2 p) {
	const vec3 s = vec3(7, 157, 0);
	vec2 h,
	     ip = floor(p);
	p = fract(p);
	p = p * p * (3. - 2. * p);
	h = s.zy + dot(ip, s.xy);
	h = mix(fract(sin(h) * 43.5453), fract(sin(h + s.x) * 43.5453), p.x);
	return mix(h.x, h.y, p.y);
}

float n11(float p) {
	float ip = floor(p);
	p = fract(p);
	vec2 h = fract(sin(vec2(ip, ip + 1.) * 12.3456) * 43.5453);
	return mix(h.x, h.y, p * p * (3. - 2. * p));
}

float wood(vec2 p) {
	p.x *= 71.;
	p.y *= 1.9;
	return n11(n21(p) * 30.);
}


vec3 getSceneColor(vec2 uv) {
    Intersection intersection = getRaymarchedIntersection(uv);
    if (intersection.distance_t > 0.0)
    { 
        float diffuseTerm = dot(intersection.normal, normalize(LIGHT_DIR - intersection.position));
        diffuseTerm = clamp(diffuseTerm, 0.f, 1.f);
        float ambientTerm = 0.0;
        float lightIntensity = diffuseTerm + ambientTerm;
        vec3 view = normalize(u_Eye - intersection.position);
        vec3 H = normalize(view + normalize(LIGHT_DIR));
        float specularIntensity = max(pow(dot(H, normalize(intersection.normal)), 40.), 0.);
        vec3 albedoColour = vec3(1.);

        switch(intersection.material_id) {
          case TOWER:
            float t =  fbm(intersection.position.x / 5., intersection.position.y / 5., intersection.position.z / 5., 6.);
            vec3 brickColour = vec3(0.81, 0.78, 0.59);
            vec3 brickColour1 = vec3(0.91, 0.74, 0.74);
            albedoColour = mix(brickColour, brickColour1, t);
            float foliage =  fbm(intersection.position.x + 109. / 15., intersection.position.y + 392. / 15., intersection.position.z+ 324. / 15., 6.);
            float bias = GetBias(foliage, -intersection.position.y);
            if (intersection.position.y < 1. && foliage > 0.45) {
              vec3 leafColour = vec3(0.33, 0.55, 0.35);
              albedoColour = mix(vec3(0.81, 0.78, 0.59), leafColour, 0.7 * foliage * abs(intersection.position.y));
            }
            break;
          case BIRD:
            albedoColour = vec3(0.81, 0.89, 0.9);
            break;
          case ROOF:
            albedoColour = vec3(0.55, 0.55, 0.88);
            break;
          case DETAILS:
            vec3 woodColour = vec3(0.64, 0.44, 0.21);
            vec3 woodGrain = mix(mix(vec3(.17, .1, .05), vec3(.08, .05, .03), wood(intersection.position.xz)), vec3(.2, .16, .08), .3 * wood(intersection.position.xz * .2));
            albedoColour = mix(woodGrain, woodColour, 0.4);
            break;
          case BACKGROUND:
            float b =  fbm(intersection.position.x / 5., intersection.position.y / 5., intersection.position.z / 5., 6.);
            vec3 rockColour = vec3(0.73, 0.63, 0.49);
            vec3 rockColour2 = vec3(0.85, 0.72, 0.62);
            albedoColour = mix(rockColour, rockColour2, b);

            break;
          case FLOOR:
            float g =  fbm(intersection.position.x, intersection.position.y*2., intersection.position.z*2., 6.);
            vec3 grassColour = vec3(0.51, 0.67, 0.51);
            vec3 grassColour2 = vec3(0.62, 0.75, 0.47);
            albedoColour = mix(grassColour, grassColour2, g);
            break;
          case WATERFALL:
            float w = fbm(intersection.position.x, intersection.position.y, intersection.position.z, 6.);
            vec3 f2 =  intersection.position + w; 
            w = fbm(f2.x, f2.y  + float(u_Time / 10.), f2.z, 6.);
            vec3 waterColour = vec3(0.69, 0.86, 1.);
            vec3 waterColour2 = vec3(0.47, 0.6, 0.86);
            albedoColour = mix(waterColour, waterColour2, w);
            break;
          case -1:
            albedoColour = vec3(1., 0., 1.);
        }
        
        DirectionalLight lights[4];
        lights[0] = DirectionalLight(KEY_LIGHT_POS, KEY_LIGHT_COLOUR);
        lights[1] = DirectionalLight(FILL_LIGHT_POS, FILL_LIGHT_COLOUR);
        lights[2] = DirectionalLight(AMBIENT_LIGHT_POS, AMBIENT_LIGHT_COLOUR);
        lights[3] = DirectionalLight(WATERFALL_LIGHT_POS, WATERFALL_LIGHT_COLOUR);
        vec3 color = albedoColour *
                lights[0].color *
                max(0.0, dot(intersection.normal, lights[0].dir)) *
                softShadow(lights[0].dir, intersection.position, 0.1, SHADOW_HARDNESS);
        for(int i = 1; i < 4; ++i) {
            color += albedoColour *
                     lights[i].color *
                     max(0.0, dot(intersection.normal, lights[i].dir));
                     //shadow(lights[i].dir, p, 0.1);
        }
        
        float ao = fiveTapAO(intersection.position, intersection.normal, FIVETAP_K);
        return color * lightIntensity * ao;
        // return color * intersection.normal;
    }
    return vec3(0.);
}

void main() {
  vec3 col = getSceneColor(fs_Pos);
  out_Col = vec4(col, 1.0);
}
