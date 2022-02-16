#version 300 es

//****** Data *******/
#define num_mat
#define TEETH 1
#define AXIS 2
#define FLOOR 3

#define tmax 5
#define EPSILON 1e-3
#define PI2 6.283185
#define MAX_DIS 999.0
precision highp float;
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

struct Material {
    vec3 ambient;//ambient color
    vec3 diffuse;//diffuse color
    vec3 specular;//specular color
    float shininess;//shininess value
    //vec3 a,b,c,d;//cosine value
}; 

struct SDFRes
{
    float distance_t; // distance
    int material_id; // material
};
const Material mat_teeth = Material(vec3(0.4667, 0.8118, 0.3059),
            vec3(1.0, 0.6902, 0.9843),
            vec3(1.0, 1.0, 1.0),
            15.0);
const Material mat_axis = Material(vec3(0.9725, 0.2863, 0.2863),
            vec3(0.4863, 0.4941, 0.8941),
            vec3(1.0, 1.0, 1.0),
            10.0);         
const Material mat_floor = Material(vec3(1.0, 0.6431, 0.6431),
            vec3(0.4863, 0.4941, 0.8941),
            vec3(1.0, 1.0, 1.0),
            2.0);         
const vec3 LIGHT_DIR = vec3(-1.0, 1.0, 2.0);

//******* Data End*******/
    vec4 mod289(vec4 x) {
        return x - floor(x * (1.0 / 289.0)) * 289.0;
    }
    vec3 mod289(vec3 x) {
        return x - floor(x * (1.0 / 289.0)) * 289.0;
    }

    vec2 mod289(vec2 x) {
        return x - floor(x * (1.0 / 289.0)) * 289.0;
    }

    float mod289(float x) {
        return x - floor(x * (1.0 / 289.0)) * 289.0; 
    }

    float permute(float x) {
        return mod289(((x*34.0)+1.0)*x);
    }

    vec3 permute(vec3 x) {
        return mod289(((x*34.0)+1.0)*x);
    }

    vec4 permute(vec4 x) {
        return mod289(((x*34.0)+1.0)*x);
    }

    float snoise(vec3 v)
    { 
        const vec2  C = vec2(1.0/6.0, 1.0/3.0) ;
        const vec4  D = vec4(0.0, 0.5, 1.0, 2.0);

        // First corner
        vec3 i  = floor(v + dot(v, C.yyy) );
        vec3 x0 =   v - i + dot(i, C.xxx) ;

        // Other corners
        vec3 g = step(x0.yzx, x0.xyz);
        vec3 l = 1.0 - g;
        vec3 i1 = min( g.xyz, l.zxy );
        vec3 i2 = max( g.xyz, l.zxy );

        //   x0 = x0 - 0.0 + 0.0 * C.xxx;
        //   x1 = x0 - i1  + 1.0 * C.xxx;
        //   x2 = x0 - i2  + 2.0 * C.xxx;
        //   x3 = x0 - 1.0 + 3.0 * C.xxx;
        vec3 x1 = x0 - i1 + C.xxx;
        vec3 x2 = x0 - i2 + C.yyy; // 2.0*C.x = 1/3 = C.y
        vec3 x3 = x0 - D.yyy;      // -1.0+3.0*C.x = -0.5 = -D.y

        // Permutations
        i = mod289(i); 
        vec4 p = permute( permute( permute( 
        i.z + vec4(0.0, i1.z, i2.z, 1.0 ))
        + i.y + vec4(0.0, i1.y, i2.y, 1.0 )) 
        + i.x + vec4(0.0, i1.x, i2.x, 1.0 ));

        // Gradients: 7x7 points over a square, mapped onto an octahedron.
        // The ring size 17*17 = 289 is close to a multiple of 49 (49*6 = 294)
        float n_ = 0.142857142857; // 1.0/7.0
        vec3  ns = n_ * D.wyz - D.xzx;

        vec4 j = p - 49.0 * floor(p * ns.z * ns.z);  //  mod(p,7*7)

        vec4 x_ = floor(j * ns.z);
        vec4 y_ = floor(j - 7.0 * x_ );    // mod(j,N)

        vec4 x = x_ *ns.x + ns.yyyy;
        vec4 y = y_ *ns.x + ns.yyyy;
        vec4 h = 1.0 - abs(x) - abs(y);

        vec4 b0 = vec4( x.xy, y.xy );
        vec4 b1 = vec4( x.zw, y.zw );

        //vec4 s0 = vec4(lessThan(b0,0.0))*2.0 - 1.0;
        //vec4 s1 = vec4(lessThan(b1,0.0))*2.0 - 1.0;
        vec4 s0 = floor(b0)*2.0 + 1.0;
        vec4 s1 = floor(b1)*2.0 + 1.0;
        vec4 sh = -step(h, vec4(0,0,0,0));

        vec4 a0 = b0.xzyw + s0.xzyw*sh.xxyy ;
        vec4 a1 = b1.xzyw + s1.xzyw*sh.zzww ;

        vec3 p0 = vec3(a0.xy,h.x);
        vec3 p1 = vec3(a0.zw,h.y);
        vec3 p2 = vec3(a1.xy,h.z);
        vec3 p3 = vec3(a1.zw,h.w);

        //Normalise gradients
        vec4 norm =  1.79284291400159 - 0.85373472095314 * vec4(dot(p0,p0), dot(p1,p1), dot(p2, p2), dot(p3,p3));
        p0 *= norm.x;
        p1 *= norm.y;
        p2 *= norm.z;
        p3 *= norm.w;

        // Mix final noise value
        vec4 m = max(0.6 - vec4(dot(x0,x0), dot(x1,x1), dot(x2,x2), dot(x3,x3)), 0.0);
        m = m * m;
        return 42.0 * dot( m*m, vec4( dot(p0,x0), dot(p1,x1), 
        dot(p2,x2), dot(p3,x3) ) );
    }



/******* SDF Geometry *******/

// smooth blend
    float smin( float a, float b, float k )
    {
        float h = clamp( 0.5+0.5*(b-a)/k, 0.0, 1.0 );
        return mix( b, a, h ) - k*h*(1.0-h);
    }

    float smax( float a, float b, float k )
    {
        float h = max(k-abs(a-b),0.0);
        return max(a, b) + h*h*0.25/k;
    }

    float sdBoxFrame( vec3 p, vec3 b, float e )
    {
    p = abs(p  )-b;
    vec3 q = abs(p+e)-e;
    return min(min(
        length(max(vec3(p.x,q.y,q.z),0.0))+min(max(p.x,max(q.y,q.z)),0.0),
        length(max(vec3(q.x,p.y,q.z),0.0))+min(max(q.x,max(p.y,q.z)),0.0)),
        length(max(vec3(q.x,q.y,p.z),0.0))+min(max(q.x,max(q.y,p.z)),0.0));
    }

/******* SDF Geometry End *******/

/******* SceneSDF *******/
float sdTriangle(vec2 p, vec2 p0, vec2 p1, vec2 p2 )
{
	vec2 e0 = p1 - p0;
	vec2 e1 = p2 - p1;
	vec2 e2 = p0 - p2;

	vec2 v0 = p - p0;
	vec2 v1 = p - p1;
	vec2 v2 = p - p2;

	vec2 pq0 = v0 - e0*clamp( dot(v0,e0)/dot(e0,e0), 0.0, 1.0 );
	vec2 pq1 = v1 - e1*clamp( dot(v1,e1)/dot(e1,e1), 0.0, 1.0 );
	vec2 pq2 = v2 - e2*clamp( dot(v2,e2)/dot(e2,e2), 0.0, 1.0 );
    
    float s = e0.x*e2.y - e0.y*e2.x;
    vec2 d = min( min( vec2( dot( pq0, pq0 ), s*(v0.x*e0.y-v0.y*e0.x) ),
                       vec2( dot( pq1, pq1 ), s*(v1.x*e1.y-v1.y*e1.x) )),
                       vec2( dot( pq2, pq2 ), s*(v2.x*e2.y-v2.y*e2.x) ));

	return -sqrt(d.x)*sign(d.y);
}
#define GEAR_SECTOR 24.0
#define GRID_SIZE 1.
float star(vec2 p){
    float d = 9999.;
    float k = 0.03;
    float h = 0.14;
    //float triangle = sdTriangle(p.xy,vec2(-k,0.),vec2(k,0.),vec2(0.0,h));

    return d;
}
float sdBox( in vec3 p, in vec3 r )
{
    return length( max(abs(p)-r,0.0) );
}
SDFRes gearSDF(vec3 p)
{
    SDFRes r;
    int id;
    float w = 0.25;
    float lpxy=length(p.xy);
    float d=10000.;
    float ang=atan(p.y,p.x);
    float outer_radius = 0.5*(sin(PI2/8.)*0.5+0.015);
    float height = 0.02;
    float inner_radius = 0.13;

    float sdf;
    sdf = length(p+vec3(p.xy/lpxy,0.)*.015*sin(ang*GEAR_SECTOR))-outer_radius;
    // basic outer ring & teeth 
    if(d>sdf){
        d = sdf;
        id = 1;
    }
    sdf = inner_radius-lpxy;
    if(d<sdf)
        d = sdf;

    //d = smin(d,star(p.xy),0.02);
    vec3 q = p;
    const float an = PI2/GEAR_SECTOR*2.0;
    float sector = round(ang/an);
    float torot = an*sector;
    q.xy = mat2(cos(torot),-sin(torot),
                sin(torot), cos(torot))*q.xy;    
    // d=smin(d, length(p.xy)-0.055,0.001);
    // d=smax(d, 0.02-lpxy,0.001);

    sdf = sdBox(q,vec3(0.13,0.004,0.02));
    if(d>sdf)
    {
        d = sdf;
        id = 2;
    }
    d=max(d,abs(p.z)-height);
    r.distance_t = d;
    r.material_id = id;
    return r;
}
float heightField(vec3 p, float planeHeight)
{
    return p.y - planeHeight;
}
float sdfSphere(vec3 query_position, vec3 position, float radius)
{
    return length(query_position - position) - radius;
}

/**Some math **/
    vec4 inverseQuat(vec4 q)
    {
        return vec4(-q.xyz,q.w);
    }

    vec4 multQuat(vec4 a, vec4 b)
    {
        return vec4(cross(a.xyz,b.xyz) + a.xyz*b.w + b.xyz*a.w, a.w*b.w - dot(a.xyz,b.xyz));
    }

    vec3 transformVecByQuat( vec3 v, vec4 q )
    {
        return v + 2.0 * cross( q.xyz, cross( q.xyz, v ) + q.w*v );
    }

    vec4 axAng2Quat(vec3 ax, float ang)
    {
        return vec4(normalize(ax),1)*sin(vec2(ang*.5)+vec2(0,PI2*.25)).xxxy;
    }
/**Some math end **/

#define Z_AXIS vec3(0.0,0.0,1.0)
#define X_AXIS vec3(1.0,0.0,0.0)
#define Y_AXIS vec3(0.0,1.0,0.0)

SDFRes gearRepeat(vec3 p){
    SDFRes r;
    vec4 q = axAng2Quat(Z_AXIS,0.02*u_Time);
    vec3 p1 = transformVecByQuat(p,q);

    SDFRes r1 = gearSDF(p1);
    float g1 = r1.distance_t;


    q = axAng2Quat(Z_AXIS,-0.02*u_Time);
    vec3 p2 = transformVecByQuat(p+vec3(0.5-0.315,-0.315,0.),q);
    SDFRes r2 = gearSDF(p2);
    float g2 = r2.distance_t;


    vec3 p3 = p+vec3(0.5,-0.5,0.);
    q = axAng2Quat(Z_AXIS,0.02*u_Time);
    p3 = transformVecByQuat(p3,q);
    SDFRes r3 = gearSDF(p3);
    float g3 = r3.distance_t;

    if(g1<g2){
        r = r1;
    }
    else{
        r = r2;
    }
    if(r.distance_t>g3){
        r = r3;
    }
    return r;
}


SDFRes gearRepeat2(vec3 p){
    
    SDFRes r;
    vec4 q_time = axAng2Quat(Z_AXIS,-0.02*u_Time);
    vec4 q;
    q =  multQuat(q_time,axAng2Quat(Y_AXIS,PI2/4.));
    vec3 p1 = transformVecByQuat(p,q);
    
    SDFRes r1 = gearSDF(p1);
    float g1 = gearSDF(p1).distance_t;


    q_time = axAng2Quat(Z_AXIS,0.02*u_Time);
    q =  multQuat(q_time,axAng2Quat(Y_AXIS,PI2/4.));
    q = multQuat(q,axAng2Quat(Z_AXIS,-PI2/8.+0.01));
    vec3 p2 = transformVecByQuat(0.92*p+vec3(0.5-0.34,-0.32,0.),q);
    SDFRes r2 = gearSDF(p2);
    float g2 = gearSDF(p2).distance_t;



    vec3 p3 = p+vec3(0.5,-0.5,0.);
    q_time = axAng2Quat(Z_AXIS,0.02*u_Time);
    q =  multQuat(q_time,axAng2Quat(X_AXIS,PI2/4.)); 
    p3 = transformVecByQuat(p3,q);
    
    SDFRes r3 = gearSDF(p3);
    float g3 = gearSDF(p3).distance_t;

    if(g1<g2){
        r = r1;
    }
    else{
        r = r2;
    }
    if(r.distance_t>g3){
        r = r3;
    }
    return r;                                                                 
}

SDFRes firstset(vec3 p){
    
    p = p + vec3(0.,0.5,0.);
    SDFRes res = gearRepeat(p);

    vec3 p0 = p*vec3(-1.,1.,1.);
    SDFRes r1 = gearRepeat(p0.zyx+vec3(-0.5,-0.5,0.));
    if(res.distance_t>r1.distance_t){
        res = r1;
    }

    vec3 p1 = p*vec3(-1.,1.,1.);
    r1 = gearRepeat(p1.xzy+vec3(0.,0.5,-0.5));
    if(res.distance_t>r1.distance_t){
         res = r1;
    }

    return res;
}

SDFRes secondset(vec3 p){
    
    p = p + vec3(0.,0.5,0.);
    SDFRes res = gearRepeat2(p);

    vec3 p1 = p*vec3(-1.,1.,1.);
    SDFRes r1 = gearRepeat2(p1.xzy+vec3(0.,0.5,-0.5));
    if(res.distance_t>r1.distance_t){
        res = r1;
    }

    vec3 p0 = p *(-1.,1.,-1.);
    r1 = gearRepeat2(p0.zyx+vec3(0.,1.0,0.));
    if(res.distance_t>r1.distance_t){
         res = r1;
    }
    
    return res;
}

//#define showtile
#define combined    
//#define showgear

SDFRes sceneSDF(vec3 p){
    
    SDFRes res;
    res.distance_t = MAX_DIS;

    // bounding sphere
    if(sdfSphere(p, vec3(0.0, 0.0, 0.0), 20.0) < .5 ){
        float d;
        vec3 mod_p;
        mod_p = fract(p)-0.5;
        // calculate checkerboard
        vec3 id = floor(mod(p,2.))*2.-1.;
        float checker = id.x*id.y*id.z;
        //mod_p = p-0.5;

        #ifdef combined
        float second_checker = id.x;
        if(second_checker==1.){
            SDFRes r = firstset(-checker*mod_p);
            if(res.distance_t>r.distance_t){
                res = r;
            }
        
        }
        else{
            SDFRes r = secondset(checker*mod_p);
            if(res.distance_t>r.distance_t){
                res = r;
            }
        }
        #endif /* combined */

        #ifdef showtile
        SDFRes r = secondset(p+vec3(1.0,0.,0.));
        if(res.distance_t>r.distance_t){
            res = r;
        }
        r = firstset(p);
        if(res.distance_t>r.distance_t){
            res = r;
        }
        float box1 = sdBoxFrame(p, vec3(0.5), 0.025 );
        float box2 = sdBoxFrame(p+vec3(1.0,0.0,0.0), vec3(0.5), 0.025 );
        d = min(box1,box2);
        if(res.distance_t>min(box1,box2)){
            res.distance_t = d;
            res.material_id = 0;
        }
        
        #endif /* showtile */

        #ifdef showgear
        SDFRes r = secondset(p+vec3(1.0,0.,0.));
        if(res.distance_t>r.distance_t){
            res = r;
        }
        r = firstset(p);
        if(res.distance_t>r.distance_t){
            res = r;
        }
        #endif /* showgear */

        // add plane 
        d = heightField(p, -.8);
        if(res.distance_t>d){
            res.distance_t = d;
            res.material_id = FLOOR;
        }
    }
    return res;
}

float hardShadow(vec3 rayOrigin, vec3 rayDirection)
{
    for(float t = 0.; t < 15.; )
    {
        float h = sceneSDF(rayOrigin + rayDirection * t).distance_t;
        if(h < EPSILON)
        {
            return 0.0;
        }
        t += h;
    }

    return 1.0;
}

float softShadow(vec3 ro, vec3 rd){
    float res = 1.0, t = 0.1; 
    for(int s = 0; s < 15; ++s){
        float h = sceneSDF(ro + rd*t).distance_t;
        if(h < 0.001) return 0.0;
        res = min( res, 8.0*h/t );
        t += h*0.9;
    }
    return res;
}
/******* SceneSDF End*******/

/******* Ray march*******/
mat3 setCamera( in vec3 ro, in vec3 ta, float cr )
{
	vec3 cw = normalize(ta-ro);
	vec3 cp = vec3(sin(cr), cos(cr),0.0);
	vec3 cu = normalize( cross(cw,cp) );
	vec3 cv =          ( cross(cu,cw) );
    return mat3( cu, cv, cw );
}

Ray getRay(vec2 p){
  float fov = 45.;
  float len = length(u_Ref - u_Eye);
  float aspect = u_Dimensions.x / u_Dimensions.y;

  vec3 look = normalize(u_Ref - u_Eye);
  vec3 R = normalize(cross(look, u_Up));
  vec3 U = cross(R, look);
  
  vec3 V = U*len*tan(fov/2.);
  vec3 H = R*len*aspect*tan(fov/2.); 

  vec3 sp =  look + p.x * H + p.y * V;
  
  Ray r;

  r.direction = normalize(sp-u_Eye);
  r.origin = u_Eye;
  #ifdef combined
  float an = 0.01*u_Time;
  r.origin += vec3(cos(u_Time*0.01),5.0+sin(u_Time*0.01),8.0+sin(u_Time*0.01));
  vec3 ta = vec3( 0.0, 0.0, 0.0 );
  vec3 ro = 0.005*sin(u_Time*0.01+vec3(0.0,1.0,3.0));
  ta += 0.009*cos(u_Time*0.005+vec3(2.0,4.0,6.0));
  mat3 ca = setCamera( ro, ta, 0.0 );
  r.direction = ca * r.direction;
  #endif

  return r;
}

vec3 estimateNormal(vec3 p) {
    float x =  sceneSDF(vec3(p.x + EPSILON, p.y, p.z)).distance_t - sceneSDF(vec3(p.x - EPSILON, p.y, p.z)).distance_t;
    float z = sceneSDF(vec3(p.x, p.y, p.z  + EPSILON)).distance_t - sceneSDF(vec3(p.x, p.y, p.z - EPSILON)).distance_t;
    float y = sceneSDF(vec3(p.x, p.y + EPSILON, p.z)).distance_t - sceneSDF(vec3(p.x, p.y - EPSILON, p.z)).distance_t;
    return normalize(vec3(x,y,z));
}

Intersection getRaymarchedIntersection(vec2 uv)
{
    Ray r = getRay(uv);
    Intersection intersection;
    int MAX_MARCHING_STEPS = 128;
    float depth = 0.0;
    vec3 p;
    for (int i = 0; i < MAX_MARCHING_STEPS; i++) {
        p = r.origin + depth * r.direction;
        SDFRes res = sceneSDF(p);
        float dist = res.distance_t;
        if (dist < EPSILON) {
            // We're inside the scene surface!
            intersection.position = p;
            intersection.distance_t = depth;
            intersection.material_id = res.material_id;
            intersection.normal = estimateNormal(p);
            return intersection;
        }
        // Move along the view ray
        depth += dist;
        
    }
    intersection.position = p;
    intersection.distance_t = -1.0;
    return intersection;
}

float ambientOcclusion(vec3 p, vec3 n){
    const int steps = 3;
    const float delta = 0.5;

    float a = 0.0;
    float weight = 0.75;
    float m;
    for(int i=1; i<=steps; i++) {
        float d = (float(i) / float(steps)) * delta; 
        a += weight*(d - sceneSDF(p + n*d).distance_t);
        weight *= 0.5;
    }
    return clamp(1.0 - a, 0.0, 1.0);
}


//#define shadow_enabled_phong
#define AO
vec3 phongContribForLight(vec3 k_d, vec3 k_s, float alpha, vec3 normal,vec3 p, vec3 eye,
                          vec3 lightPos, vec3 lightIntensity) {
    vec3 N = normal;
    vec3 L = normalize(lightPos - p);
    vec3 V = normalize(eye - p);
    vec3 R = normalize(reflect(-L, N));
    
    float dotLN = dot(L, N);
    float dotRV = dot(R, V);
    

    #ifdef shadow_enabled_phong
    float shadowFactor = softShadow(p, normalize(LIGHT_DIR));
    #else
    float shadowFactor = 1.0;
    #endif


    float ao = 1.0;
    #ifdef AO
	ao = ambientOcclusion(p, N);
    #endif


    if (dotLN < 0.0) {
        // Light not visible from this point on the surface
        return vec3(0.0, 0.0, 0.0);
    } 
	//Final Color

    if (dotRV < 0.0) {
        // Light reflection in opposite direction as viewer, apply only diffuse
        // component
        return lightIntensity * (k_d * dotLN);
    }
    return lightIntensity * (k_d * dotLN * shadowFactor + k_s * pow(dotRV, alpha));
}

vec3 phongIllumination(vec3 k_a, vec3 k_d, vec3 k_s, float alpha, vec3 n,vec3 p, vec3 eye) {
    const vec3 ambientLight = 0.7*vec3(0.9804, 1.0, 0.8667);
    vec3 color = ambientLight * k_a;
    

    vec3 light1Pos = vec3(-4.*sin(0.01*u_Time),2.+sin(0.008*u_Time),3.*sin(0.01*u_Time));
    vec3 light1Intensity = vec3(0.5);


    
    vec3 L = normalize(light1Pos - p);  
    vec3 bg=mix(k_a,color,clamp(dot(eye - p,L)*.2,-.5,1.5));    

    color += phongContribForLight(k_d, k_s, alpha, n, p, eye,
                                  light1Pos,
                                  light1Intensity);
    // DEPTH FOG
    color = mix(bg,color,exp(-length(eye - p)/7.));
    return color;
}
vec3 lambertianIllumintation_shadow(vec3 k_d, vec3 N,vec3 p, vec3 eye){

    vec3 lightPos = vec3(-3.*sin(0.01*u_Time), 4.+cos(0.01*u_Time), -2.*cos(0.009*u_Time));
    vec3 diffuseColor = k_d; 
    vec3 L = normalize(lightPos - p);

    // Calculate the diffuse term for Lambert shading
    float diffuseTerm = dot(normalize(N), normalize(L));
    // Avoid negative lighting values
    diffuseTerm = clamp(diffuseTerm, 0., 1.);
    float ambientTerm = 0.2;
    float lightIntensity = diffuseTerm + ambientTerm;   //Add a small float value to the color multiplier
                                                            //to simulate ambient lighting. This ensures that faces that are not
                                                            //lit by our point light are not completely black.
    float shadowFactor = softShadow(p, L);
    // Compute final shaded color
    vec3 col = 0.5*vec3(diffuseColor * lightIntensity *shadowFactor);
    return col;
}
vec3 lambertianIllumintation(vec3 k_d, vec3 N,vec3 p, vec3 eye){

    vec3 lightPos = vec3(-3.*sin(0.01*u_Time), 3.+abs(cos(0.01*u_Time)), -2.*cos(0.009*u_Time));
    vec3 diffuseColor = k_d; 
    vec3 L = normalize(lightPos - p);

    // Calculate the diffuse term for Lambert shading
    float diffuseTerm = dot(normalize(N), normalize(L));
    // Avoid negative lighting values
    diffuseTerm = clamp(diffuseTerm, 0., 1.);
    float ambientTerm = 0.2;
    float lightIntensity = diffuseTerm + ambientTerm;   
    // Compute final shaded color
    vec3 col = 0.5*vec3(diffuseColor * lightIntensity);
    return col;
}
vec3 palette( float t, vec3 a, vec3 b, vec3 c, vec3 d )
{
    return a + b*cos( 6.28318*(c*t+d) );
}

vec3 calcColor(Intersection i){
    vec3 p = i.position;
    vec3 col = vec3(0.0);
    switch(i.material_id){
        case(AXIS):{

            vec3 K_a = mat_axis.ambient;
            vec3 a = vec3(0.5, 0.5, 0.5);
            vec3 b = vec3(0.5, 0.5, 0.5);	
            vec3 c = vec3(2.0, 1.0, 0.0);
            vec3 d = vec3(0.50, 0.20, 0.25);
            float noise = snoise(p);
            
            float pct = abs(sin(0.001*u_Time)+noise);
            vec3 cosine_color = palette(0.01*u_Time+noise,a,b,c,d);
            K_a = mix(cosine_color,K_a,pct);
            vec3 phong_col = phongIllumination(clamp(K_a,0.0,1.0),mat_axis.diffuse,mat_axis.specular, mat_axis.shininess, i.normal, p, u_Eye);
            col += lambertianIllumintation(phong_col,i.normal,p,u_Eye);
            break;
        }
        case(TEETH):{
            vec3 a = vec3(0.5, 0.5, 0.5);
            vec3 b = vec3(0.5, 0.5, 0.5);	
            vec3 c = vec3(1.0, 1.0, 1.0);
            vec3 d = vec3(0.00, 0.33, 0.67);
            float noise = snoise(p);
            float pct = abs(cos(0.02*u_Time)+noise);
            vec3 K_a = palette(0.01*u_Time+0.1*noise,a,b,c,d);
            
            a = vec3(0.5, 0.5, 0.5);
            b = vec3(0.5, 0.5, 0.5);	
            c = vec3(1.0, 1.0, 1.0);
            d = vec3(0.30, 0.20, 0.20);
            vec3 cosine_color = palette(0.001*u_Time+noise,a,b,c,d);
            K_a = mix(cosine_color,K_a,pct);
            vec3 phong_col = phongIllumination(clamp(K_a,0.0,1.0), mat_teeth.diffuse, mat_teeth.specular, mat_teeth.shininess, i.normal,p, u_Eye);
            col += lambertianIllumintation(phong_col,i.normal,p,u_Eye);
            break;
        }
         case(FLOOR):{
            vec3 K_a = mat_floor.ambient;
            col += lambertianIllumintation_shadow(K_a, i.normal, p, u_Eye);
            break;
        }
        default:
            col = vec3(1.0);
    }
    return col;
}


void main() {
  Intersection i = getRaymarchedIntersection(fs_Pos);
  if(i.distance_t==-1.0){
    // background
    vec3 color =  0.7*vec3(1.0, 0.9333, 0.8353);
    vec3 k_a=vec3(0.0);
    vec3 p = i.position;
    vec3 light1Pos = vec3(-4.*sin(0.01*u_Time),2.+sin(0.008*u_Time),3.*sin(0.01*u_Time));
    vec3 light1Intensity = vec3(0.5);
    vec3 L = normalize(light1Pos - p);  
    vec3 bg=mix(k_a,color,clamp(dot(u_Eye - p,L)*.2,-.5,1.5));    
    // DEPTH FOG
    color = mix(bg,color,exp(-length(u_Eye - p)/7.));
    out_Col = vec4(color,1.0);
  }
  else{
    vec3 col = calcColor(i);
    out_Col=vec4(col,1.0);
  }

  // foggy
  
}
