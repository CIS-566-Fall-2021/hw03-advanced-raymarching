#version 300 es
precision highp float;

uniform vec3 u_Eye, u_Ref, u_Up;
uniform vec2 u_Dimensions;
uniform float u_Time;

in vec2 fs_Pos;
out vec4 out_Col;

#define DEG_TO_RAD 3.14159 / 180.0
// Optimization
const int RAY_STEPS = 256;
#define MAX_RAY_Z 40.0;

// Key light
#define LIGHT_POS vec3(-8.0, 30.0, -8.0)
// Fill light
#define SKY_FILL_LIGHT_COLOR vec3(0.2, 0.55, 0.65) * 0.2
#define SKY_FILL_LIGHT_DIR vec3(0.0, 1.0, 0.0)
// Fake global illumination light
#define SUN_AMBIENT_LIGHT_COLOR vec3(0.6, 0.6, 0.2) * 0.2
#define SUN_AMBIENT_LIGHT_DIR vec3(-8.0, 0.0, -8.0)

// Structs
struct Ray {
    vec3 origin;
    vec3 direction;
};

struct Intersection {
    float t;
    vec3 color;
    vec3 p;
    int object;
};

////////// GEOMETRY //////////
// Podium
#define CENTER_TRI_SDF triangularPrism(rotateX(pos + vec3(0.0, 0.0, 0.0), -75.0), vec2(8.0, 1.0))
#define MIDDLE_TRI_SDF triangularPrism(rotateX(pos + vec3(0.0, -0.25, 0.0), -75.0), vec2(7.0, 1.0))
#define SWORD_HOLDER_SDF triangularPrism(rotateX(pos + vec3(0.0, -0.5, 0.0), 105.0), vec2(2.0, 1.0))

// Sword
#define SWORD_BLADE_BOTTOM_SDF box(pos + vec3(0.0, -2.3, 0.5), vec3(0.25, 1.5, 0.03))
#define SWORD_BLADE_TOP_SDF box(pos + vec3(0.0, -4.0, 0.5), vec3(0.15, 0.5, 0.03))
#define SWORD_GUARD_SDF triangularPrism(rotateZ(pos + vec3(0.0, -4.9, 0.5), 180.0), vec2(0.35, 0.05))
#define SWORD_HILT_SDF capsule(pos + vec3(0.0, -5.4, 0.5), vec3(0.0, 0.5, 0.04), vec3(0.0, -0.3, 0.04), 0.05)
#define SWORD_HILT2_SDF box(pos + vec3(0.0, -4.8, 0.5), vec3(0.15, 0.05, 0.03))
#define SWORD_GEM_SDF capsule(pos + vec3(0.0, -4.6, 0.0), vec3(0.0, 0.2, -0.55), vec3(0.0, -0.1, -0.55), 0.08)
#define SWORD_LEFT_WING_SDF box(rotateZ(pos + vec3(0.25, -4.7, 0.5), -60.0), vec3(0.1, 0.5, 0.05))
#define SWORD_RIGHT_WING_SDF box(rotateZ(pos + vec3(-0.25, -4.7, 0.5), 60.0), vec3(0.1, 0.5, 0.05))
#define SWORD_LEFT_WING_END_SDF triangularPrism(rotateZ(pos + vec3(0.68, -4.75, 0.5), 15.0), vec2(0.26, 0.05))
#define SWORD_RIGHT_WING_END_SDF triangularPrism(rotateZ(pos + vec3(-0.68, -4.75, 0.5), -15.0), vec2(0.26, 0.05))
#define SWORD_END_SDF box(rotateZ(pos + vec3(0.0, -6.0, 0.5), 45.0), vec3(0.15, 0.15, 0.05))
#define SWORD_QUAD_SDF box(rotateZ(pos + vec3(0.0, -3.8, 0.5), 45.0), vec3(0.22, 0.22, 0.03))

// Steps
#define TOP_STEP_SDF roundBox(rotateX(rotateZ(pos + vec3(0.4, 1.95, 4.0), 2.0), 3.0), vec3(4.2, 1.0, 0.5), 0.25)
#define TOP_STEP_CONNECTOR_SDF roundedCylinder(rotateX(pos + vec3(-3.5, 2.3, 4.5), 3.0), 0.5, 0.7, 0.5)
#define MID_STEP_SDF roundBox(rotateX(rotateY(pos + vec3(0.0, 2.9, 4.8), -8.0), 3.0), vec3(4.2, 1.0, 0.5), 0.25)
#define BOT_STEP_SDF roundBox(rotateX(pos + vec3(0.4, 3.1, 5.2), 3.0), vec3(3.4, 0.4, 1.2), 0.25)
#define STEPS_SDF smoothBlend(TOP_STEP_SDF, smoothBlend(TOP_STEP_CONNECTOR_SDF, smoothBlend(MID_STEP_SDF, BOT_STEP_SDF, 0.1), 0.25), 0.25)

// Front stones
#define LEFT_FRONT_STONE_SDF roundBox(rotateX(pos + vec3(-7.5, 2.6, 4.0), 1.0), vec3(2.5, 1.5, 1.5), 0.2)
#define RIGHT_FRONT_STONE_SDF roundBox(rotateX(pos + vec3(7.5, 2.6, 4.0), 1.0), vec3(2.5, 1.5, 1.5), 0.5)

// Floor
#define FLOOR_SDF plane(rotateX(pos + vec3(0.0, 1.6, 0.0), 5.0), vec4(0.0, 1.0, 0.0, 1.0))

// Background elements
#define BACK_BOTTOM_STEP_SDF roundBox(pos + vec3(0.0, -1.0, -20.0), vec3(7.0, 4.0, 1.5), 0.25)
#define BACK_TOP_STEP_SDF roundBox(pos + vec3(0.0, -5.0, -24.0), vec3(4.0, 4.0, 1.5), 0.25)
#define FLOATING_ROCK_SDF ellipsoid(pos + vec3(0.0, -23.0, -24.0) + vec3(0.0, 5.0, 0.0) * bias(0.8f, cos(u_Time / 20.f)), vec3(4.0, 8.0, 4.0) + vec3(0.5))
////////// GEOMETRY ENDS //////////

////////// MATERIAL IDS //////////
#define CENTER_TRI 0
#define MIDDLE_TRI 1
#define SWORD_HOLDER 2
#define SWORD_BLADE_BOTTOM 3
#define SWORD_BLADE_TOP 4
#define SWORD_QUAD 5
#define SWORD_GUARD 6
#define SWORD_HILT 7
#define SWORD_HILT2 8
#define SWORD_END 9
#define SWORD_LEFT_WING 10
#define SWORD_RIGHT_WING 11
#define SWORD_LEFT_WING_END 12
#define SWORD_RIGHT_WING_END 13
#define SWORD_GEM 14
#define STEPS 15
#define LEFT_FRONT_STONE 16
#define RIGHT_FRONT_STONE 17
#define FLOOR 18
#define BACK_BOTTOM_STEP 19
#define BACK_TOP_STEP 20
#define FLOATING_ROCK 21
////////// MATERIAL IDS END //////////

////////// SDFS //////////
float sphere(vec3 p, float s) {
  return length(p) - s;
}

float box(vec3 p, vec3 b) {
  return length(max(abs(p) - b, 0.0));
}

float plane(vec3 p, vec4 n) {
  return dot(p, n.xyz) + n.w;
}

float triangularPrism(vec3 p, vec2 h) {
  vec3 q = abs(p);
  return max(q.z - h.y, max(q.x * 0.866025 + p.y * 0.5, -p.y) - h.x * 0.5);
}

float roundBox(vec3 p, vec3 b, float r)
{
  vec3 q = abs(p) - b;
  return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0) - r;
}

float roundedCylinder(vec3 p, float ra, float rb, float h) {
  vec2 d = vec2(length(p.xz) - 2.0 * ra + rb, abs(p.y) - h);
  return min(max(d.x, d.y), 0.0) + length(max(d, 0.0)) - rb;
}

float roundCone(vec3 p, float r1, float r2, float h) {
  vec2 q = vec2(length(p.xz), p.y);
    
  float b = (r1 - r2) / h;
  float a = sqrt(1.0 - b * b);
  float k = dot(q, vec2(-b, a));
    
  if(k < 0.0) return length(q) - r1;
  if(k > a * h) return length(q - vec2(0.0, h)) - r2;
        
  return dot(q, vec2(a, b)) - r1;
}

float capsule( vec3 p, vec3 a, vec3 b, float r ) {
  vec3 pa = p - a, ba = b - a;
  float h = clamp(dot(pa, ba)/dot(ba, ba), 0.0, 1.0);
  return length(pa - ba * h) - r;
}

float verticalCapsule(vec3 p, float h, float r) {
  p.y -= clamp(p.y, 0.0, h);
  return length(p) - r;
}

float ellipsoid(vec3 p, vec3 r) {
  float k0 = length(p / r);
  float k1 = length(p / (r * r));
  return k0 * (k0 - 1.0) / k1;
}

float smoothBlend(float sdf1, float sdf2, float k) {
    float h = clamp(0.5f + 0.5f * (sdf2 - sdf1) / k, 0.0f, 1.0f);
    return mix(sdf2, sdf1, h) - k * h * (1.0f - h);
}
////////// SDFS END //////////

////////// TRANSFORMATIONS //////////
// Rotate a-degrees along the X-axis
vec3 rotateX(vec3 p, float a) {
    a = DEG_TO_RAD * a;
    return vec3(p.x, cos(a) * p.y + -sin(a) * p.z, sin(a) * p.y + cos(a) * p.z);
}

// Rotate a-degrees along the Y-axis
vec3 rotateY(vec3 p, float a) {
    a = DEG_TO_RAD * a;
    return vec3(cos(a) * p.x + sin(a) * p.z, p.y, -sin(a) * p.x + cos(a) * p.z);
}

// Rotate a-degrees along the Z-axis
vec3 rotateZ(vec3 p, float a) {
    a = DEG_TO_RAD * a;
    return vec3(cos(a) * p.x + -sin(a) * p.y, sin(a) * p.x + cos(a) * p.y, p.z);
}
////////// TRANSFORMATIONS END //////////

////////// TOOLBOX FUNCTIONS //////////
float bias(float b, float t) {
  return pow(t, log(b) / log(0.5f));
}

float gain(float g, float t) {
  if (t < 0.5f) {
    return bias(1.f - g, 2.f * t) / 2.f;
  } else {
    return 1.f - bias(1.f - g, 2.f - 2.f * t);
  }
}
////////// TOOLBOX FUNCTIONS END //////////


////////// NOISE FUNCTIONS //////////
vec3 noise3D(vec3 p) {
    float val1 = fract(sin((dot(p, vec3(127.1, 311.7, 191.999)))) * 43758.5453);

    float val2 = fract(sin((dot(p, vec3(191.999, 127.1, 311.7)))) * 3758.5453);

    float val3 = fract(sin((dot(p, vec3(311.7, 191.999, 127.1)))) * 758.5453);

    return vec3(val1, val2, val3);
}

vec3 interpNoise3D(float x, float y, float z) {
    int intX = int(floor(x));
    float fractX = fract(x);
    int intY = int(floor(y));
    float fractY = fract(y);
    int intZ = int(floor(z));
    float fractZ = fract(z);

    vec3 v1 = noise3D(vec3(intX, intY, intZ));
    vec3 v2 = noise3D(vec3(intX + 1, intY, intZ));
    vec3 v3 = noise3D(vec3(intX, intY + 1, intZ));
    vec3 v4 = noise3D(vec3(intX + 1, intY + 1, intZ));

    vec3 v5 = noise3D(vec3(intX, intY, intZ + 1));
    vec3 v6 = noise3D(vec3(intX + 1, intY, intZ + 1));
    vec3 v7 = noise3D(vec3(intX, intY + 1, intZ + 1));
    vec3 v8 = noise3D(vec3(intX + 1, intY + 1, intZ + 1));

    vec3 i1 = mix(v1, v2, fractX);
    vec3 i2 = mix(v3, v4, fractX);

    vec3 i3 = mix(i1, i2, fractY);

    vec3 i4 = mix(v5, v6, fractX);
    vec3 i5 = mix(v7, v8, fractX);

    vec3 i6 = mix(i4, i5, fractY);

    vec3 i7 = mix(i3, i6, fractZ);

    return i7;
}

vec3 fbm(float x, float y, float z) {
    vec3 total = vec3(0.f, 0.f, 0.f);

    float persistence = 0.5f;
    int octaves = 6;

    for(int i = 1; i <= octaves; i++)
    {
        float freq = pow(2.f, float(i));
        float amp = pow(persistence, float(i));

        total += interpNoise3D(x * freq, y * freq, z * freq) * amp;
    }

    return total;
}

vec3 random3(vec3 p) {
    return fract(sin(vec3(dot(p,vec3(127.1, 311.7, 147.6)),
                          dot(p,vec3(269.5, 183.3, 221.7)),
                          dot(p, vec3(420.6, 631.2, 344.2))
                    )) * 43758.5453);
}

float surflet(vec3 p, vec3 gridPoint) {
    vec3 t2 = abs(p - gridPoint);
    vec3 t = vec3(1.0) - 6.0 * pow(t2, vec3(5.0)) + 15.0 * pow(t2, vec3(4.0)) - 10.0 * pow(t2, vec3(3.0));
    vec3 gradient = random3(gridPoint) * 2.0 - vec3(1.0);
    vec3 diff = p - gridPoint;
    float height = dot(diff, gradient);
    return height * t.x * t.y * t.z;
}

float perlin(vec3 p) {
  float surfletSum = 0.0;
  for(int dx = 0; dx <= 1; ++dx) {
    for(int dy = 0; dy <= 1; ++dy) {
      for(int dz = 0; dz <= 1; ++dz) {
        surfletSum += surflet(p, floor(p) + vec3(dx, dy, dz));
      }
    }
  }
  return surfletSum;
}
////////// NOISE FUNCTIONS END //////////

////////// COLOR FUNCTIONS //////////
vec3 rgb(vec3 color) {
    return vec3(color.x / 255.0, color.y / 255.0, color.z / 255.0);
}

vec3 cosinePalette(vec3 a, vec3 b, vec3 c, vec3 d, float t) {
    return a + b * cos(6.2831 * (c * t + d));
}
////////// COLOR FUNCTIONS END //////////

////////// RAY MARCHING //////////
Ray raycast(vec2 uv) {
  Ray r;
  
  vec3 look = normalize(u_Ref - u_Eye);
  vec3 right = normalize(cross(look, u_Up));
  vec3 up = cross(right, look);

  float len = length(u_Ref - u_Eye);
  float aspectRatio = u_Dimensions.x / u_Dimensions.y;
  float fov = 90.f;
  float alpha = fov / 2.f;

  vec3 screenVertical = up * len * tan(alpha);
  vec3 screenHorizontal = right * len * aspectRatio * tan(alpha);
  vec3 screenPoint = u_Ref + uv.x * screenHorizontal + uv.y * screenVertical;

  r.origin = u_Eye;
  r.direction = normalize(screenPoint - u_Eye);
  return r;
}

bool isRayTooLong(vec3 queryPoint, vec3 origin) {
    return length(queryPoint - origin) > MAX_RAY_Z;
}

float findClosestObject(vec3 pos, vec3 lightPos) {
    float t = CENTER_TRI_SDF;
    t = min(t, SWORD_HOLDER_SDF);
    t = min(t, SWORD_BLADE_BOTTOM_SDF);
    t = min(t, SWORD_BLADE_TOP_SDF);
    t = min(t, SWORD_GUARD_SDF);
    t = min(t, SWORD_HILT_SDF);
    t = min(t, SWORD_QUAD_SDF);
    t = min(t, SWORD_END_SDF);
    t = min(t, SWORD_LEFT_WING_SDF);
    t = min(t, SWORD_RIGHT_WING_SDF);
    t = min(t, SWORD_LEFT_WING_END_SDF);
    t = min(t, SWORD_RIGHT_WING_END_SDF);
    t = min(t, SWORD_GEM_SDF);
    t = min(t, SWORD_HILT2_SDF);
    t = min(t, STEPS_SDF);
    t = min(t, LEFT_FRONT_STONE_SDF);
    t = min(t, RIGHT_FRONT_STONE_SDF);
    t = min(t, FLOOR_SDF);
    t = min(t, MIDDLE_TRI_SDF);
    t = min(t, BACK_BOTTOM_STEP_SDF);
    t = min(t, BACK_TOP_STEP_SDF);
    t = min(t, FLOATING_ROCK_SDF);
    return t;
}

void findClosestObject(vec3 pos, out float t, out int obj, vec3 lightPos) {
    t = CENTER_TRI_SDF;
    obj = CENTER_TRI;
    
    float t2;
    float bounding_sphere_dist = sphere(pos, 50.0);
    if(bounding_sphere_dist <= 0.00001f) {
      if((t2 = SWORD_HOLDER_SDF) < t) {
          t = t2;
          obj = SWORD_HOLDER;
      }
      if((t2 = SWORD_BLADE_BOTTOM_SDF) < t) {
          t = t2;
          obj = SWORD_BLADE_BOTTOM;
      }
      if((t2 = SWORD_BLADE_TOP_SDF) < t) {
          t = t2;
          obj = SWORD_BLADE_TOP;
      }
      if((t2 = SWORD_GUARD_SDF) < t) {
          t = t2;
          obj = SWORD_GUARD;
      }
      if((t2 = SWORD_HILT_SDF) < t) {
          t = t2;
          obj = SWORD_HILT;
      }
      if((t2 = SWORD_HILT2_SDF) < t) {
          t = t2;
          obj = SWORD_HILT2;
      }
      if((t2 = SWORD_QUAD_SDF) < t) {
          t = t2;
          obj = SWORD_QUAD;
      }
      if((t2 = SWORD_END_SDF) < t) {
          t = t2;
          obj = SWORD_END;
      }
      if((t2 = SWORD_LEFT_WING_SDF) < t) {
          t = t2;
          obj = SWORD_LEFT_WING;
      }
      if((t2 = SWORD_RIGHT_WING_SDF) < t) {
          t = t2;
          obj = SWORD_RIGHT_WING;
      }
      if((t2 = SWORD_LEFT_WING_END_SDF) < t) {
          t = t2;
          obj = SWORD_LEFT_WING_END;
      }
      if((t2 = SWORD_RIGHT_WING_END_SDF) < t) {
          t = t2;
          obj = SWORD_RIGHT_WING_END;
      }
      if((t2 = SWORD_GEM_SDF) < t) {
          t = t2;
          obj = SWORD_GEM;
      }
      if((t2 = STEPS_SDF) < t) {
          t = t2;
          obj = STEPS;
      }
      if((t2 = LEFT_FRONT_STONE_SDF) < t) {
          t = t2;
          obj = LEFT_FRONT_STONE;
      }
      if((t2 = RIGHT_FRONT_STONE_SDF) < t) {
          t = t2;
          obj = RIGHT_FRONT_STONE;
      }
      if((t2 = FLOOR_SDF) < t) {
          t = t2;
          obj = FLOOR;
      }
      if((t2 = MIDDLE_TRI_SDF) < t) {
          t = t2;
          obj = MIDDLE_TRI;
      }
      if((t2 = BACK_BOTTOM_STEP_SDF) < t) {
          t = t2;
          obj = BACK_BOTTOM_STEP;
      }
      if((t2 = BACK_TOP_STEP_SDF) < t) {
          t = t2;
          obj = BACK_TOP_STEP;
      }
      if((t2 = FLOATING_ROCK_SDF) < t) {
          t = t2;
          obj = FLOATING_ROCK;
      }
    } else {
      t = bounding_sphere_dist;
      obj = -1;
    }
}

float hardShadow(vec3 dir, vec3 origin, float min_t, vec3 lightPos) {
    float t = min_t;
    for(int i = 0; i < RAY_STEPS; i++) {
        float m = findClosestObject(origin + t * dir, lightPos);
        if(m < 0.0001) {
            return 0.0;
        }
        t += m;
    }
    return 1.0;
}

float softShadow(vec3 dir, vec3 origin, float min_t, float k, vec3 lightPos) {
    float res = 1.0;
    float t = min_t;
    for(int i = 0; i < RAY_STEPS; ++i) {
        float m = findClosestObject(origin + t * dir, lightPos);
        if(m < 0.0001) {
            return 0.0;
        }
        res = min(res, k * m / t);
        t += m;
    }
    return res;
}

void march(vec3 origin, vec3 dir, out float t, out int hitObj, vec3 lightPos) {
    t = 0.001;
    for(int i = 0; i < RAY_STEPS; i++) {
        vec3 pos = origin + t * dir;
        float m;
        if(isRayTooLong(pos, origin)) {
          break;
        }
        findClosestObject(pos, m, hitObj, lightPos);
        if(m < 0.01) {
            return;
        }
        t += m;
    }
    t = -1.0;
    hitObj = -1;
}

vec3 computeNormal(vec3 pos, vec3 lightPos) {
    vec3 epsilon = vec3(0.0, 0.001, 0.0);
    return normalize(vec3(findClosestObject(pos + epsilon.yxx, lightPos) - findClosestObject(pos - epsilon.yxx, lightPos),
                          findClosestObject(pos + epsilon.xyx, lightPos) - findClosestObject(pos - epsilon.xyx, lightPos),
                          findClosestObject(pos + epsilon.xxy, lightPos) - findClosestObject(pos - epsilon.xxy, lightPos)));
}

vec3 getSceneColor(int hitObj, vec3 p, vec3 n, vec3 light, vec3 view) {
    float lambert = dot(n, light) + 0.3;
    vec3 h = (view + light) / 2.0;
    float shininess = 4.0;
    vec3 specularColor = vec3(1.0);
    vec3 blinnPhong = max(pow(dot(h, n), shininess), 0.f) * specularColor;
    vec3 a, b, c, d;
    switch(hitObj) {
        case CENTER_TRI:
        case SWORD_HOLDER:
        case STEPS:
        case LEFT_FRONT_STONE:
        case RIGHT_FRONT_STONE:
        case MIDDLE_TRI:
        case BACK_TOP_STEP:
        case BACK_BOTTOM_STEP:
        case FLOATING_ROCK:
        a = vec3(-0.281, 0.4884, 0.5384);
        b = vec3(-1.301, 0.3884, -0.041);
        c = vec3(0.1384, -0.141, -0.381);
        d = vec3(-1.581, 0.1784, -0.121);
        return cosinePalette(a, b, c, d, fbm(p.x / 2.0, p.y / 2.0, p.z / 2.0).x) / 1.2 * lambert;
        break;
        case FLOOR:
        a = vec3(0.3, 0.8, 0.1);
        b = vec3(0.5);
        c = vec3(1.0);
        d = vec3(0.3, 0.2, 0.2);
        return cosinePalette(a, b, c, d, perlin(p / 100.0)) * lambert;
        break;
        case SWORD_BLADE_BOTTOM:
        case SWORD_BLADE_TOP:
        case SWORD_QUAD:
        return rgb(vec3(165.0, 240.0, 232.0)) * lambert + blinnPhong;
        break;
        case SWORD_HILT:
        return vec3(0.1, 0.7, 0.7) * lambert;
        break;
        case SWORD_GUARD:
        case SWORD_END:
        case SWORD_LEFT_WING:
        case SWORD_RIGHT_WING:
        case SWORD_LEFT_WING_END:
        case SWORD_RIGHT_WING_END:
        case SWORD_HILT2:
        return vec3(0.2, 0.2, 0.7) * lambert;
        break;
        case SWORD_GEM:
        return vec3(0.7, 0.7, 0.1) * lambert + vec3(0.5) + blinnPhong;
        break;
    }
    // Background color
    a = vec3(-1.061, 0.4884, 0.5384);
    b = vec3(-1.301, 0.3884, -0.041);
    c = vec3(0.1384, -0.141, -0.381);
    d = vec3(-1.581, 0.1784, -0.121);
    return cosinePalette(a, b, c, d, perlin(p * 5.0));
}

Intersection getIntersection(vec3 dir, vec3 eye, vec3 lightPos) {
    float t;
    int hitObj;
    march(eye, dir, t, hitObj, lightPos);
    
    vec3 isect = eye + t * dir;
    vec3 nor = computeNormal(isect, lightPos);
    vec3 surfaceColor = vec3(1.0);
    
    vec3 lightDir = normalize(lightPos - isect);
    
    surfaceColor *= getSceneColor(hitObj, isect, nor, lightDir, normalize(isect - eye)) * softShadow(lightDir, isect, 0.1, 8.0, lightPos);
    // Fill light and global illumination
    surfaceColor += max(0.0, dot(nor, SKY_FILL_LIGHT_DIR)) * vec3(1.2f) * SKY_FILL_LIGHT_COLOR;
    surfaceColor += max(0.0, dot(nor, SUN_AMBIENT_LIGHT_DIR)) * vec3(0.1) * SUN_AMBIENT_LIGHT_COLOR;
    return Intersection(t, surfaceColor, isect, hitObj);
}
////////// RAY MARCHING END //////////


void main() {
  Ray r = raycast(fs_Pos);
  Intersection i = getIntersection(r.direction, r.origin, LIGHT_POS);
  // vec3 color = 0.5 * (r.direction + vec3(1.0, 1.0, 1.0));

  // out_Col = vec4(0.5 * (fs_Pos + vec2(1.0)), 0.5 * (sin(u_Time * 3.14159 * 0.01) + 1.0), 1.0);
  out_Col = vec4(i.color, 1.0);
}

