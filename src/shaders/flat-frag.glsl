#version 300 es
precision highp float;

const int MAX_RAY_STEPS = 150;
const float EPSILON = 1e-4;
const float FOV = 60.0;
const float MAX_DISTANCE = 20.0;

uniform vec3 u_Eye, u_Ref, u_Up;
uniform vec2 u_Dimensions;
uniform float u_Time;

in vec2 fs_Pos;
out vec4 out_Col;

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

struct DirectionalLight
{
    vec3 dir;
    vec3 color;
};

// HELPERS //
vec3 rgb(vec3 col)
{
  return col / 255.0;
}

float triangleWave(float x, float freq, float amplitude)
{
  return abs(mod(x * freq, amplitude) - (0.5 * amplitude));
}

// SDF CODE //
mat4 rotateX(float theta) {
    float c = cos(theta);
    float s = sin(theta);

    mat4 m = mat4(
        vec4(c, 0, s, 0),
        vec4(0, 1, 0, 0),
        vec4(-s, 0, c, 0),
        vec4(0, 0, 0, 1)
    );
    return inverse(m);
}

mat4 rotateY(float theta) {
    float c = cos(theta);
    float s = sin(theta);

    mat4 m = mat4(
        vec4(1, 0, 0, 0),
        vec4(0, c, -s, 0),
        vec4(0, s, c, 0),
        vec4(0, 0, 0, 1)
    );
    return inverse(m);
}

mat4 rotateZ(float theta) {
    float c = cos(theta);
    float s = sin(theta);

    mat4 m = mat4(
        vec4(c, -s, 0, 0),
        vec4(s, c, 0, 0),
        vec4(0, 0, 1, 0),
        vec4(0, 0, 0, 1)
    );
    return inverse(m);
}

float sdfSphere(vec3 query_position, vec3 position, float radius)
{
    return length(query_position - position) - radius;
}

// from IQ
float sdCylinder(vec3 p, vec3 a, vec3 b, float r)
{
  vec3  ba = b - a;
  vec3  pa = p - a;
  float baba = dot(ba,ba);
  float paba = dot(pa,ba);
  float x = length(pa*baba-ba*paba) - r*baba;
  float y = abs(paba-baba*0.5)-baba*0.5;
  float x2 = x*x;
  float y2 = y*y*baba;
  float d = (max(x,y)<0.0)?-min(x2,y2):(((x>0.0)?x2:0.0)+((y>0.0)?y2:0.0));
  return sign(d)*sqrt(abs(d))/baba;
}

float sdRoundBox( vec3 p, vec3 b, float r )
{
  vec3 q = abs(p) - b;
  return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0) - r;
}

float plane(vec3 p, float planeHeight)
{
  return p.y - planeHeight;
}

float smin( float a, float b, float k )
{
    float h = clamp( 0.5+0.5*(b-a)/k, 0.0, 1.0 );
    return mix( b, a, h ) - k*h*(1.0-h);
}

// from IQ
vec3 applyFog(vec3 rgb, vec3 fogColor, float density, float dist)
{
    float fogAmount = 1.0 - exp( -dist*density );
    return mix( rgb, fogColor, fogAmount );
}

vec3 opRep(vec3 p, vec3 c)
{
    return mod(p+0.5*c,c)-0.5*c;
}

vec3 opRepLim(vec3 p, float c, vec3 l)
{
    return p-c*clamp(round(p/c),-l,l);
}

vec3 opRevolution( in vec3 p, float o )
{
    return vec3( length(p.xz) - o, p.y , 0);
}

float pillar(vec3 pos, float rotation)
{
  return sdCylinder(pos, (rotateX(rotation) * vec4(0.57, -2.0, 0.0, 1.0)).xyz, 
    (rotateX(rotation) * vec4(0.57, 1.6, 0.0, 1.0)).xyz, 0.02);
}

float towerFloor(vec3 pos)
{
  return sdCylinder(pos, vec3(0.0, -0.05, 0.0), vec3(0.0, 0.05, 0.0), 0.64);
}

float towerBody(vec3 pos)
{
  vec3 displacement = vec3(0.0, 0.4, 0.0);
  // base
  float middle = sdCylinder(pos, vec3(0.0, -1.5, 0.0), vec3(0.0, 1.6, 0.0), 0.5);
  // upper tower
  float upper = sdCylinder(pos, vec3(0.0, 1.60, 0.0), vec3(0.0, 2.2, 0.0), 0.45);
  middle = min(middle, upper);
  // pillars
  float rotation = radians(45.0);
  float p1 = pillar(pos, 0.0);
  float p2 = pillar(pos, rotation * 1.0);
  float p3 = pillar(pos, rotation * 2.0);
  float p4 = pillar(pos, rotation * 3.0);
  float p5 = pillar(pos, rotation * 4.0);
  float p6 = pillar(pos, rotation * 5.0);
  float p7 = pillar(pos, rotation * 6.0);
  float p8 = pillar(pos, rotation * 7.0);
  float pillars = min(p1, min(p2, min(p3, min(p4, min(p5, min(p6, min(p7, p8)))))));
  // floors
  float levels = towerFloor(opRepLim(pos + vec3(0.0, -0.1, 0.0), 0.5, vec3(0.0, 2.0, 0.0)));
  float top = sdCylinder(pos + vec3(0.0, -1.6, 0.0), vec3(0.0, -0.05, 0.0), vec3(0.0, 0.05, 0.0), 0.64);
  
  return smin(middle, smin(min(levels, top), pillars, 0.05), 0.05);
}

float towerBase(vec3 pos)
{
  float middle = sdCylinder(pos, vec3(0.0, -0.5, 0.0), vec3(0.0, 0.45, 0.0), 0.64);
  return middle;
}

float tower(vec3 pos, float minDist)
{
  // float bound = sdRoundBox(pos + vec3(0.0, 1.0, 0.0), vec3(3.0, 3.0, 3.0), 0.0);
  // if (bound > minDist)
  // {
  //   return minDist;
  // }

  float rotation = radians(-25.0) * (sin(u_Time / 50.0) + 1.0) / 2.0;
  vec3 rotatedPos = (rotateZ(rotation) * vec4(pos + vec3(0.0, 3.0, 0.0), 1.0)).xyz + vec3(0.0, -3.0, 0.0) + vec3(0.0, 0.2, 0.0);
  return smin(towerBody(rotatedPos), towerBase(rotatedPos + vec3(0.0, 1.8, 0.0)), 0.05);
}

float people(vec3 pos, float size)
{
  vec3 movement = vec3(0.0, 0.08, 0.0) * triangleWave((u_Time + 3.5 * fs_Pos.x + 1.2 * fs_Pos.y) / 25.0, 10.0, 2.0);
  float crowd = sdCylinder(opRepLim(pos + vec3(0.0, 2.4, 0.0) + movement, 0.25, vec3(size, 0.0, size)), vec3(0.0, -0.05,0.0), vec3(0.0,0.05,0.0), 0.02);
  return crowd;
}

float crowds(vec3 pos)
{
  return min(people(pos + vec3(-1.3, 0.0, 1.2), 3.0), 
             min(people(pos + vec3(2.0, 0.0, -2.4), 2.0), 
                 people(pos + vec3(-1.5, 0.0, -1.5), 4.0)));
}

// SCENE //
#define FLOOR plane(queryPos, -2.5)
#define BODY tower(queryPos + vec3(0.0, 0.2, 0.0), dist)
#define THING crowds(queryPos)

#define FLOOR_NUM 0
#define BODY_NUM 2
#define THING_NUM 3

// material colors //
#define GRASS_COLOR rgb(vec3(10, 54, 21))
#define TOWER_COLOR rgb(vec3(235, 242, 225))
#define PEOPLE_COLOR rgb(vec3(88, 230, 232))

// light colors //
#define SUN_KEY_LIGHT rgb(vec3(186, 255, 237)) * 1.5
#define SKY_FILL_LIGHT rgb(vec3(255, 233, 181)) * 0.2
#define SUN_AMBIENT_LIGHT rgb(vec3(181, 178, 16)) * 0.2
#define OUTSIDE_BACKGROUND rgb(vec3(49, 98, 173))
#define OUTSIDE_BACKGROUND_2 rgb(vec3(121, 156, 209))

float sceneSDF(vec3 queryPos)
{
  float dist = FLOOR;
  dist = min(dist, BODY);
  dist = min(dist, THING);
  return dist;
}

float shadowSDF(vec3 queryPos)
{
  float dist = FLOOR;
  dist = min(dist, BODY);
  dist = min(dist, THING);
  return dist;
}

void sceneSDF(vec3 queryPos, out float dist, out int material_id) 
{
  dist = FLOOR;
  float dist2;
  material_id = FLOOR_NUM;
  if ((dist2 = BODY) < dist)
  {
    dist = dist2;
    material_id = BODY_NUM;
  }
  if ((dist2 = THING) < dist)
  {
    dist = dist2;
    material_id = THING_NUM;
  }
}

vec3 sdfNormal(vec3 pos)
{
  vec2 epsilon = vec2(0.0, EPSILON);
  return normalize( vec3( sceneSDF(pos + epsilon.yxx) - sceneSDF(pos - epsilon.yxx),
                            sceneSDF(pos + epsilon.xyx) - sceneSDF(pos - epsilon.xyx),
                            sceneSDF(pos + epsilon.xxy) - sceneSDF(pos - epsilon.xxy)));
}

// RAYMARCH CODE //
Ray getRay(vec2 uv)
{
    Ray r;
    
    vec3 look = normalize(u_Ref - u_Eye);
    vec3 camera_RIGHT = normalize(cross(look, u_Up));
    vec3 camera_UP = cross(camera_RIGHT, look);
    float len = distance(u_Eye, u_Ref);
    
    float aspect_ratio = u_Dimensions.x / u_Dimensions.y;
    vec3 screen_vertical = camera_UP * len * tan(FOV); 
    vec3 screen_horizontal = camera_RIGHT * len * aspect_ratio * tan(FOV);
    vec3 screen_point = (look + uv.x * screen_horizontal + uv.y * screen_vertical);
    
    r.origin = u_Eye;
    r.direction = normalize(screen_point - u_Eye);
   
    return r;
}

Intersection getRaymarchedIntersection(vec2 uv)
{
    Ray ray = getRay(uv);
    Intersection intersection;
    
    intersection.distance_t = -1.0;
    intersection.position = u_Eye;
    intersection.normal = vec3(0, 0, 0);
    intersection.material_id = -1;

    float t = 0.0;
    for (int i = 0; i < MAX_RAY_STEPS; i++)
    {
      // get position
      vec3 pos = ray.origin + t * ray.direction;
      if (t > MAX_DISTANCE)
      {
        break;
      }

      float dist;
      int material_id;
      sceneSDF(pos, dist, material_id);
      // if dist is on surface of sdf, then we're done
      if (dist < EPSILON)
      {
        intersection.position = pos;
        intersection.distance_t = t;
        intersection.normal = sdfNormal(intersection.position);
        intersection.material_id = material_id;
        break;
      }
      t += dist;
    }

    return intersection;
}

float softShadow(vec3 origin, vec3 dir, float min_t, float k) {
    float res = 1.0;
    float t = min_t;
    for(int i = 0; i < MAX_RAY_STEPS; ++i) 
    {
        float h = shadowSDF(origin + t * dir);
        if (h < EPSILON) 
        {
            return 0.0;
        }
        res = min(res, k * h / t );
        t += h;
    }
    return res;
}

vec3 calculateMaterial(int material_id, vec3 p, vec3 n, vec3 viewDir)
{
  DirectionalLight lights[3];
  lights[0] = DirectionalLight(normalize(vec3(-10.0, 15.0, -10.0)),
                               SUN_KEY_LIGHT);
  lights[1] = DirectionalLight(vec3(0., 1., 0.),
                               SKY_FILL_LIGHT);
  lights[2] = DirectionalLight(normalize(-vec3(15.0, 0.0, 10.0)),
                               SUN_AMBIENT_LIGHT);
  vec3 backgroundColor = mix(OUTSIDE_BACKGROUND_2, OUTSIDE_BACKGROUND, (fs_Pos.y + 1.0) / 2.0);

  float ambient = 0.2;
  float lambert = max(0.0, dot(n, lights[0].dir)) + ambient;
  vec3 halfVec = (lights[0].dir + viewDir) / 2.0; 
  float specular = pow(max(dot(halfVec, n), 0.0), 32.0);
  float blinn = lambert + 0.75 * specular;

  vec3 albedo;
  switch (material_id)
  {
    case FLOOR_NUM:
      albedo = GRASS_COLOR;
      break;
    case BODY_NUM:
      albedo = TOWER_COLOR;
      break;
    case THING_NUM:
      albedo = PEOPLE_COLOR;
      break;
    case -1:
      return backgroundColor;
  }

  vec3 color = albedo *
               lights[0].color *
               max(0.0, dot(n, lights[0].dir)) *
               softShadow(p, lights[0].dir, 0.1, 12.0);
  for(int i = 1; i < 3; ++i) 
  {
    color += albedo *
             lights[i].color *
             max(0.0, dot(n, lights[i].dir));
  }
  color *= blinn;
  // gamma
  color = pow(color, vec3(1. / 2.2));

  return color;
}

vec3 getSceneColor(vec2 uv, vec3 lightPos, out vec3 pos)
{
  Intersection intersection = getRaymarchedIntersection(uv);
  vec3 viewDir = normalize(u_Ref - u_Eye);
  pos = intersection.position;
  return calculateMaterial(intersection.material_id, intersection.position, intersection.normal, viewDir);
}

void main() {
  vec3 lightPos = vec3(-5.0, 7.45, -5.0);

  vec2 uv = fs_Pos;

  vec3 pos;
  vec3 col = getSceneColor(uv, lightPos, pos);

  vec3 backgroundColor = rgb(vec3(23, 53, 99));

  float fog = smoothstep(14.0, 20.0, distance(pos, u_Eye.xyz));

  col = mix(col, backgroundColor, fog);

  out_Col = vec4(col, 1.0);
}
