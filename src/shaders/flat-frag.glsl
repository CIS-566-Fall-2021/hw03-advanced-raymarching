#version 300 es
precision highp float;

uniform vec3 u_Eye, u_Ref, u_Up;
uniform vec2 u_Dimensions;
uniform float u_Time;

in vec2 fs_Pos;
out vec4 out_Col;

#define CULL_RAY_LENGTH 1
#define BOUNDING_SPHERE 1

#define MAX_RAY_LENGTH 20.0
#define MAX_RAY_MARCH_STEPS 150
#define EPSILON 0.001
#define BOUNDING_SPHERE_EPSILON 0.35
#define FOV 45.0
#define LIGHT_POS vec3(-12.0, 15.0, -15.0)

#define WHITE_LIGHT vec3(1.0, 1.0, 1.0)
#define YELLOW_LIGHT vec3(13, 1.3, -1.5)
#define FILL_LIGHT vec3(0.7, 0.0, 0.0)

#define FLOOR plane(p + vec3(0, 4, 10), vec3(0, 1, 0), 1.0)

#define FRIDGE fridge(p)
#define TATA_HEAD tataHead(p)
#define TATA_BODY tataBody(p)
#define TATA_FACE tataFace(p)
#define TATA_MOUTH tataMouth(p)

#define BOTTLE_1 sauceBottle(p, vec3(0, -30.0, 0), vec3(0.25, 1.65, -4))
#define BOTTLE_2 sauceBottle(p, vec3(0, -30.0, 0), vec3(-0.05, 1.65, -4.75))
#define BOTTLE_3 sauceBottle(p, vec3(0, -30.0, 0), vec3(-0.15, 1.65, -5.5))

#define WATER_BOTTLE_1 waterBottle(p, vec3(0, 20.0, 0), vec3(-0.6, 4, -4.4))
#define WATER_BOTTLE_2 waterBottle(p, vec3(0, 20.0, 0), vec3(0.6, 4, -4.4))
#define WATER_BOTTLE_3 waterBottle(p, vec3(0, 20.0, 0), vec3(1.8, 4, -4.4))
#define WATER_CAP_1 waterBottleCap(p, vec3(0, 20.0, 0), vec3(-0.6, 2.25, -4.4))
#define WATER_CAP_2 waterBottleCap(p, vec3(0, 20.0, 0), vec3(0.6, 2.25, -4.4))
#define WATER_CAP_3 waterBottleCap(p, vec3(0, 20.0, 0), vec3(1.8, 2.25, -4.4))

#define MILK_1 milk(p, vec3(0, -10.0, 0), vec3(-0.5, 4.3, -4))
#define MILK_2 milk(p + vec3(-1.5, 4.8, -2), vec3(90, -60.0, 0), vec3(-2, 0, 0))
#define MILK_3 milk(p, vec3(0, -50.0, 0), vec3(0.3, 4.3, -4))
#define MILK_4 milk(p, vec3(0, -30.0, 0), vec3(-0.2, 4.3, -4))
#define MILK_5 milk(p, vec3(0, -40.0, 0), vec3(-0.5, 4.3, -4.75))
#define MILK_6 milk(p, vec3(0, -20.0, 0), vec3(-1.2, 4.3, -4.75))

#define JUICE_BOX_1 juiceBox(p, vec3(0, -40.0, 0), vec3(2.0, 1.5, -3.75))
#define JUICE_BOX_2 juiceBox(p, vec3(0, -30.0, 0), vec3(1.3, 1.5, -4.75))
#define JUICE_BOX_3 juiceBox(p, vec3(0, -20.0, 0), vec3(0.3, 1.5, -5.75))

#define JUICE_BOX_TOP_1 juiceBoxTop(p, vec3(0, -40.0, 0), vec3(2.0, 1.5, -3.75))
#define JUICE_BOX_TOP_2 juiceBoxTop(p, vec3(0, -30.0, 0), vec3(1.3, 1.5, -4.75))
#define JUICE_BOX_TOP_3 juiceBoxTop(p, vec3(0, -20.0, 0), vec3(0.3, 1.5, -5.75))

#define CAN_1 can(p, vec3(0, -30.0, 0), vec3(-1.2, 1.75, -4))
#define CAN_2 can(p, vec3(0, -30.0, 0), vec3(-0.8, 1.75, -4.75))
#define CAN_3 can(p + vec3(-2.3, -4.4, -4), vec3(10.0 + 30.0 * gain(sin(u_Time * 0.05), 0.15) - 100.0, -30, 0), vec3(0, 0.75, 0))
#define CAN_4 can(p, vec3(0, 10, 90), vec3(-4.75, 0, 0))

#define ICE_CREAM_1 iceCreamTub(p, vec3(0, -30, 0), vec3(1, -1, -4.5))

#define FLOOR_ID 2
#define FRIDGE_ID 3
#define JUICE_WHITE_ID 4
#define JUICE_ORANGE_ID 5
#define BOTTLE_1_ID 6
#define BOTTLE_2_ID 7
#define BOTTLE_3_ID 8
#define WATER_BOTTLE_ID 9
#define TATA_HEAD_ID 10
#define TATA_BODY_ID 11
#define TATA_MOUTH_ID 12
#define TATA_FACE_ID 13
#define MILK_ID 14
#define WATER_CAP_ID 15
#define CAN_ID 16
#define ICE_CREAM_TUB_ID 17
#define JUICE_BOX_TOP_ID 18

struct Ray {
  vec3 origin;
  vec3 direction;
};

struct Intersection 
{
  vec3 position;
  vec3 normal;
  float distance_t;
  int material_id;
  bool object_hit;
};

struct DirectionalLight
{
  vec3 direction;
  vec3 color;
};

float dot2(vec2 v) { return dot(v,v); }

float dot2(vec3 v) { return dot(v,v); }

vec3 rgb(int r, int g, int b) {
  return vec3(float(r) / 255.0, float(g) / 255.0, float(b) / 255.0);
}

float bias(float t, float b) {
  return (t / ((((1.0 / b) - 2.0) * (1.0 - t)) + 1.0));
}

float gain(float t, float g) {
  if(t < 0.5)
    return bias(t * 2.0, g) / 2.0;
  else
    return bias(t * 2.0 - 1.0, 1.0 - g) / 2.0 + 0.5;
}

float easeInOutQuart(float t) {
  if (t < 0.5) {
    return 8.0 * t * t * t * t;
  }
  return 1.0 - pow(-2.0 * t + 2.0, 4.0) / 2.0;
}

vec3 rotateX(vec3 p, float d) {
  float a = d * 3.1415 / 180.;
  return vec3(p.x, cos(a) * p.y - sin(a) * p.z, sin(a) * p.y + cos(a) * p.z);   
}

vec3 rotateY(vec3 p, float d) {
  float a = d * 3.1415 / 180.;
  return vec3(cos(a) * p.x + sin(a) * p.z, p.y, -sin(a) * p.x + cos(a) * p.z);    
}

vec3 rotateZ(vec3 p, float d) {
  float a = d * 3.1415 / 180.;
  return vec3(cos(a) * p.x - sin(a)* p.y, sin(a) * p.x + cos(a) * p.y, p.z);    
}

vec3 rotateYXZ(vec3 p, vec3 r) {
  return rotateZ(rotateX(rotateY(p, r[1]), r[0]), r[2]);
}

float opUnion(float d1, float d2) { 
  return min(d1, d2); 
}

float opSubtraction(float d1, float d2) {
  return max(-d1, d2); 
}

float opIntersection(float d1, float d2) { 
  return max(d1, d2); 
}

float opSmoothUnion(float d1, float d2, float k) {
  float h = clamp( 0.5 + 0.5*(d2-d1)/k, 0.0, 1.0 );
  return mix( d2, d1, h ) - k*h*(1.0-h);
}

float plane(vec3 p, vec3 n, float h) {
  // n must be normalized
  return dot(p,n) + h;
}

float sphere(vec3 p, float r, vec3 c) {
	return distance(p, c) - r;
}

float sphere(vec3 p, float s) {
  return length(p)-s;
}

float box(vec3 p, vec3 b) {
  vec3 q = abs(p) - b;
  return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0);
}

float roundBox(vec3 p, vec3 b, float r) {
  vec3 q = abs(p) - b;
  return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0) - r;
}

float cylinder(vec3 p, float h, float r) {
  vec2 d = abs(vec2(length(p.xz),p.y)) - vec2(h,r);
  return min(max(d.x,d.y),0.0) + length(max(d,0.0));
}

float roundCylinder(vec3 p, float ra, float rb, float h) {
  vec2 d = vec2( length(p.xz)-2.0*ra+rb, abs(p.y) - h );
  return min(max(d.x,d.y),0.0) + length(max(d,0.0)) - rb;
}

float ellipsoid(vec3 p, vec3 r) {
  float k0 = length(p/r);
  float k1 = length(p/(r*r));
  return k0*(k0-1.0)/k1;
}

float cappedTorus(vec3 p, vec2 sc, float ra, float rb) {
  p.x = abs(p.x);
  float k = (sc.y*p.x>sc.x*p.y) ? dot(p.xy,sc) : length(p.xy);
  return sqrt( dot(p,p) + ra*ra - 2.0*ra*k ) - rb;
}

float capsule(vec3 p, vec3 a, vec3 b, float r) {
  vec3 pa = p - a, ba = b - a;
  float h = clamp( dot(pa,ba)/dot(ba,ba), 0.0, 1.0 );
  return length( pa - ba*h ) - r;
}

float capsule(vec3 p, float h, float r) {
  p.y -= clamp(p.y, 0.0, h);
  return length(p) - r;
}

float triPrism(vec3 p, vec2 h)
{
  vec3 q = abs(p);
  return max(q.z-h.y,max(q.x*0.866025+p.y*0.5,-p.y)-h.x*0.5);
}

float cappedCone(vec3 p, float h, float r1, float r2)
{
  vec2 q = vec2( length(p.xz), p.y );
  vec2 k1 = vec2(r2,h);
  vec2 k2 = vec2(r2-r1,2.0*h);
  vec2 ca = vec2(q.x-min(q.x,(q.y<0.0)?r1:r2), abs(q.y)-h);
  vec2 cb = q - k1 + k2*clamp( dot(k1-q,k2)/dot2(k2), 0.0, 1.0 );
  float s = (cb.x<0.0 && ca.y<0.0) ? -1.0 : 1.0;
  return s*sqrt( min(dot2(ca),dot2(cb)) );
}

float fridge(vec3 p) {
  float open_front = box(rotateY(p, -30.0) + vec3(0, 1, -3), vec3(2.4, 4.4, 0.5));
  float top_shelf = box(rotateY(p, -30.0) + vec3(0, -1.8, -4.5), vec3(2, 1.2, 2));
  float mid_shelf = box(rotateY(p, -30.0) + vec3(0, 0.85, -4.5), vec3(2, 1.2, 2));
  float bot_shelf = box(rotateY(p, -30.0) + vec3(0, 3.5, -4.5), vec3(2, 1.2, 2));
  float shelves = opUnion(opUnion(top_shelf, mid_shelf), bot_shelf);
  float box_body = roundBox(rotateY(p, -30.0) + vec3(0, 1, -5), vec3(2, 4, 2), 0.3);
  float top_door_body = roundBox(rotateY(p, 50.0) + vec3(-1, -1.8, -3), vec3(2, 1.2, 0.5), 0.3);
  float top_door_open_front = box(rotateY(p, 50.0) + vec3(-1, -1.8, -2.4), vec3(2.4, 1.6, 0.3));
  float top_door_shelf = box(rotateY(p, 50.0) + vec3(-0.9, -1.8, -2.5), vec3(2, 1.2, 1.2));
  float top_door = opSubtraction(top_door_open_front, top_door_body);
  float bot_door_body = roundBox(rotateY(p, 20.0) + vec3(0.8, 2.4, -4.2), vec3(2, 2.4, 0.5), 0.3);
  float bot_door_open_front = box(rotateY(p, 20.0) + vec3(0.85, 2.4, -3.6), vec3(2.4, 2.8, 0.3));
  float bot_door_shelf = box(rotateY(p, 20.0) + vec3(0.85, 2.4, -3.6), vec3(2, 2.4, 1.2));
  float bot_door = opSubtraction(bot_door_open_front, bot_door_body);
  float door = opUnion(opSubtraction(top_door_shelf, top_door), 
                       opSubtraction(bot_door_shelf, bot_door));
  float body = opSubtraction(shelves, opSubtraction(open_front, box_body));
  return opUnion(body, door);
}

float tataHead(vec3 p) {
  float head_1 = ellipsoid(rotateZ(rotateY(p, -30.0) + vec3(0.4, -5, -5), 40.0), vec3(1, 0.75, 0.5));
  float head_2 = ellipsoid(rotateZ(rotateY(p, -30.0) + vec3(-0.4, -5, -5), -40.0), vec3(1, 0.75, 0.5));
  float head = opSmoothUnion(head_1, head_2, 0.1);
  return head;
}

float tataFace(vec3 p) {
  float mouth = ellipsoid(rotateY(p, -30.0) + vec3(0, -4.5, -4.5), vec3(0.16, 0.04, 0.04));
  float angle = 40.0 * easeInOutQuart(0.5 + 0.5 * sin(u_Time * 0.05));
  float right_eyebrow = ellipsoid(rotateZ(rotateY(p, -30.0) + vec3(0.25, -5, -4.5), angle), vec3(0.16, 0.04, 0.04));
  float left_eyebrow = ellipsoid(rotateZ(rotateY(p, -30.0) + vec3(-0.25, -5, -4.5), -angle), vec3(0.16, 0.04, 0.04));
  float right_eye = sphere(rotateY(p, -30.0) + vec3(0.2, -4.8, -4.5), 0.08, vec3(0));
  float left_eye = sphere(rotateY(p, -30.0) + vec3(-0.2, -4.8, -4.5), 0.08, vec3(0));
  return opUnion(opUnion(opUnion(right_eyebrow, left_eyebrow), mouth),
                opUnion(right_eye, left_eye));
}

float tataBody(vec3 p) {
  float tummy = ellipsoid(rotateX(rotateY(p, -30.0) + vec3(0, -3.9, -5), -20.0), vec3(0.5, 0.5, 0.3));
  float xAngle = 40.0 * gain(sin(u_Time * 0.05), 0.15) - 100.0;
  float right_arm = cappedTorus(rotateZ(
                                  rotateX(rotateY(p, -30.0) + 
                                          vec3(0, -4, -5), xAngle) + 
                                  vec3(0, 0.5, 0), 
                                -90.0), vec2(sqrt(1.0 - pow(0.5, 2.0)), 0.5), 0.6, 0.15);
  float left_arm = capsule(rotateZ(
                            rotateX(
                              rotateY(p, -30.0) + 
                                      vec3(-.7, -3.5, -5.25), 
                            20.0), 
                          -30.0), 0.6, 0.15);
  float left_leg = capsule(rotateX(rotateY(p, -30.0) + vec3(-0.2, -3.5, -4.8), 90.0), 0.6, 0.2);
  float right_leg = capsule(rotateX(rotateY(p, -30.0) + vec3(0.2, -3.5, -4.8), 90.0), 0.6, 0.2);
  float body = opSmoothUnion(
                opSmoothUnion(
                  opSmoothUnion(
                    opSmoothUnion(tummy, right_arm, 0.06), 
                    left_arm, 0.06), 
                  right_leg, 0.06), 
                left_leg, 0.06);
  return body;
}

float tataMouth(vec3 p) {
  return ellipsoid(rotateX(rotateY(p, -30.0) + vec3(0, -4.5, -4.6), 20.0), vec3(0.4, 0.2, 0.05));
}

float juiceBox(vec3 p, vec3 r, vec3 t) {
  vec3 pos = rotateYXZ(p, r) + t;
  float radius = 0.02;
  vec3 dimensions = vec3(0.4, 0.6, 0.25);
  return roundBox(pos, dimensions, radius);
}

float juiceBoxTop(vec3 p, vec3 r, vec3 t) {
  vec3 top_offset = vec3(0, -0.6, 0);
  vec3 pos = rotateYXZ(p, r) + t + top_offset;
  float radius = 0.02;
  vec3 dimensions = vec3(0.42, 0.05, 0.27);
  return roundBox(pos, dimensions, radius);
}

float can(vec3 p, vec3 r, vec3 t) {
  vec3 pos = rotateYXZ(p, r) + t;
  float union_smooth_radius = 0.05;
  float body_radius = 0.25;
  float body_height = 0.35;
  float top_radius = 0.1;
  float top_height = 0.05;
  float top_smooth_radius = 0.05;
  vec3 top_offset = vec3(0, 0.32, 0);

  float body = cylinder(pos, body_radius, body_height);
  float top = roundCylinder(pos - top_offset, top_radius, top_height, top_smooth_radius);
  float bottom = roundCylinder(pos + top_offset, top_radius, top_height, top_smooth_radius);

  return opSmoothUnion(opSmoothUnion(body, top, union_smooth_radius), bottom, union_smooth_radius);
}

float milk(vec3 p, vec3 r, vec3 t) {
  vec3 body_pos = rotateYXZ(p, r) + t;
  vec3 top_offset = vec3(0, -0.42, 0);
  vec3 top_pos = rotateY(body_pos + top_offset, 90.0);
  vec2 top_dims = vec2(0.25, 0.25);
  float smooth_radius = 0.06;

  float body = box(body_pos, vec3(0.3, 0.3, 0.3));
  float top = triPrism(top_pos, top_dims);
  return opSmoothUnion(body, top, smooth_radius);
}

float sauceBottle(vec3 p, vec3 r, vec3 t) {
  vec3 body_pos = rotateYXZ(p, r) + t;
  float body_radius = 0.15;
  float body_height = 0.4;
  float round_radius = 0.05;
  float neck_radius = 0.07;
  float neck_height = 0.4;
  float union_smooth_radius = 0.2;
  vec3 neck_pos = body_pos + vec3(0, -0.45, 0);

  float body = roundCylinder(body_pos, body_radius, round_radius, body_height);
  float neck = roundCylinder(neck_pos, neck_radius, round_radius, neck_height);

  return opSmoothUnion(body, neck, union_smooth_radius);
}

float waterBottle(vec3 p, vec3 r, vec3 t) {
  vec3 body_pos = rotateYXZ(p, r) + t;
  float body_radius = 0.2;
  float body_round_radius = 0.08;
  float body_height = 0.8;

  vec3 top_pos = body_pos + vec3(0, -1.3, 0);
  float top_radius = 0.4;
  float union_smooth_radius = 0.3;

  float body = roundCylinder(body_pos, body_radius, body_round_radius, body_height);
  float top = sphere(top_pos, top_radius);
  
  return opSmoothUnion(body, top, union_smooth_radius);
}

float waterBottleCap(vec3 p, vec3 r, vec3 t) {
  vec3 pos = rotateYXZ(p, r) + t;
  float body_radius = 0.08;
  float round_radius = 0.02;
  float height = 0.08;
  return roundCylinder(pos, body_radius, round_radius, height);
}

float iceCreamTub(vec3 p, vec3 r, vec3 t) {
  vec3 tub_pos = rotateYXZ(p, r) + t;
  float tub_height = 0.4;
  float tub_top_radius = 0.5;
  float tub_bot_radius = 0.4;
  vec3 cap_pos = tub_pos + vec3(0, -0.4, 0);
  float cap_body_radius = 0.26;
  float cap_round_radius = 0.05;
  float cap_height = 0.08;
  
  float body = cappedCone(tub_pos, tub_height, tub_bot_radius, tub_top_radius);
  float cap = roundCylinder(cap_pos, cap_body_radius, cap_round_radius, cap_height);
  return opUnion(body, cap);
}

Ray getRay(vec2 uv) {
  Ray r;
  vec3 look = normalize(vec3(0.0) - u_Eye);
  vec3 right = normalize(cross(look, u_Up));
  vec3 up = normalize(cross(right, look));
  float len = length(u_Ref - u_Eye);

  float aspect_ratio = u_Dimensions.x / u_Dimensions.y;
  vec3 vertical = up * len * tan(FOV / 2.0);
  vec3 horizontal = right * len * aspect_ratio * tan(FOV / 2.0);
  vec3 screen_point = u_Ref + uv.x * horizontal + uv.y * vertical;

  r.origin = u_Eye;
  r.direction = normalize(screen_point - u_Eye);
  return r;
}

// sdf used for coloring materials
float sceneSDF(vec3 p, out int material_id) {
  #if BOUNDING_SPHERE
    float bounding_sphere_dist = sphere(p, 7.0, vec3(0, 0, 4));
    if(bounding_sphere_dist <= BOUNDING_SPHERE_EPSILON) {
      #endif

      float t1 = FLOOR;
      material_id = FLOOR_ID;
      float t2;

      if ((t2 = FRIDGE) < t1) {
        t1 = t2;
        material_id = FRIDGE_ID;
      }

      if ((t2 = ICE_CREAM_1) < t1) {
        t1 = t2;
        material_id = ICE_CREAM_TUB_ID;
      }

      if ((t2 = JUICE_BOX_1) < t1) {
        t1 = t2;
        material_id = JUICE_WHITE_ID;
      }

      if ((t2 = JUICE_BOX_2) < t1) {
        t1 = t2;
        material_id = JUICE_WHITE_ID;
      }

      if ((t2 = JUICE_BOX_3) < t1) {
        t1 = t2;
        material_id = JUICE_WHITE_ID;
      }

      if ((t2 = BOTTLE_1) < t1) {
        t1 = t2;
        material_id = BOTTLE_1_ID;
      }

      if ((t2 = BOTTLE_2) < t1) {
        t1 = t2;
        material_id = BOTTLE_2_ID;
      }

      if ((t2 = BOTTLE_3) < t1) {
        t1 = t2;
        material_id = BOTTLE_3_ID;
      }

      if ((t2 = MILK_1) < t1) {
        t1 = t2;
        material_id = MILK_ID;
      }

      if ((t2 = MILK_2) < t1) {
        t1 = t2;
        material_id = MILK_ID;
      }

      if ((t2 = MILK_3) < t1) {
        t1 = t2;
        material_id = MILK_ID;
      }

      if ((t2 = MILK_4) < t1) {
        t1 = t2;
        material_id = MILK_ID;
      }

      if ((t2 = MILK_5) < t1) {
        t1 = t2;
        material_id = MILK_ID;
      }

      if ((t2 = MILK_6) < t1) {
        t1 = t2;
        material_id = MILK_ID;
      }

      if ((t2 = CAN_1) < t1) {
        t1 = t2;
        material_id = CAN_ID;
      }

      if ((t2 = CAN_2) < t1) {
        t1 = t2;
        material_id = CAN_ID;
      }

      if ((t2 = CAN_4) < t1) {
        t1 = t2;
        material_id = CAN_ID;
      }

      if ((t2 = WATER_BOTTLE_1) < t1) {
        t1 = t2;
        material_id = WATER_BOTTLE_ID;
      }

      if ((t2 = WATER_BOTTLE_2) < t1) {
        t1 = t2;
        material_id = WATER_BOTTLE_ID;
      }

      if ((t2 = WATER_BOTTLE_3) < t1) {
        t1 = t2;
        material_id = WATER_BOTTLE_ID;
      }

      if ((t2 = WATER_CAP_1) < t1) {
        t1 = t2;
        material_id = WATER_CAP_ID;
      }

      if ((t2 = WATER_CAP_2) < t1) {
        t1 = t2;
        material_id = WATER_CAP_ID;
      }

      if ((t2 = WATER_CAP_3) < t1) {
        t1 = t2;
        material_id = WATER_CAP_ID;
      }

      if((t2 = CAN_3) < t1) {
        t1 = t2;
        material_id = CAN_ID;
      }

      if ((t2 = TATA_HEAD) < t1) {
        t1 = t2;
        material_id = TATA_HEAD_ID;
      }

      if ((t2 = TATA_BODY) < t1) {
        t1 = t2;
        material_id = TATA_BODY_ID;
      }

      if ((t2 = TATA_MOUTH) < t1) {
        t1 = t2;
        material_id = TATA_MOUTH_ID;
      }

      if ((t2 = TATA_FACE) < t1) {
        t1 = t2;
        material_id = TATA_FACE_ID;
      }

      if ((t2 = JUICE_BOX_TOP_1) < t1) {
        t1 = t2;
        material_id = JUICE_BOX_TOP_ID;
      }

      if ((t2 = JUICE_BOX_TOP_2) < t1) {
        t1 = t2;
        material_id = JUICE_BOX_TOP_ID;
      }

      if ((t2 = JUICE_BOX_TOP_3) < t1) {
        t1 = t2;
        material_id = JUICE_BOX_TOP_ID;
      }

      return t1;
  #if BOUNDING_SPHERE
    }
  material_id = -1;
  return bounding_sphere_dist;
  #endif
}

// sdf used for calculating normala
float sceneSDF(vec3 p) {
  #if BOUNDING_SPHERE
    float bounding_sphere_dist = sphere(p, 7.0, vec3(0, 0, 4));
    if(bounding_sphere_dist <= BOUNDING_SPHERE_EPSILON) {
      #endif

      float t = FLOOR;
      t = min(t, FRIDGE);
      t = min(t, ICE_CREAM_1);
      t = min(t, JUICE_BOX_1);
      t = min(t, JUICE_BOX_2);
      t = min(t, JUICE_BOX_3);
      t = min(t, JUICE_BOX_TOP_1);
      t = min(t, JUICE_BOX_TOP_2);
      t = min(t, JUICE_BOX_TOP_3);
      t = min(t, BOTTLE_1);
      t = min(t, BOTTLE_2);
      t = min(t, BOTTLE_3);
      t = min(t, MILK_1);
      t = min(t, MILK_2);
      t = min(t, MILK_3);
      t = min(t, MILK_4);
      t = min(t, MILK_5);
      t = min(t, MILK_6);
      t = min(t, WATER_BOTTLE_1);
      t = min(t, WATER_BOTTLE_2);
      t = min(t, WATER_BOTTLE_3);
      t = min(t, WATER_CAP_1);
      t = min(t, WATER_CAP_2);
      t = min(t, WATER_CAP_3);
      t = min(t, CAN_1);
      t = min(t, CAN_2);
      t = min(t, CAN_4);
      t = min(t, CAN_3);
      t = min(t, TATA_HEAD);
      t = min(t, TATA_BODY);
      t = min(t, TATA_MOUTH);
      t = min(t, TATA_FACE);
      return t;

  #if BOUNDING_SPHERE
    }
  return bounding_sphere_dist;
  #endif
}

float getLambertIntensity(Intersection i) {
  vec3 lightVec = normalize(LIGHT_POS - i.position);
  float diffuseTerm = dot(i.normal, lightVec);
  float ambientTerm = 0.2;
  return diffuseTerm + ambientTerm;  
}

float getSpecularIntensity(Intersection i, float spec) {
  vec3 lightVec = normalize(LIGHT_POS - i.position);
  vec3 viewVec = normalize(u_Eye - i.position);
  vec3 h = (lightVec + viewVec) / 2.0;
  return pow(max(dot(i.normal, h), 0.0), spec);
}

float softShadow(vec3 dir, vec3 origin, float min_t, float k) {
  float res = 1.0;
  float t = min_t;
  for( int i = 0; i < 40; i++) {
    float h = sceneSDF(origin + dir * t);
    res = min(res, smoothstep(0.0, 1.0, k * h / t));
    t += clamp(h, 0.01, 0.25);
    if(res < 0.005 || t > 10.0) break;
  }
  return clamp(res, 0.0, 1.0);
}

vec3 computeMaterial(Intersection i) {
  DirectionalLight lights[3];
  lights[0] = DirectionalLight(normalize(LIGHT_POS), WHITE_LIGHT);
  lights[1] = DirectionalLight(normalize(vec3(5, 10, 4)), YELLOW_LIGHT);
  lights[2] = DirectionalLight(normalize(vec3(-10, 0, -4)), FILL_LIGHT);

  vec3 albedo = vec3(0);

  if (i.material_id == FLOOR_ID) {
    albedo = rgb(60, 130, 0) * getLambertIntensity(i);
  } else if (i.material_id == FRIDGE_ID) {
    albedo = rgb(40, 210, 255) * getSpecularIntensity(i, 1.4);
  } else if (i.material_id == JUICE_WHITE_ID) {
    albedo = rgb(240, 240, 240) * getLambertIntensity(i);
  } else if (i.material_id == JUICE_ORANGE_ID) {
    albedo = rgb(240, 180, 40) * getLambertIntensity(i);
  } else if (i.material_id == BOTTLE_1_ID) {
    albedo = rgb(255, 190, 0) * getSpecularIntensity(i, 0.7);
  } else if (i.material_id == BOTTLE_2_ID) {
    albedo = rgb(230, 100, 0) * getSpecularIntensity(i, 0.7);
  } else if (i.material_id == BOTTLE_3_ID) {
    albedo = rgb(230, 20, 10) * getSpecularIntensity(i, 0.7);
  } else if (i.material_id == WATER_BOTTLE_ID) {
    albedo = rgb(150, 240, 255) * getSpecularIntensity(i, 1.5);
  } else if (i.material_id == TATA_HEAD_ID) {
    albedo = rgb(250, 40, 10) * getLambertIntensity(i);
  } else if (i.material_id == TATA_BODY_ID) {
    albedo = rgb(80, 80, 250) * getLambertIntensity(i);
  } else if (i.material_id == TATA_MOUTH_ID) {
    albedo = rgb(255, 190, 0) * getLambertIntensity(i);
  } else if (i.material_id == TATA_FACE_ID) {
    albedo = rgb(10, 10, 10) * getLambertIntensity(i);
  } else if (i.material_id == MILK_ID) {
    albedo = rgb(230, 230, 200) * getLambertIntensity(i);
  } else if (i.material_id == WATER_CAP_ID) {
    albedo = rgb(100, 100, 100) * getSpecularIntensity(i, 2.0);
  } else if (i.material_id == CAN_ID) {
    albedo = rgb(250, 20, 50) * getSpecularIntensity(i, 4.0);
  } else if (i.material_id == ICE_CREAM_TUB_ID) {
    albedo = rgb(140, 70, 20) * getLambertIntensity(i);
  } else if (i.material_id == JUICE_BOX_TOP_ID) {
    albedo = rgb(240, 100, 30) * getLambertIntensity(i);
  }

  vec3 lightVec = LIGHT_POS - i.position;
  float shadow = softShadow(normalize(lightVec), i.position, 0.001, 30.0);
  vec3 color = albedo * lights[0].color * max(0.0, dot(i.normal, lights[0].direction)) * shadow;
  for(int j = 1; j < 3; ++j) {
    color += albedo * lights[j].color * max(0.0, dot(i.normal, lights[j].direction));
  }
  color = pow(color, vec3(1.0 / 1.4));
  return color;
}

vec3 computeNormal(vec3 p) {
  vec2 off = vec2(0, EPSILON);
  return normalize(vec3(sceneSDF(p + off.yxx) - sceneSDF(p - off.yxx),
                        sceneSDF(p + off.xyx) - sceneSDF(p - off.xyx),
                        sceneSDF(p + off.xxy) - sceneSDF(p - off.xxy)));
}

Intersection getRaymarchedIntersection(vec2 uv)
{
  Ray ray = getRay(uv);
  Intersection intersection;
  intersection.distance_t = -1.0;
  intersection.object_hit = false;
  float t = EPSILON;
  int material_id;

  for (int step = 0; step < MAX_RAY_MARCH_STEPS; ++step) {  
    vec3 queryPos = ray.origin + t * ray.direction;

    #if CULL_RAY_LENGTH
    if (t > MAX_RAY_LENGTH) break;
    #endif

    float dist = sceneSDF(queryPos, material_id);

    if (dist <= EPSILON) {
      // intersection found!
      intersection.position = queryPos;
      intersection.distance_t = dist;
      intersection.normal = computeNormal(queryPos);
      intersection.material_id = material_id;
      intersection.object_hit = true;
      return intersection;
    }

    t += dist;
  }

  return intersection;
}

void main() {  
  Intersection i = getRaymarchedIntersection(fs_Pos);
  if (!i.object_hit) {
    out_Col = vec4(rgb(10, 20, 50), 1.0);
  } else {
    vec3 lightVec = LIGHT_POS - i.position;
    vec3 normal = i.normal;
    vec4 color = vec4(computeMaterial(i), 1.0);
    out_Col = vec4(color.rgb, 1.0);
  }
}