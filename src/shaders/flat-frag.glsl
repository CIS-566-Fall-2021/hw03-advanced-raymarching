#version 300 es
precision highp float;

// uniform vec3 u_Eye, u_Ref, u_Up;
uniform vec2 u_Dimensions;
uniform float u_Time;

const vec3 u_Eye = vec3(1., 1.2, 4);
const vec3 u_Ref = vec3(0, .2, 0);
const vec3 u_Up = vec3(0, 1, 0);

in vec2 fs_Pos;
out vec4 out_Col;

const int MAX_RAY_STEPS = 100;
const float MAX_RAY_DEPTH = -3.;
const float FOV = 0.25 * 3.141569;
const float EPSILON = .001;
const float BOX_EPSILON = .01;
const vec3 LIGHT = vec3(-2, 3, -5);
const vec3 LIGHT2 = vec3(-3, 3, -4);
const vec3 LIGHT3 = vec3(2, 4, 4);
const vec3 LIGHT4 = vec3(4, -4, -7);
const vec3 LIGHT5 = vec3(-4, -4, 0);
const int TABLE = 0;
const int BOWL = 1;
const int SOUP = 2;
const int NOODLES = 3;
const int EGGwHITE = 4;
const int EGGYOLK = 5;
const int SAUSAGE = 6;
const int MUSHROOM = 7;
const int ENOKI = 8;
const int CHOPSTICKS = 9;
const int HOLDER = 10;
const int MUSHROOM_OUTSIDE = 11;
const int SHADOW_BOX = 12;


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
    vec4 color;
};

Ray getRay(vec2 uv) {
    Ray r;
    vec3 look = normalize(u_Ref - u_Eye);
    vec3 camera_RIGHT = normalize(cross(look, u_Up));
    vec3 camera_UP = cross(camera_RIGHT, look);
    float aspect_ratio = u_Dimensions.x / u_Dimensions.y;
    vec3 screen_vertical = u_Up * length(u_Ref - u_Eye)* tan(FOV/2.); 
    vec3 screen_horizontal = camera_RIGHT * length(u_Ref - u_Eye) * aspect_ratio * tan(FOV/2.);
    vec3 screen_point = (u_Ref + uv.x * screen_horizontal + uv.y * screen_vertical);
    r.origin = u_Eye;
    r.direction = normalize(screen_point - u_Eye);
    return r;
}

mat4 inverseRotateY(float y) {
  y = radians(y);
  mat4 r_y;
  r_y[0] = vec4(cos(y), 0., -sin(y), 0.);
  r_y[1] = vec4(0., 1, 0., 0.);
  r_y[2] = vec4(sin(y), 0., cos(y), 0.);
  r_y[3] = vec4(0., 0., 0., 1.);
  return r_y;
}

// takes in radians (kinda messed up but don't wanna change the values)
mat4 inverseRotateZ(float z) {
  mat4 r_z;
  r_z[0] = vec4(cos(z), sin(z), 0., 0.);
  r_z[1] = vec4(-sin(z), cos(z), 0., 0.);
  r_z[2] = vec4(0., 0., 1., 0.);
  r_z[3] = vec4(0., 0., 0., 1.);
  return r_z;
}

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
    
mat4 inverseScale(vec3 scale) {
    mat4 s;
    s[0] = vec4(scale.x, 0., 0., 0.);
    s[1] = vec4(0., scale.y, 0., 0.);
    s[2] = vec4(0., 0., scale.z, 0.);
	  s[3] = vec4(0., 0., 0., 1.);
    return s;   
}

float sdfSphere(vec3 query_position, vec3 position, float radius) {
    return length(query_position - position) - radius;
}

float dot2( in vec2 v ) { return dot(v,v); }
float dot2( in vec3 v ) { return dot(v,v); }

// h = height, r1 = bottom radius, r2 = top radius
float sdCappedCone(vec3 p, float h, float r1, float r2) {
  vec2 q = vec2( length(p.xz), p.y );
  vec2 k1 = vec2(r2,h);
  vec2 k2 = vec2(r2-r1,2.0*h);
  vec2 ca = vec2(q.x-min(q.x,(q.y<0.0)?r1:r2), abs(q.y)-h);
  vec2 cb = q - k1 + k2*clamp( dot(k1-q,k2)/dot2(k2), 0.0, 1.0 );
  float s = (cb.x<0.0 && ca.y<0.0) ? -1.0 : 1.0;
  return s*sqrt( min(dot2(ca),dot2(cb)) );
}

// ra = radius of cynlinder, rb = roundess of edges, h = height
float sdRoundedCylinder(vec3 p, float ra, float rb, float h) {
  vec2 d = vec2( length(p.xz)-2.0*ra+rb, abs(p.y) - h );
  return min(max(d.x,d.y),0.0) + length(max(d,0.0)) - rb;
}

// a = left end position, b = right end position, r1 = left end radius, r2 = right end radius
float sdRoundCone(vec3 p, vec3 a, vec3 b, float r1, float r2) {
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

// b = dimensions of box
float sdBox(vec3 p, vec3 b) {
  vec3 q = abs(p) - b;
  return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0);
}

float sdCappedCylinder(vec3 p, float h, float r) {
  vec2 d = abs(vec2(length(p.xz),p.y)) - vec2(h,r);
  return min(max(d.x,d.y),0.0) + length(max(d,0.0));
}

float sdHalfEllipsoid(vec3 p, vec3 r) {
  float k0 = length(p/r);
  float k1 = length(p/(r*r));
  return max(k0*(k0-1.0)/k1, p.y);
}

float sdEllipsoid(vec3 p, vec3 r) {
  float k0 = length(p/r);
  float k1 = length(p/(r*r));
  return k0*(k0-1.0)/k1;
}

float sdfHalfSphere(vec3 p, vec3 center, float radius) {
    return max(length(p - center) - radius, p.y);
}

float opSmoothUnion(float d1, float d2, float k) {
    float h = clamp( 0.5 + 0.5*(d2-d1)/k, 0.0, 1.0 );
    return mix( d2, d1, h ) - k*h*(1.0-h); 
}
float opSmoothSubtraction(float d1, float d2, float k) {
    float h = clamp( 0.5 - 0.5*(d2+d1)/k, 0.0, 1.0 );
    return mix( d2, -d1, h ) + k*h*(1.0-h); 
}

vec3 opCheapBend(vec3 p, float k) {
    float c = cos(k*p.y);
    float s = sin(k*p.y);
    mat2  m = mat2(c,-s,s,c);
    vec3  q = vec3(m*p.xy,p.z);
    return q;
}

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

float fbm(float x, float y, float z) {
  float total = 0.;
  float persistence = 0.5f;
  for(float i = 1.; i <= 6.; i++) {
    float freq = pow(2., i);
    float amp = pow(persistence, i);
    total += interpNoise3D(x * freq, y * freq, z * freq) * amp;
  }
  return total;
}

float noise(vec3 p) {
  float f = fbm(p.x, p.y, p.z);
  vec4 pos = vec4(p, 1.0);
  pos += f; 
  return fbm(pos.x - .02*float(u_Time), pos.y - .02*float(u_Time), pos.z);
}

float noiseTable(vec3 p) {
  float f = fbm(p.x, p.y, p.z);
  vec4 pos = vec4(p, 1.0);
  pos += f; 
  return fbm(pos.x, pos.y, pos.z);
}

float bowl(vec3 p) {
  p.x += .5;
  float ridges = 0.;
  if (p.y < -.4) {
    ridges = (sin(50. * p.y) + 1.) * (sin(50. * p.y) + 1.) / 1000.;
  }
  return opSmoothUnion(max(abs(sdCappedCone(p, .65, .65, .89) - .25) - .02, p.y) - ridges,
                      sdRoundedCylinder(p + vec3(0, 1.2, 0), .26, .05, .2), .2);
}

float soup(vec3 p) {
  p.x += .5;
  return max(sdCappedCone(p, .65, .65, .85) - .25, p.y + .18);
}

float chopsticks(vec3 p, out int obj) {
  float box = sdBox(vec3(inverseRotateY(-50.) * vec4(p - vec3(1.8, -1, -.3), 1)), vec3(.4, .22, 1.3));
  if (box > BOX_EPSILON) {
    return box;
  }
  p.y -= .08;
  mat4 invRotate = inverseRotateY(-30.);
  float chopsticks = min(sdRoundCone(p, vec3(1., -.88, -1), vec3(2.6, -1.37, .2), .02 ,.05),
              sdRoundCone(p, vec3(1.1, -.88, -.9), vec3(2.8, -1.37, .2), .02 ,.05));
  p.y -= .06;
  float holder = opSmoothSubtraction( 
                          sdBox(vec3(invRotate * vec4(p - vec3(1.3, -1., -.8), 1)), vec3(.15, .07, .5)) - .05,
                          sdBox(vec3(invRotate * vec4(p - vec3(1.3, -1.2, -.8), 1)), vec3(.3, .15, .2)) - .05, .05);
  if (chopsticks < holder) {
    obj = CHOPSTICKS;
    return chopsticks;
  }
  obj = HOLDER;
  return holder;
}

// lima = left end position of repition block, limb = right end
float enoki(vec3 p, float s, vec3 lima, vec3 limb) {
  vec3 q = p-s*clamp(round(p/s),lima,limb);
  return opSmoothUnion(sdRoundedCylinder(opCheapBend(q, .2), .012, .06, .4),
                      sdCappedCone(vec3(inverseRotateZ(-25.) * vec4(q - vec3(-.06, .5, 0), 1)), .01, .025, .01) - .06, .02);
}

float enoki2(vec3 p, float s, vec3 lima, vec3 limb) {
  vec3 q = p-s*clamp(round(p/s),lima,limb);
  return opSmoothUnion(sdRoundedCylinder(opCheapBend(q, -.1), .01, .04, .3),
                      sdCappedCone(vec3(inverseRotateZ(15.) * vec4(q - vec3(0.02, .35, 0), 1)), .005, .008, .004) - .04, .01);
}

float enoki3(vec3 p, float s, vec3 lima, vec3 limb) {
  vec3 q = p-s*clamp(round(p/s),lima,limb);
  return opSmoothUnion(sdRoundedCylinder(opCheapBend(q, -.1), .01, .04, .3),
                      sdCappedCone(vec3(inverseRotateZ(15.) * vec4(q - vec3(0.02, .35, 0), 1)), .005, .008, .004) - .04, .01);
}

float enokis(vec3 p) {
  p.x += .01;
  p.z += .08;
  float box = sdBox(vec3(inverseRotateY(-50.) * vec4(p - vec3(-.95, .05, -.4), 1)), vec3(.5, .37, .4));
  if (box > BOX_EPSILON) {
    return box;
  }
  p = vec3(inverseRotate(vec3(50, -60, 0)) * vec4(p - vec3(-.93, -.05, -.6), 1));
  return min(min(enoki(vec3(inverseRotate(vec3(0, 0, -5)) * vec4(p - vec3(-.05, -.1, 0), 1)), .3, vec3(-1, 0, 0), vec3(1, 0, 0)), 
              enoki2(vec3(inverseRotate(vec3(5, 3, 12)) * vec4(p - vec3(-.06, -.03,.05), 1)), .2, vec3(-2., 0, .5), vec3(1., 0, .5))),
              enoki3(vec3(inverseRotate(vec3(12, 15, -2)) * vec4(p - vec3(-.02, -.2, 0), 1)), .14, vec3(-3., 0, 1.), vec3(2., 0, 1.)));
}

// 2 egg whites
float eggWhite(vec3 p) {
  p.y += .03;
  float box = min(sdBox(p - vec3(-.08, -.07, -.1), vec3(.3, .15, .2)),
                  sdBox(vec3(inverseRotateY(18.) * vec4(p - vec3(-.9, -.15, .24),1)), vec3(.32, .15, .25)));
  if (box > BOX_EPSILON) {
    return box;
  }
  vec3 a = vec3(inverseRotate(vec3(-20, -10, 0)) * vec4(p - vec3(-.07, .02, -.1), 1));
  float egg1 = sdHalfEllipsoid(a, vec3(.3, .25, .2));
  // left
  vec3 b = vec3(inverseRotate(vec3(-5, 10, 0)) * vec4(p - vec3(-.9, -.04, .2), 1));
  float egg2 = sdHalfEllipsoid(b, vec3(.3, .25, .2));
  return min(egg1, egg2);
}

// 2 egg yolks
float eggYolk(vec3 p) {
  p.y += .03;
  p.y += .02;
  float box = min(sdBox(p - vec3(-.05, 0, -.05), vec3(.2, .1, .2)),
                sdBox(vec3(inverseRotateY(20.) * vec4(p - vec3(-.92, -.1, .25),1)), vec3(.2, .1, .2)));
  if (box > BOX_EPSILON) {
    return box;
  }
  float f = fbm((p.x + 2.4)*.7, p.y*.7, p.z*.7);
  p.y -= f * f/ 8.;
  p.y += .046;
  vec3 a = vec3(inverseRotate(vec3(-20, -10, 0)) * vec4(p - vec3(-.05, .04, -.1), 1));
  float egg1 = sdRoundedCylinder(a, .09, .03, .005);
  vec3 b = vec3(inverseRotate(vec3(-5, 10, 0)) * vec4(p - vec3(-.9, -.02, .2), 1));
  float egg2 = sdRoundedCylinder(b, .09, .03, .005);
  return min(egg1, egg2);
}

float table(vec3 p, bool normal) {
    p.y += 1.45;
    if (normal) {
      p.y += noiseTable(p * .5) / 27.;
    }
    return sdBox(p, vec3(6, .2, 3));
}

float noodle(vec3 p) {
  float box = sdBox(vec3(inverseRotateY(45.) * vec4(p - vec3(-.54, -.15, 0), 1)), vec3(.8, .06, .8));
  if (box > BOX_EPSILON) {
    return box;
  }
  float y = radians(50.);
  mat4 r_z;
  r_z[0] = vec4(cos(y), sin(y), 0., 0.);
  r_z[1] = vec4(-sin(y), cos(y), 0., 0.);
  r_z[2] = vec4(0., 0., 1., 0.);
  r_z[3] = vec4(0., 0., 0., 1.);

  float s = .2;
  vec3 a = vec3(inverseRotate(vec3(95, 50, 0)) * vec4(p - vec3(-.52, -.21, 0), 1));
  a = a-s*clamp(round(a/s),vec3(-2, 0, 0),vec3(3, 0, 0));
  a.x += .02 * cos(15.*a.y);
  a.z -= .1 * cos(2.*a.y - .7);
  float group1 = sdRoundedCylinder(a, .013, .1, .75);

  s = .15;
  vec3 b = vec3(inverseRotate(vec3(95, 30, 0)) * vec4(p - vec3(-.43, -.23, 0), 1));
  b = b-s*clamp(round(b/s),vec3(-2, 0, 0),vec3(3, 0, 0));
  b.x += .02 * cos(12.*b.y);
  b.z -= .09 * cos(2.*b.y - .7);
  float group2 = sdRoundedCylinder(b, .013, .1, .8);
  return min(group1, group2);
}

float sausages(vec3 p) {
  float box = sdBox(vec3(inverseRotateY(-80.) * vec4(p - vec3(-1.3, .03, 0), 1)), vec3(.5, .3, .1));
  if (box > BOX_EPSILON) {
    return box;
  }
  vec3 a = vec3(inverseRotate(vec3(90, -80, -20)) * inverseScale(vec3(1, .7 , 1)) * vec4(p - vec3(-1.35, 0, .2), 1));
  float front = sdCappedCylinder(a, .2, .02) - .02;
  vec3 b = vec3(inverseRotate(vec3(100, -60, 0)) * inverseScale(vec3(.7, 1. , 1)) * vec4(p - vec3(-1.35, 0, -.08), 1));
  float back = sdCappedCylinder(b, .18, .01) - .02;
  return min(front, back);
}

float mushroom(vec3 p, out int obj) {
  p.z += .05;
  float box = sdBox(p - vec3(.05, .12, -.5), vec3(.2, .3, .25));
  if (box > BOX_EPSILON) {
    return box;
  }
  p.x -= .2;
  p.y += .05;
  p.z += .65;
  vec4 rotated = inverseRotate(vec3(10, -70, 15)) * vec4(p, 1); 
  vec4 rotated2 = inverseRotate(vec3(20, -120, 15)) * vec4(p, 1); 
  float ellipsoid = sdEllipsoid(p - vec3(.05, .2, .02), vec3(.3, .04, .3));
  float cone = sdCappedCone(p - vec3(0, .3, 0), .002, .3, .3) - .12;
  float top = opSmoothSubtraction(ellipsoid,
                            max(max(cone, rotated2.x), rotated.z), .02);
  if (opSmoothSubtraction(ellipsoid, abs(cone) - .008, .02) < EPSILON) {
    obj = MUSHROOM_OUTSIDE;
  } else {
    obj = MUSHROOM;
  }
  return opSmoothUnion(sdBox(vec3(rotated - vec4(-.06, .07, -.11, 0)), vec3(.0005, .25, .08)) - .03, 
                      top, .01); 
}

float mushroom2(vec3 p, out int objHit) {
  p.z +=.02;
  vec3 temp = vec3(inverseRotateY(-20.) * vec4(p - vec3(-.32, .3, -.55), 1));
  float box = sdBox(temp, vec3(.25, .5, .15));
  if (box > BOX_EPSILON) {
    return box;
  }
  p = vec3(inverseRotate(vec3(10, -20, -10)) * vec4(p - vec3(-.4, .3, -.7), 1));
  float top = sdCappedCone(p, .002, .15, .1) - .07;
  if (top < EPSILON) {
    objHit = MUSHROOM_OUTSIDE;
  } else {
    objHit = MUSHROOM;
  }
  return opSmoothUnion(top,
                    sdBox(p - vec3(0, -.3, 0), vec3(.1, .3, .04)) - .03, .05);
}

float GetBias(float time, float bias) {
  return (time / ((((1.0/bias) - 2.0)*(1.0 - time))+1.0));
}

float GetGain(float time, float gain) {
  if(time < 0.5)
    return GetBias(time * 2.0,gain)/2.0;
  else
    return GetBias(time * 2.0 - 1.0,1.0 - gain)/2.0 + 0.5;
}

float smoke(vec3 p, vec3 dir, out bool hit) {
  float box = sdBox(p - vec3(.2, 1, 0), vec3(.8, 1, 1));
  if (box > EPSILON) {
    return box;
  }
  p.y *= .7;
  p.y += .1;
  float d = sdfSphere(p, vec3(0, 1, 0), 1.);
  float t = 0.01;
  if (d < EPSILON) {
    float sum = 0.;
    for (int step = 0; step < 200; step++) {
      p = p + dir * t;
      if (sdfSphere(p, vec3(0, 1, 0), 1.) > EPSILON) {
        break;
      }
      float den = noise(p);
      sum += clamp((den * den * den) / 350., 0. , .01);
      t += .001;
    }
    hit = true;
    sum = mix(0., sum * sum * 30., GetGain(1. - abs(p.x), .6));
    return clamp(20. * sum, 0.0, 1.0);    
  } else {
    hit = false;
    return d;
  }
}

float sceneSDF(vec3 p, out int objHit, bool normal) {
  float x = 10000000.;
  float t = sdBox(p - vec3(-.48, -.4, -.02), vec3(1.1, .8, 1.2));
  if (t <= BOX_EPSILON) {
    t = bowl(p);
    if (t < x) {
      x = t;
      objHit = BOWL;
    }
    t = enokis(p);
    if (t < x) {
      x = t;
      objHit = ENOKI;
    }
    t = eggWhite(p);
    if (t < x) {
      x = t;
      objHit = EGGwHITE;
    }
    t = eggYolk(p);
    if (t < x) {
      x = t;
      objHit = EGGYOLK;
    }
    t = soup(p);
    if (t < x) {
      x = t;
      objHit = SOUP;
    }
    t = noodle(p);
    if (t < x) {
      x = t;
      objHit = NOODLES;
    }
    t = sausages(p);
    if (t < x) {
      x = t;
      objHit = SAUSAGE;
    }
    int temp;
    t = mushroom(p, temp);
    if (t < x) {
      x = t;
      objHit = temp;
    }
    t = mushroom2(p, temp);
    if (t < x) {
      x = t;
      objHit = temp;
    }
  } else {
    if (t < x)
      x = t;
  }
  int temp;
  t = chopsticks(p, temp);
  if (t < x) {
    x = t;
    objHit = temp;
  }
  t = table(p, normal);
  if (t < x) {
    x = t;
    objHit = TABLE;
  }
  t = sdBox(p - vec3(0, 1, -4.7), vec3(7, .5, 1));
  if (t < x) {
    x = t;
    objHit = SHADOW_BOX;
  }
  return x;
}

vec3 normal(vec3 p) {
  vec2 q = vec2(0, EPSILON);
  int obj;
  return normalize(vec3(sceneSDF(p + q.yxx, obj, true) - sceneSDF(p - q.yxx, obj, true),
              sceneSDF(p + q.xyx, obj, true) - sceneSDF(p - q.xyx, obj, true),
              sceneSDF(p + q.xxy, obj, true) - sceneSDF(p - q.xxy, obj, true)));
}

float shadow(vec3 dir, vec3 origin) {
  float res = 1.0;
  float k = 50.0;
  float t = 0.01;
  for(int i = 0; i < 60; ++i) {
      int obj;
      float m = sceneSDF(origin + t * dir, obj, false);
      if(m < EPSILON) {
          return 0.0;
      }
      res = min(res, k * m / t);
      t += m;
  }
  return res;
  // return 1.;
}

Intersection getRaymarchedIntersection(vec2 uv) {
    Intersection intersection;    
    intersection.distance_t = -1.0;
    Ray r = getRay(uv);
    float t = 0.0;
    for (int step = 0; step < MAX_RAY_STEPS; ++step) {
      vec3 queryPoint = r.origin + r.direction * t;
      if (queryPoint.z < MAX_RAY_DEPTH) {
        return intersection;
      }
      int objHit;
      float currentDist = sceneSDF(queryPoint, objHit, false);
      if (currentDist < EPSILON) {
        intersection.distance_t = t;
        intersection.normal = normal(queryPoint);
        intersection.position = queryPoint;
        intersection.material_id = objHit;
        return intersection;
      }
      t += currentDist;
    }
    return intersection;
}

Intersection getRaymarchedIntersectionSmoke(vec2 uv) {
    Intersection intersection;    
    intersection.distance_t = -1.0;
    Ray r = getRay(uv);
    float t = 0.0;
    for (int step = 0; step < MAX_RAY_STEPS; ++step) {
      vec3 queryPoint = r.origin + r.direction * t;
      if (queryPoint.z < MAX_RAY_DEPTH) {
        return intersection;
      }
      bool hit;
      float currentDist = smoke(queryPoint, r.direction, hit);
      if (hit) {
        intersection.distance_t = currentDist;
        intersection.position = queryPoint;
        return intersection;
      }
      t += currentDist;
    }
    return intersection;
}

vec3 contrast(vec3 rgb, float c) {
    float f = 259.0 * (c + 255.0) / (255.0 * (259.0 - c));
    return clamp(f * (rgb - vec3(0.5)) + vec3(0.5), 0.0, 1.0);
}

vec4 getSceneColor(vec2 uv) {
    vec3 albedo = vec3(0);
    vec3 color = vec3(0);
    Intersection intersection = getRaymarchedIntersection(uv);
    if (intersection.distance_t > 0.0) { 
      float diffuseTerm = clamp(dot(intersection.normal, normalize(LIGHT - intersection.position)), 0., 1.);
      float lightIntensity = diffuseTerm;

      float diffuseTerm2 = clamp(dot(intersection.normal, normalize(LIGHT2 - intersection.position)), 0., 1.);
      float lightIntensity2 = diffuseTerm2;

      float diffuseTerm3 = clamp(dot(intersection.normal, normalize(LIGHT3 - intersection.position)), 0., 1.);
      float lightIntensity3 = diffuseTerm3;

      float diffuseTerm4 = clamp(dot(intersection.normal, normalize(LIGHT4 - intersection.position)), 0., 1.);
      float lightIntensity4 = diffuseTerm4;
      
      vec3 view = normalize(u_Eye - intersection.position);
      vec3 H = normalize(view + normalize(LIGHT));
      float specularIntensity = max(pow(dot(H, normalize(intersection.normal)), 5.), 0.) / 2.;
      vec3 H2 = normalize(view + normalize(LIGHT4));
      float specularIntensity2 = max(pow(dot(H2, normalize(intersection.normal)), 5.), 0.) / 1.2;
      vec3 H3 = normalize(view + normalize(LIGHT5));
      float specularIntensity3 = max(pow(dot(H3, normalize(intersection.normal)), 5.), 0.);
      
      switch(intersection.material_id) {
        case TABLE:
          albedo = vec3(.104, .109, .115) + specularIntensity / 2.;
          break;
        case EGGwHITE:
          albedo = vec3(1);
          albedo /= 1.4;
          break;
        case EGGYOLK:
          albedo = vec3(.99, .76, .07);
          albedo /= 1.4;
          break;
        case NOODLES:
          albedo = vec3(.99, .92, .76);
          albedo /= 1.4;
          break;
        case BOWL:
          albedo = vec3(.004, .009, .03) + specularIntensity + specularIntensity2 + specularIntensity3;
          break;
        case SAUSAGE:
          float f =  fbm(intersection.position.x*3.5 - 2.5, intersection.position.y*3.5, intersection.position.z*3.5);
          albedo = mix(vec3(.85, .3176, .035), vec3(.9, .57, .3), (f * 2.)) + specularIntensity;
          albedo /= 1.4;
          break;
        case SOUP:
          albedo = vec3(.7, .6, .5);
          albedo /= 1.4;
          break;
        case MUSHROOM:
          albedo = vec3(.72, .65, .533);
          albedo /= 1.4;
          break;
        case MUSHROOM_OUTSIDE:
          albedo = vec3(.64, .51, .39);
          albedo /= 1.4;
          break; 
        case ENOKI:
          albedo = vec3(1, .98, .89);
          albedo /= 1.4;
          break;
        case CHOPSTICKS:
          f =  fbm(intersection.position.x*5., intersection.position.y*5., intersection.position.z*5.);
          albedo = vec3(.36, .3, .266) * (1. - f / 4.);
          albedo *= 1.4;
          break;
        case HOLDER:
          f =  fbm(intersection.position.x, intersection.position.y, intersection.position.z);
          albedo = vec3(.62, .54, .45) * (1. - f / 4.);
          albedo /= 1.4;
          break;
        case SHADOW_BOX:
          albedo = vec3(0);
      }
      color = albedo * lightIntensity3 * .9;
      albedo /= 2.;
      color += albedo * lightIntensity * .9 * shadow(normalize(LIGHT - intersection.position), intersection.position);
      color += albedo * lightIntensity2 * .9 * shadow(normalize(LIGHT2 - intersection.position), intersection.position);
      color = pow(color, vec3(.72));
      color = contrast(color, 120.);
    }
    Intersection smoke = getRaymarchedIntersectionSmoke(uv);
    if (smoke.distance_t > 0.0) {
      return vec4(color, 1. - (smoke.distance_t));
    }
    return vec4(color, 1);
}

void main() {
  // Normalized pixel coordinates (from 0 to 1)
  vec2 uv = fs_Pos;
    
  vec4 col = getSceneColor(uv);
  
  // Output to screen
  out_Col = col;
  
  // out_Col = vec4(0.5 * (fs_Pos + vec2(1.0)), 0.5 * (sin(u_Time * 3.14159 * 0.01) + 1.0), 1.0);
}
