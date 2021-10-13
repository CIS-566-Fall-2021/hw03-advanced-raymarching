#version 300 es
precision highp float;

uniform vec3 u_Eye, u_Ref, u_Up;
uniform vec2 u_Dimensions;
uniform float u_Time;

in vec2 fs_Pos;
out vec4 out_Col;

const int MAX_RAY_STEPS = 256;
const float MAX_RAY_DISTANCE = 50.;
const float FOV = 45.0;
const float EPSILON = 1e-5;

const vec3 ORIGIN = vec3(0.0, 0.0, 0.0);
const vec3 WORLD_UP = vec3(0.0, 1.0, 0.0);
const vec3 WORLD_RIGHT = vec3(-1.0, 0.0, 0.0);
const vec3 WORLD_FORWARD = vec3(0.0, 0.0, 1.0);
const vec3 LIGHT_COL_1 = vec3(.2, .4, 1.);
const vec3 LIGHT_COL_2 = vec3(.4, .1, .2);
const vec3 LIGHT_COL_3 = vec3(.5, .5, .2);
const vec3 LIGHT_DIR_1 = vec3(1.0, .25, 1.0);
const vec3 LIGHT_DIR_2 = vec3(-1.0, 1.0, -1.0);
const vec3 LIGHT_DIR_3 = vec3(0.0, 3.0, 0.0);

#define MATERIAL_NONE 0.
#define MATERIAL_LAMBERT 1.
#define MATERIAL_BLINN 2.
#define MATERIAL_VELVET 3.

// The higher the value, the smaller the penumbra
const float SHADOW_HARDNESS = 7.0;
const vec3 SHADOW_COL = vec3(1., .2, .4);
// 0 for no, 1 for yes
#define SHADOW 1
#define ANIMATION 1
// 0 for penumbra shadows, 1 for hard shadows
#define HARD_SHADOW 0

//------------------------------------------------------------------

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
    float material_id;
    vec3 color;
};

//------------------------------------------------------------------

//TRANSFORMATIONS

vec3 rotateX(vec3 p, float a) {
    return vec3(p.x, cos(a) * p.y - sin(a) * p.z, sin(a) * p.y + cos(a) * p.z);
}

vec3 rotateY(vec3 p, float a) {
    return vec3(cos(a) * p.x + sin(a) * p.z, p.y, -sin(a) * p.x + cos(a) * p.z);
}

vec3 rotateZ(vec3 p, float a) {
    return vec3(cos(a) * p.x - sin(a) * p.y, sin(a) * p.x + cos(a) * p.y, p.z);
}

//------------------------------------------------------------------

//TOOLBOX FUNCTIONS & ADDITIONAL OPERATIONS

float ease_in_quadratic(float t)
{
  return t * t;
}

float ease_out_quadratic(float t)
{
  return 1. - ease_in_quadratic(1. - t);
}

float ease_in_out_quadratic(float t)
{
  if (t < .5) {
    return ease_in_quadratic(t * 2.) / 2.;
  }
  else {
    return 1. - ease_in_quadratic((1. - t) * 2.) / 2.; 
  }
}

float displacement(vec3 p)
{
    //no easing
    // p[0] += u_Time / 100.;
    // p[1] += u_Time / 80.;
    // p[2] += u_Time / 120.;
    // return sin(.5*p.x)*cos(.5*p.y)*sin(.5*p.z);

    //weird blobs dripping down
    // p[0] += u_Time / 100.;
    // p[1] += u_Time / 80.;
    // p[2] += u_Time / 120.;
    // return 2. * (1. - ease_in_out_quadratic(sin(.5*p.x)*cos(.5*p.y)*sin(.5*p.z)));

    //with easing
    #if ANIMATION
    float u_Time_new = ease_in_out_quadratic(sin(u_Time / 100.) * 20.);
    p[0] += u_Time_new / 100.;
    p[1] += u_Time_new / 80.;
    p[2] += u_Time_new / 120.;
    #endif
    p += .5;
    float b = 2.;
    return sin(b*p.x)*cos(b*p.y)*sin(b*p.z);
}

//add result to primitive(p)
float opDisplace(vec3 p)
{
    float d2 = displacement(p);
    return d2;
}

//result = primitive(q)
vec3 opCheapBend(vec3 p, float k)
{
    float c = cos(k*p.x);
    float s = sin(k*p.x);
    mat2  m = mat2(c,-s,s,c);
    vec3  q = vec3(m*p.xy,p.z);
    return q;
}

//result = primitive(q)
vec3 opRep(vec3 p, vec3 c)
{
    vec3 q = mod(p+0.5*c,c)-0.5*c;
    return q;
}

//------------------------------------------------------------------

float plane(vec3 p, vec4 n)
{
    return dot(p,n.xyz) + n.w;
}

float sdfSphere(vec3 query_position, vec3 position, float radius)
{
    return length(query_position - position) - radius;
}

float sdEllipsoid( vec3 p, vec3 r )
{
  float k0 = length(p/r);
  float k1 = length(p/(r*r));
  return k0*(k0-1.0)/k1;
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

float sdCappedCone(vec3 p, vec3 a, vec3 b, float ra, float rb)
{
    float rba  = rb-ra;
    float baba = dot(b-a,b-a);
    float papa = dot(p-a,p-a);
    float paba = dot(p-a,b-a)/baba;
    float x = sqrt( papa - paba*paba*baba );
    float cax = max(0.0,x-((paba<0.5)?ra:rb));
    float cay = abs(paba-0.5)-0.5;
    float k = rba*rba + baba;
    float f = clamp( (rba*(x-ra)+paba*baba)/k, 0.0, 1.0 );
    float cbx = x-ra - f*rba;
    float cby = paba - f;
    float s = (cbx < 0.0 && cay < 0.0) ? -1.0 : 1.0;
    return s*sqrt( min(cax*cax + cay*cay*baba,
                       cbx*cbx + cby*cby*baba) );
}

float sdCone( vec3 p, vec2 c, float h )
{
  // c is the sin/cos of the angle, h is height
  // Alternatively pass q instead of (c,h),
  // which is the point at the base in 2D
  vec2 q = h*vec2(c.x/c.y,-1.0);
    
  vec2 w = vec2( length(p.xz), p.y );
  vec2 a = w - q*clamp( dot(w,q)/dot(q,q), 0.0, 1.0 );
  vec2 b = w - q*vec2( clamp( w.x/q.x, 0.0, 1.0 ), 1.0 );
  float k = sign( q.y );
  float d = min(dot( a, a ),dot(b, b));
  float s = max( k*(w.x*q.y-w.y*q.x),k*(w.y-q.y)  );
  return sqrt(d)*sign(s);
}

float smin( float a, float b, float k )
{
    float h = clamp( 0.5+0.5*(b-a)/k, 0.0, 1.0 );
    return mix( b, a, h ) - k*h*(1.0-h);
}

float sdBox( vec3 p, vec3 b )
{
    vec3 d = abs(p) - b;
    return min(max(d.x,max(d.y,d.z)),0.0) + length(max(d,0.0));
}

float sceneSDF(vec3 queryPos, out float material, out vec3 color)
{
    float bounding_sphere_dist = sdfSphere(queryPos, vec3(0.), 5.);
    material = MATERIAL_NONE;
    color = vec3(0.);

    if ((queryPos.z < -3. || bounding_sphere_dist > .3) && queryPos.z > -10.) {
      // && queryPos.x > -2. && queryPos.x < 2.
      float t = 20.;
      float displace = displacement(queryPos) / 4.;
      // displace = 0.;
      float plane = plane(queryPos, vec4(0., .5, 0.25, 2.)) + displace;
      if (plane < t) {
        t = plane;
        material = MATERIAL_LAMBERT;
        color = vec3(.2, .4, 1.);
        vec3 newQueryPos = queryPos * .75;

        float sum = 0.;
        for (int i = 0; i < 3; i++) {
          // newQueryPos[i] = (mod(newQueryPos[i],2.) + 1. * displace) / 2.;
          // newQueryPos[i] = mod(newQueryPos[i],1.);
          newQueryPos[i] = (displace * 5.);
          float modres = mod(newQueryPos[i],1.);
          if (modres <= EPSILON) {
            newQueryPos[i] += 1.;
          }
          else {
            newQueryPos[i] += .5;
          }
          sum += newQueryPos[i];
        }
          // color = newQueryPos + (vec3(1., 0., 0.) - sum);
          // if (sum < 0.) {
            color = mix(newQueryPos, vec3(.9, .1, .2), 1. - sum / 2.);
            color += .2;
          // }
        return t;
      }
    }
    else if (bounding_sphere_dist < .3) {
      //TEMP TraNSLate
      // queryPos = queryPos + vec3(2., 0., 4.);
      // return smin(sdfSphere(queryPos, vec3(0.0, 0.0, 0.0), 0.2),
                  // sdfSphere(queryPos, vec3(cos(u_Time) * 2.0, 0.0, 0.0), abs(cos(u_Time))), 0.2);
      // return min(sdfSphere(queryPos, vec3(.0, .0, .0), 0.5), plane(queryPos, vec4(0., 1., 0., 0.)));

      //floor
      // float t = plane(queryPos, vec4(0., 2., 0., 4.));

    //BODY
      //chest
      // t = smin(t, sdfSphere(queryPos, vec3(.0, .0, .0), 0.5), .05);
      // t = smin(t, sdfSphere(queryPos, vec3(-.05, .0, -.05), 0.55), .05);
      float t = sdfSphere(queryPos, vec3(-.05, .0, -.05), 0.55);
      material = MATERIAL_VELVET;
      color = vec3(.1, .7, 1.5);
      //test // float t = sdfSphere(queryPos, vec3(-.0, -.0, -.0), 0.55);
      //torso
      t = smin(t, sdEllipsoid(rotateY(queryPos - vec3(-.35, -.05, -.35), .7), vec3(.8, .6, .6)), .05);
      //hindquarters
      t = smin(t, sdfSphere(queryPos, vec3(-.85, .0, -.85), 0.6), .05);

    //FRONT LEGS
      //front-right shoulder
      t = smin(t, sdRoundCone(rotateZ(rotateX(queryPos - vec3(-.2, -.25, .2), .25), .15), 0.25, .25, .6), .05);
      //front-right leg upper
      t = smin(t, sdRoundCone(rotateZ(rotateX(queryPos - vec3(-.35, -1., .35), .4), .2), 0.1, .15, .5), .05);
      //front-right leg knee
      t = smin(t, sdEllipsoid(rotateZ(rotateX(queryPos - vec3(-.4, -1.1, .4), .3), .1), vec3(0.1, .15, .1)), .05);
      //front-right leg lower
      t = smin(t, sdRoundCone(rotateZ(rotateX(queryPos - vec3(-.45, -1.7, .7), .55), .05), 0.11, .08, .5), .05);
      //front-right leg hoof
      // t = smin(t, sdEllipsoid(rotateZ(rotateX(queryPos - vec3(-.3, -1.9, .7), .3), .1), vec3(0.15, .1, .15)), .05);
      t = smin(t, sdCappedCone(queryPos - vec3(-.7, -1.8, .6), vec3(0.15, -.1, .15), vec3(0.2, .0, .2), .15, .05), .05);

      //front-left shoulder
      t = smin(t, sdRoundCone(rotateZ(rotateX(queryPos - vec3(.25, -.25, .0), .05), -.2), 0.25, .25, .6), .05);
      //front-left leg upper
      vec3 offset = vec3(.4, .0, -.4);
      t = smin(t, sdRoundCone(queryPos - vec3(-.15, -1., .35) - offset, 0.1, .15, .5), .05);
      //front-left leg knee
      t = smin(t, sdEllipsoid(queryPos - vec3(-.15, -1.1, .35) - offset, vec3(0.1, .15, .1)), .05);
      //front-left leg lower
      t = smin(t, sdRoundCone(queryPos - vec3(-.15, -1.7, .35) - offset, 0.11, .08, .5), .05);
      //front-left leg hoof
      // t = smin(t, sdEllipsoid(rotateZ(rotateX(queryPos - vec3(-.3, -1.9, .7), .3), .1), vec3(0.15, .1, .15)), .05);
      t = smin(t, sdCappedCone(queryPos - vec3(-.25, -1.8, .25) - offset, vec3(0.15, -.1, .15), vec3(0.2, .0, .2), .15, .05), .05);

    //BACK LEGS
      vec3 back_offset = vec3(-1., 0., -1.);
      //back-right shoulder
      // t = smin(t, sdRoundCone(rotateZ(rotateX(queryPos - vec3(.2, -.2, .2) - back_offset, -.25), -.15), 0.2, .3, .6), .05);
      //back-right leg upper
      t = smin(t, sdRoundCone(rotateZ(rotateX(queryPos - vec3(-.35, -1., .35) - back_offset, .4), .2), 0.1, .2, .5), .05);
      //back-right leg knee
      t = smin(t, sdEllipsoid(rotateZ(rotateX(queryPos - vec3(-.4, -1.1, .4) - back_offset, .3), .1), vec3(0.1, .15, .1)), .05);
      //back-right leg lower
      t = smin(t, sdRoundCone(rotateZ(rotateX(queryPos - vec3(-.45, -1.7, .7) - back_offset, .55), .05), 0.11, .08, .5), .05);
      //back-right leg hoof
      // t = smin(t, sdEllipsoid(rotateZ(rotateX(queryPos - vec3(-.3, -1.9, .7), .3), .1), vec3(0.15, .1, .15)), .05);
      t = smin(t, sdCappedCone(queryPos - vec3(-.7, -1.8, .6) - back_offset, vec3(0.15, -.1, .15), vec3(0.2, .0, .2), .15, .05), .05);

      //back-left shoulder
      // t = smin(t, sdRoundCone(rotateZ(rotateX(queryPos - vec3(.25, -.2, .05) - back_offset, .05), -.2), 0.3, .25, .6), .05);
      //back-left leg upper
      t = smin(t, sdRoundCone(queryPos - vec3(-.15, -1., .35) - back_offset - offset, 0.1, .2, .5), .05);
      //back-left leg knee
      t = smin(t, sdEllipsoid(queryPos - vec3(-.15, -1.1, .35) - back_offset - offset, vec3(0.1, .15, .1)), .05);
      //back-left leg lower
      t = smin(t, sdRoundCone(queryPos - vec3(-.15, -1.7, .35) - back_offset - offset, 0.11, .08, .5), .05);
      //back-left leg hoof
      // t = smin(t, sdEllipsoid(rotateZ(rotateX(queryPos - vec3(-.3, -1.9, .7), .3), .1), vec3(0.15, .1, .15)), .05);
      t = smin(t, sdCappedCone(queryPos - vec3(-.25, -1.8, .25) - back_offset - offset, vec3(0.15, -.1, .15), vec3(0.2, .0, .2), .15, .05), .05);


      //NECK
      t = smin(t, sdRoundCone(rotateX(queryPos - vec3(0., .3, 0.), -.5), 0.41, .28, .55), .05);
      t = smin(t, sdRoundCone(rotateX(queryPos - vec3(-.05, .9, .35), -1.), 0.24, .22, .35), .1);

      //HEAD
      t = smin(t, sdfSphere(queryPos, vec3(-.07, .95, .6), .25), .05);
      t = smin(t, sdRoundCone(rotateX(queryPos - vec3(-.07, .9, .6), -3.), 0.24, .15, .35), .05);
      t = smin(t, sdRoundCone(rotateX(queryPos - vec3(-.07, .8, .6), -3.), 0.14, .1, .35), .05);

      //EARS
      // t = smin(t, sdRoundCone(rotateY(rotateZ(rotateX(queryPos - vec3(-.07, 1., .6), -2.), -1.5), -10.), 0.07, .05, .5), .05);
      t = smin(t, sdRoundCone(rotateX(queryPos - vec3(-.2, 1.2, .8), -1.), 0.07, .01, .25), .05);
      t = smin(t, sdRoundCone(rotateX(queryPos - vec3(.1, 1.2, .7), -1.), 0.07, .01, .25), .05);

      //FLOOR
      // float t = 100.;
      // float t = plane(queryPos, vec4(0., 1., 0.2, 4.)) + displacement(queryPos);
      // float plane = plane(queryPos, vec4(0., 1., 0.5, 2.)) + displacement(queryPos);
      float displace = displacement(queryPos) / 4.;
      // displace = 0.;
      float plane = plane(queryPos, vec4(0., .5, 0., 1.15)) + displace;
      if (plane < t) {
        t = plane;
        material = MATERIAL_LAMBERT;
        color = vec3(.2, .4, 1.);
        vec3 newQueryPos = queryPos * .75;

        float sum = 0.;
        for (int i = 0; i < 3; i++) {
          // newQueryPos[i] = (mod(newQueryPos[i],2.) + 1. * displace) / 2.;
          // newQueryPos[i] = mod(newQueryPos[i],1.);
          newQueryPos[i] = (displace * 5.);
          float modres = mod(newQueryPos[i],1.);
          if (modres <= EPSILON) {
            newQueryPos[i] += 1.;
          }
          else {
            newQueryPos[i] += .5;
          }
          sum += newQueryPos[i];
        }
          // color = newQueryPos + (vec3(1., 0., 0.) - sum);
          // if (sum < 0.) {
            color = mix(newQueryPos, vec3(.9, .1, .2), 1. - sum / 2.);
            color += .2;
          // }
      }

      // // PLANT (its ugly so nvm..)
      // // float k = sin(u_Time / 20.) * 10.;
      // float k = sin(u_Time / 20.);
      // // float leaf = sdCone(opCheapBend(queryPos - vec3(1., 1., 0.), k), vec2(.1, .9), 1.);
      // float leaf = sdCone(queryPos - vec3(1., 1., 0.), vec2(.1, .9), 1.);
      // if (leaf < t) { 
      //   t = leaf;
      //   material = MATERIAL_BLINN;
      //   color = vec3(0., .5, 0.);
      // }

      // float t = sdfSphere(opRep(queryPos, vec3(5.)), vec3(-1.), .5);
      // t = min(t, sdfSphere(opRep(queryPos, vec3(5.)), vec3(-1.), .5));
      // t = min(t, sdCone(opRep(queryPos - vec3(.7, .1, .1), vec3(7.)), vec2(1., 10.), 4.));

      return t;
    }
    return bounding_sphere_dist;
}

//------------------------------------------------------------------------------------------------------------------

Ray getRay(vec2 uv)
{
    Ray r;
    
    vec3 look = normalize(u_Ref - u_Eye);
    vec3 camera_RIGHT = normalize(cross(look, WORLD_UP));
    vec3 camera_UP = cross(camera_RIGHT, look);
    
    float aspect_ratio = u_Dimensions.x / u_Dimensions.y;
    vec3 screen_vertical = camera_UP * tan(FOV); 
    vec3 screen_horizontal = camera_RIGHT * aspect_ratio * tan(FOV);
    vec3 screen_point = (look + uv.x * screen_horizontal + uv.y * screen_vertical);
    
    r.origin = u_Eye;
    r.direction = normalize(screen_point - u_Eye);

    return r;
}

vec3 calcNormal(vec3 pos)
{
  vec3 eps = vec3(EPSILON,0.0,0.0);
  float mat;
  vec3 color;
	return normalize( vec3(
           sceneSDF(pos+eps.xyy, mat, color) - sceneSDF(pos-eps.xyy, mat, color),
           sceneSDF(pos+eps.yxy, mat, color) - sceneSDF(pos-eps.yxy, mat, color),
           sceneSDF(pos+eps.yyx, mat, color) - sceneSDF(pos-eps.yyx, mat, color) ) );
}

Intersection getRaymarchedIntersection(vec2 uv)
{
    Ray ray = getRay(uv);
    float distance = EPSILON;
    Intersection intersection;
    for (int steps = 0; steps < MAX_RAY_STEPS; steps++) {
      if (distance > MAX_RAY_DISTANCE) {
        break;
      }
      vec3 test_point = ray.origin + distance * ray.direction;
      float material = MATERIAL_NONE;
      vec3 color = vec3(0.);
      float remaining_dist = sceneSDF(test_point, material, color);
      if (remaining_dist <= EPSILON) {
        intersection.position = test_point;
        intersection.distance_t = distance;
        intersection.normal = calcNormal(test_point);
        intersection.material_id = material;
        intersection.color = color;
        return intersection;
      } else {
        distance += remaining_dist;
      }
    }
    intersection.distance_t = -1.0;
    return intersection;
}

float hardShadow(vec3 dir, vec3 origin, float min_t) {
    float t = min_t;
    float mat;
    vec3 color;
    for(int i = 0; i < MAX_RAY_STEPS; ++i) {
        float m = sceneSDF(origin + t * dir, mat, color);
        if(m < EPSILON) {
            return 0.0;
        }
        t += m;
    }
    return 1.0;
}

float softShadow(vec3 dir, vec3 origin, float min_t, float k) {
    // float res = 1.0;
    // float t = min_t;
    // for(int i = 0; i < MAX_RAY_STEPS; ++i) {
    //     float m = sceneSDF(origin + t * dir).x;
    //     if(m < EPSILON) {
    //         return 0.0;
    //     }
    //     res = min(res, k * m / t);
    //     t += m;
    // }
    // return res;

    float res = 1.0;
    float t = min_t;
    float mat;
    vec3 color;
    for( int i=0; i< MAX_RAY_STEPS; i++ )
    {
        float h = sceneSDF(origin + dir*t, mat, color);
        res = min( res, smoothstep(0.0,1.0,k*h/t) );
		t += clamp( h, 0.01, 0.25 );
		if( res<0.005 || t>10.0 ) break;
    }
    return clamp(res,0.0,1.0);
}

float shadow(vec3 dir, vec3 origin, float min_t) {
    #if HARD_SHADOW
    return hardShadow(dir, origin, min_t);
    #else
    return softShadow(dir, origin, min_t, SHADOW_HARDNESS);
    #endif
}

vec3 getLambertColor(Intersection intersection, vec3 lightColor, vec3 lightDirection, float ambientTerm)
{ 
    vec3 surfaceColor = intersection.color;
    // Calculate the diffuse term for Lambert shading
    float diffuseTerm = dot(normalize(intersection.normal), normalize(lightDirection));
    // Avoid negative lighting values
    diffuseTerm = clamp(diffuseTerm, 0., 1.);

    float lightIntensity = diffuseTerm + ambientTerm;   //Add a small float value to the color multiplier
                                                        //to simulate ambient lighting. This ensures that faces that are not
                                                        //lit by our point light are not completely black.

    // Compute final shaded color
    return surfaceColor * lightColor * lightIntensity;
}

vec3 getBlinnPhongColor(Intersection intersection, vec3 lightColor, vec3 lightDirection, float ambientTerm)
{ 
    vec3 surfaceColor = intersection.color;
    float diffuseTerm = dot(normalize(intersection.normal), normalize(lightDirection));
    diffuseTerm = clamp(diffuseTerm, 0., 1.);

    float lightIntensity = diffuseTerm + ambientTerm;

    vec3 v = u_Eye - intersection.position;
    vec3 h = (v + lightDirection) / 2.;
    float specularIntensity = max(pow(dot(normalize(h),normalize(intersection.normal)),100.f),0.f);

    return surfaceColor * lightColor * lightIntensity + specularIntensity;
}

vec3 getVelvetColor(Intersection intersection, vec3 lightColor, vec3 lightDirection, float ambientTerm)
{ 
    vec3 surfaceColor = intersection.color;
    // float diffuseTerm = dot(normalize(intersection.normal), normalize(diffuseDirection));
    // diffuseTerm = clamp(diffuseTerm, 0., 1.);

    // float lightIntensity = diffuseTerm + ambientTerm;
    
    float backscatter = 0.25;
    float edginess = 4.0;
    float sheen = 0.7;
    float roughness = 0.9;

    vec3 V = normalize(u_Eye - intersection.position);
    vec3 N = normalize(intersection.normal);
    vec3 L = normalize(lightDirection);

    float diffuseTerm = max(dot(L, N), 0.0);

    float cosine = max(dot(L, V), 0.0);
    float shiny = sheen * pow(cosine, 1.0 / roughness) * backscatter;

    cosine = max(dot(N, V), 0.0);
    float sine = sqrt(1.0 - cosine);
    shiny = shiny + sheen * pow(sine, edginess) * diffuseTerm;

    float specularTerm = 1.;

    return ambientTerm + (diffuseTerm * surfaceColor * lightColor) + (specularTerm * shiny);
}

vec3 getSceneColor(vec2 uv, out bool hitSomething)
{
    Intersection intersection = getRaymarchedIntersection(uv);
    hitSomething = false;
    if (intersection.distance_t > 0.0)
    {
        //return vec3(1.0f);
        // return intersection.normal;

        // vec3 finalColor = (getLambertColor(intersection, LIGHT_COL_1, LIGHT_DIR_1, .2) + getLambertColor(intersection, LIGHT_COL_2, LIGHT_DIR_2, .2)) / 2.;
        // for (int i = 0; i < 3; i++) {
        //   finalColor[i] = clamp(finalColor[i], 0., 1.);
        // }
        // return finalColor;
        
        // + intersection.normal * .001

        if (abs(intersection.material_id - MATERIAL_LAMBERT) <= EPSILON) {
          hitSomething = true;
          #if SHADOW
          return getLambertColor(intersection, LIGHT_COL_1, LIGHT_DIR_1, .2) * shadow(LIGHT_DIR_1, intersection.position + normalize(intersection.normal) * EPSILON, .1) * vec3(1., .8, .8)
                + getLambertColor(intersection, LIGHT_COL_2, LIGHT_DIR_2, .2)
                + getLambertColor(intersection, LIGHT_COL_3, LIGHT_DIR_3, .2);
          #else
          return getLambertColor(intersection, LIGHT_COL_1, LIGHT_DIR_1, .2)
                + getLambertColor(intersection, LIGHT_COL_2, LIGHT_DIR_2, .2)
                + getLambertColor(intersection, LIGHT_COL_3, LIGHT_DIR_3, .2);
          #endif
        }
        else if (abs(intersection.material_id - MATERIAL_BLINN) <= EPSILON) {
          hitSomething = true;
          #if SHADOW
          return getBlinnPhongColor(intersection, LIGHT_COL_1, LIGHT_DIR_1, .2) * shadow(LIGHT_DIR_1, intersection.position + normalize(intersection.normal) * EPSILON, .1) * vec3(1., .8, .8)
                + getBlinnPhongColor(intersection, LIGHT_COL_2, LIGHT_DIR_2, .2)
                + getBlinnPhongColor(intersection, LIGHT_COL_3, LIGHT_DIR_3, .2);
          #else
          return getBlinnPhongColor(intersection, LIGHT_COL_1, LIGHT_DIR_1, .2)
                + getBlinnPhongColor(intersection, LIGHT_COL_2, LIGHT_DIR_2, .2)
                + getBlinnPhongColor(intersection, LIGHT_COL_3, LIGHT_DIR_3, .2);
          #endif
        } else if (abs(intersection.material_id - MATERIAL_VELVET) <= EPSILON) {
          hitSomething = true;
          #if SHADOW
          return getVelvetColor(intersection, LIGHT_COL_1, LIGHT_DIR_1, .2) * shadow(LIGHT_DIR_1, intersection.position + normalize(intersection.normal) * EPSILON, .1) * vec3(1., .8, .8)
                + .25 * getVelvetColor(intersection, LIGHT_COL_2, LIGHT_DIR_2, .2)
                + .25 * getVelvetColor(intersection, LIGHT_COL_3, LIGHT_DIR_3, .2);
          #else
          return getVelvetColor(intersection, LIGHT_COL_1, LIGHT_DIR_1, .2)
                + .25 * getVelvetColor(intersection, LIGHT_COL_2, LIGHT_DIR_2, .2)
                + .25 * getVelvetColor(intersection, LIGHT_COL_3, LIGHT_DIR_3, .2);
          #endif
        }
     }
     return vec3(0.0f);
}

void main() {
  bool hitSomething = true;
    vec3 sceneColor = getSceneColor(vec2(fs_Pos), hitSomething);
    if (!hitSomething) {
      // out_Col = vec4(.2, .4, 1., .1);
      out_Col = mix(vec4(1., 1., .5, 1.), vec4(1., .5, .4, 1.), fs_Pos.y + .5) + .2;
      // out_Col = vec4(sceneColor, 1.);
    }
    else {
      out_Col = vec4(sceneColor, 1.);
    }
}
