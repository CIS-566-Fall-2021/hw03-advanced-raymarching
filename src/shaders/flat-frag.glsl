#version 300 es

#define keyPadding 0.011f
#define keyScale 2.7f
precision highp float;

uniform vec3 u_Eye, u_Ref, u_Up;
uniform vec2 u_Dimensions;
uniform float u_Time;

in vec2 fs_Pos;
out vec4 out_Col;

const int MAX_RAY_STEPS = 512;
const float FOV = 45.0;
const float FOV_TAN = tan(45.0);
const float EPSILON = 1e-6;

const vec3 EYE = vec3(0.0, 0.0, -10.0);
const vec3 ORIGIN = vec3(0.0, 0.0, 0.0);
const vec3 WORLD_UP = vec3(0.0, 1.0, 0.0);
const vec3 WORLD_RIGHT = vec3(1.0, 0.0, 0.0);
const vec3 WORLD_FORWARD = vec3(0.0, 0.0, 1.0);

const vec3 ebCut = vec3(0.062, -0.27f, 0.f) / keyScale;
const vec3 ebCutB = vec3(0.04, 0.45, 0.121) / keyScale;
const vec3 whiteKeyBox = vec3(0.1, 0.71, 0.12) / keyScale;
const vec3 keyStep = vec3(0.2f + keyPadding, 0.f, 0.f) / keyScale;

const int MAT_FLAT = 0;
const int MAT_WOOD = 1;
const int MAT_METAL = 2;
const int MAT_MARBLE = 3;
const int MAT_TILE = 4;

struct Surface {
  float distance;
  vec3 color;
  int material;
};

Surface createSurface() {
  Surface surf;
  surf.distance = 9999999.f;
  surf.color = vec3(0.f, 0.f, 0.f);
  surf.material = MAT_FLAT;
  return surf;
}

Surface mins(Surface a, Surface b) {
  if (a.distance < b.distance) {
    return a;
  } else {
    return b;
  }
}

Surface maxs(Surface a, Surface b) {
  if (a.distance > b.distance) {
    return a;
  } else {
    return b;
  }
}

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
  Surface surface;
};

// --- Noise copied from HW3 ---
float randomNoise2(vec3 p, float seed) {
    return fract(sin(dot(p, vec3(12.9898, -78.233, 133.999)))  * (43758.5453 + seed));
}

float randomNoise3(vec2 co){
    return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

float randomNoise3(vec3 co){
    float noise = randomNoise3(co.xy);
    return randomNoise3(vec2(noise, co.z));
}
const float WORLEY_SQUARES = 20.f;
vec4 worley_noise(vec2 uv) {
    vec2 uv_w = uv * WORLEY_SQUARES;
    vec2 uv_int = floor(uv_w);
    vec2 uv_fract = fract(uv_w);
    float min_dist = 999999.f;
    vec2 min_diff = vec2(0, 0);
    vec2 min_point = vec2(0, 0);
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 neighbor = uv_int +  vec2(float(x), float(y));

            // Work off of absolute coords to help my ailing brain...
            vec2 point = (neighbor + vec2(randomNoise2(neighbor.xxy, 1.f), randomNoise2(neighbor.yyx, 2.f))) / WORLEY_SQUARES;
            vec2 diff = point - uv;
            float lness = 6.f;
            float dist = pow(pow(diff.x, lness) + pow(diff.y, lness), 1.f / lness);
            if (dist < min_dist) {
                min_dist = dist;
                min_diff = -diff;
                min_point = point;
            }
        }
    }

    return vec4(min_diff.x, min_diff.y, min_point.x, min_point.y);
}

float bias(float time, float bias) {
    return (time / ((((1.0 / bias) - 2.0) * (1.0 - time)) + 1.0));
}

float gain(float time, float gain) {
    if (time < 0.5) {
        return bias(time * 2.0, gain) / 2.0;
    } else {
        return bias(time * 2.0 - 1.0, 1.0 - gain) / 2.0 + 0.5;
    }
}

vec3 normalizeNZ(vec3 v) {
    if (v.x == 0.f && v.y == 0.f && v.z == 0.f) {
        return v;
    } else {
        return v;//normalize(v);
    }
}

vec3 getLatticeVector(ivec3 p, float cutoff, float seed) {
    vec3 p2 = vec3(float(p.x), float(p.y), float(p.z));
    float x = -1.f + 2.f * randomNoise2(p2, 1201.f + seed);
    float y = -1.f + 2.f * randomNoise2(p2, 44402.f + seed);
    float z = -1.f + 2.f * randomNoise2(p2, 23103.f + seed);

    return normalizeNZ(vec3(x, y, z));
}

float interpQuintic(float x, float a, float b) {
    float mod = 1.f - 6.f * pow(x, 5.f) + 15.f * pow(x, 4.f) - 10.f * pow(x, 3.f);
    return mix(a, b, 1.f - mod);
}

float interpQuintic3D(vec3 p, float bnl, float bnr, float bfr, float bfl, float tnl, float tnr, float tfr, float tfl) {
    vec3 base = floor(p);
    vec3 diff = p - base;

    float bl = interpQuintic(diff.z, bnl, bfl);
    float br = interpQuintic(diff.z, bnr, bfr);
    float tl = interpQuintic(diff.z, tnl, tfl);
    float tr = interpQuintic(diff.z, tnr, tfr);

    float l = interpQuintic(diff.y, bl, tl);
    float r = interpQuintic(diff.y, br, tr);

    return interpQuintic(diff.x, l, r);
}

const ivec3 bnlv = ivec3(0, 0, 0);
const ivec3 bnrv = ivec3(1, 0, 0);
const ivec3 bfrv = ivec3(1, 0, 1);
const ivec3 bflv = ivec3(0, 0, 1);

const ivec3 tnlv = ivec3(0, 1, 0);
const ivec3 tnrv = ivec3(1, 1, 0);
const ivec3 tfrv = ivec3(1, 1, 1);
const ivec3 tflv = ivec3(0, 1, 1);

const vec3 bnlv2 = vec3(0.f, 0.f, 0.f);
const vec3 bnrv2 = vec3(1.f, 0.f, 0.f);
const vec3 bfrv2 = vec3(1.f, 0.f, 1.f);
const vec3 bflv2 = vec3(0.f, 0.f, 1.f);
const vec3 tnlv2 = vec3(0.f, 1.f, 0.f);
const vec3 tnrv2 = vec3(1.f, 1.f, 0.f);
const vec3 tfrv2 = vec3(1.f, 1.f, 1.f);
const vec3 tflv2 = vec3(0.f, 1.f, 1.f);

const float sqrt3 = 1.732050807568877;
float perlin(vec3 p, float voxelSize, float nonZeroCutoff, float seed) {
    p.x += 100.f;
    p.y += 100.f;
    p.z += 100.f;
    p /= voxelSize;
    vec3 lp2 = floor(p);
    ivec3 lp = ivec3(floor(p.x), floor(p.y), floor(p.z));

    vec3 bnl = getLatticeVector(lp + bnlv, nonZeroCutoff, seed);
    vec3 bnr = getLatticeVector(lp + bnrv, nonZeroCutoff, seed);
    vec3 bfr = getLatticeVector(lp + bfrv, nonZeroCutoff, seed);
    vec3 bfl = getLatticeVector(lp + bflv, nonZeroCutoff, seed);
    vec3 tnl = getLatticeVector(lp + tnlv, nonZeroCutoff, seed);
    vec3 tnr = getLatticeVector(lp + tnrv, nonZeroCutoff, seed);
    vec3 tfr = getLatticeVector(lp + tfrv, nonZeroCutoff, seed);
    vec3 tfl = getLatticeVector(lp + tflv, nonZeroCutoff, seed);

    float dotBnl = dot(normalizeNZ(p - lp2), bnl);
    float dotBnr = dot(normalizeNZ(p - lp2 - bnrv2), bnr);
    float dotBfr = dot(normalizeNZ(p - lp2 - bfrv2), bfr);
    float dotBfl = dot(normalizeNZ(p - lp2 - bflv2), bfl);

    float dotTnl = dot(normalizeNZ(p - lp2 - tnlv2), tnl);
    float dotTnr = dot(normalizeNZ(p - lp2 - tnrv2), tnr);
    float dotTfr = dot(normalizeNZ(p - lp2 - tfrv2), tfr);
    float dotTfl = dot(normalizeNZ(p - lp2 - tflv2), tfl);

    return (sqrt3/2.f + interpQuintic3D(p, dotBnl, dotBnr, dotBfr, dotBfl, dotTnl, dotTnr, dotTfr, dotTfl)) / sqrt3;
}

float fbmPerlin(vec3 p,   // The point in 3D space to get perlin value for
    float voxelSize,      // The size of each voxel in perlin lattice
    float nonZeroCutoff,  // The chance that a given lattice vector is nonzero
    float seed,           // Seed for perlin noise.
    int rounds,           // # of rounds of frequency summation/reconstruction
    float ampDecay,       // Amplitude decay per 'octave'.
    float freqGain) {     // Frequency gain per 'octave'.

    float acc = 0.f;
    float amplitude = 1.f;
    float freq = 0.5f;
    float normC = 0.f;
    for (int round = 0; round < rounds; round++) {
        acc += amplitude * perlin(p * freq, voxelSize, nonZeroCutoff, seed);
        normC += amplitude;
        amplitude *= ampDecay;
        freq *= freqGain;
    }

    return acc / normC;
}


// --- Geometry helpers ---
float smoothSubtraction(float d1, float d2, float k)  {
    float h = clamp( 0.5 - 0.5*(d2+d1)/k, 0.0, 1.0 );
    return mix( d2, -d1, h ) + k*h*(1.0-h); 
}

float lengthInf(vec3 p) {
  return max(p.x, max(p.y, p.y));
}

vec3 flipX(vec3 p) {
  return vec3(-p.x, p.y, p.z);
}

float smin(float a, float b, float k) {
  float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
  return mix(b, a, h) - k * h * (1.0 - h);
}

mat3 rotationMatrix(vec3 axis, float angle)
{
    axis = normalize(axis);
    float s = sin(angle);
    float c = cos(angle);
    float oc = 1.0 - c;
    
    return mat3(oc * axis.x * axis.x + c,           oc * axis.x * axis.y - axis.z * s,  oc * axis.z * axis.x + axis.y * s,
                oc * axis.x * axis.y + axis.z * s,  oc * axis.y * axis.y + c,           oc * axis.y * axis.z - axis.x * s,
                oc * axis.z * axis.x - axis.y * s,  oc * axis.y * axis.z + axis.x * s,  oc * axis.z * axis.z + c);
}

vec3 translateTo(vec3 p, vec3 c) {
  return p - c;
}

vec3 rotateAround(vec3 p, vec3 axis, float angle) {
  return rotationMatrix(axis, angle) * p;
}

// L2-Norm SDFs
float sdRoundedCylinder(vec3 p, float ra, float rb, float h) {
  vec2 d = vec2(length(p.xz) - 2.0 * ra + rb, abs(p.y) - h);
  return min(max(d.x,d.y),0.0) + length(max(d,0.0)) - rb;
}

float sdfEllipsoid(vec3 p, vec3 r) {
  float k0 = length(p / r);
  float k1 = length(p / (r * r));
  return k0 * (k0 - 1.0) / k1;
}

float sdCappedCylinder(vec3 p, float h, float r) {
  vec2 d = abs(vec2(length(p.xz), p.y)) - vec2(h,r);
  return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
}

float sdfCappedCone(vec3 p, vec3 a, vec3 b, float ra, float rb)
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
    return s * sqrt( min(cax*cax + cay*cay*baba,
                       cbx*cbx + cby*cby*baba) );
}

float sdfSphere(vec3 query_position, vec3 position, float radius) {
  return length(query_position - position) - radius;
}

float sdfRoundBox(vec3 p, vec3 b, float r) {
  vec3 q = abs(p) - b;
  return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0) - r;
}

float sdfBox( vec3 p, vec3 b ) {
  vec3 q = abs(p) - b;
  return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

float sdfPlane(vec3 p, vec3 n, float h) {
  return dot(p, n) + h;
}

Surface sdfEbonyKey(vec3 p) {
  Surface s = createSurface();
  s.distance = sdfBox(p, vec3(0.05, 0.45, 0.18) / keyScale);
  s.color = vec3(0.09f, 0.09f, 0.09f);
  return s;
}

Surface sdfEBKey(vec3 p) {
Surface s = createSurface();
  vec3 pt = p + ebCut;
  float d1 = -sdfBox(pt, ebCutB);
  float d2 = sdfBox(p, whiteKeyBox);
  s.distance = d1 > d2 ? d1 : d2;
  s.color = vec3(0.98, 0.98, 0.98);
  return s;
}

Surface sdfCFKey(vec3 p) {
  return sdfEBKey(p - vec3(p.x * 2.f - whiteKeyBox.x, 0.f, 0.f));
}

float expImpulse(float x, float k) {
    float h = k * x;
    return h * exp(1.0 - h);
}

Surface sdfDKey(vec3 p) {
  Surface s = createSurface();
  float mod = (1. + cos(u_Time / 4.f)) / 25.f;
  p.z -= expImpulse(mod, 1.f / 25.f) * 4.5f;
  vec3 pt = p + vec3(0.085, -0.27f, 0.f) / keyScale;
  float leftBox = sdfBox(pt, vec3(0.02, 0.45, 0.121) / keyScale);
  pt = p + vec3(-0.089, -0.27f, 0.f) / keyScale;
  float rightBox = sdfBox(pt, vec3(0.02, 0.45, 0.121) / keyScale);
  s.distance = max(-rightBox, max(-leftBox, sdfBox(p, vec3(0.1, 0.71, 0.12) / keyScale)));
  s.color = vec3(0.98, 0.98, 0.98);
  return s;
}

Surface sdfGKey(vec3 p) {
Surface s = createSurface();
  vec3 pt = p + vec3(0.085, -0.27f, 0.f) / keyScale;
  float leftBox = sdfBox(pt, vec3(0.018, 0.45, 0.121) / keyScale);
  pt = p + vec3(-0.076, -0.27f, 0.f) / keyScale;
  float rightBox = sdfBox(pt, vec3(0.025, 0.45, 0.121) / keyScale);
  s.distance = max(-rightBox, max(-leftBox, sdfBox(p, vec3(0.1, 0.71, 0.12) / keyScale)));
  s.color = vec3(0.98, 0.98, 0.98);
  return s;
}

Surface sdfAKey(vec3 p) {
  return sdfGKey(p - vec3(p.x * 2.f, 0.f, 0.f));
}

Surface sdfMusicStand(vec3 p) {
Surface s = createSurface();
  vec3 p2 = p + vec3(0.f, 0.58f, 0.5f);
  p2 = rotateAround(p2, vec3(1.f, 0.f, 0.f), 0.3);
  s.distance = smoothSubtraction(
    sdCappedCylinder(p2 + vec3(-1.46f, 0.f, 0.2f), 0.2, 0.022),
    smoothSubtraction(
      sdCappedCylinder(p2 + vec3(1.46f, 0.f, 0.2f), 0.2, 0.022), 
      sdfBox(p2, vec3(1.5f, 0.02f, 0.25f)),
      0.1), 0.1);

  s.color = vec3(0.09, 0.09, 0.09);
  return s;
}

// For center-positioned objects
vec3 repeatX(vec3 p, float period, float l, float u) {
  vec3 p2 = p;
  p2.x = p.x - period * clamp(round(p.x / period), l, u);
  return p2;
}

// For top-left-near positioned objects
vec3 repeatX2(vec3 p, float period, float l, float u) {
  vec3 p2 = p;
  p2.x = p.x - period * clamp(floor(p.x / period), l, u);
  return p2;
}

Surface sdfOctave2(vec3 p) {
  vec3 ip = p - vec3(0.18, 0.28, -0.063) / keyScale;

  // Ivory Keys
  vec3 q = repeatX(p, keyStep.x * 3.f, 0.f, 1.f);
  Surface cf = sdfCFKey(q);
  p -= keyStep + vec3(0.04f, 0.f,0.f);
  Surface d = sdfDKey(p);
  p -= keyStep;
  q = repeatX(p, keyStep.x * 4.f, 0.f, 1.f);
  Surface eb = sdfEBKey(q);
  p -= 2.f * keyStep;
  Surface g = sdfGKey(p);
  p -= keyStep;
  Surface a = sdfAKey(p);

  // Ebony Keys
  q = repeatX(ip, 0.255 / keyScale, 0.f, 1.f);
  Surface csds = sdfEbonyKey(q);
  ip.x -= (0.38 + 0.255) / keyScale;
  q = repeatX(ip, 0.24 / keyScale, 0.f, 2.f);
  Surface fsgsas = sdfEbonyKey(q);
  return mins(fsgsas, mins(csds, mins(a, mins(g, mins(eb, mins(cf, d))))));
}


Surface sdfKeys2(vec3 p, int octaves) {
  vec3 q = repeatX2(p, keyStep.x * 7.f, 0.f, float(octaves));
  return sdfOctave2(q);
}

Surface sdfFrame(vec3 p) {
  Surface s = createSurface();
  s.material = MAT_FLAT;
  s.color = vec3(0.3f, 0.3f, 0.3f);
  vec3 mainB = vec3(7.f, 2.f, 6.f) / 4.f;
  vec3 sideB = vec3(0.05, 0.9, 0.9);
  vec3 frontB = vec3(mainB.x, sideB.x, 0.2);
  float top = sdfRoundBox(p + vec3(0.f, 0.f, 1.5f), vec3(7.1f, 2.1f, 0.1f) / 4.f, 0.01);
  float bottom = 
    sdfBox(p + vec3(0.f, 1.f, -0.1f), vec3(1.7f, 0.3f, 0.1f));
  s.distance = min(
    sdfBox(p + vec3(0.f, mainB.y + sideB.y - frontB.y * 3.f, 0.f), frontB), 
    smin(
      sdfRoundBox(p - flipX(mainB) + flipX(sideB), sideB, 0.01), 
      smin(sdfRoundBox(p - mainB + sideB, sideB, 0.01), sdfBox(p, mainB), 0.1), 0.1));

  s.distance = smin(top, s.distance, 0.1);
  s.distance = min(s.distance, bottom);
  s.distance = max(s.distance, -sdfRoundBox(p - vec3(-1.7f, -0.9f, 0.9f), vec3(0.06f, .3f, 0.5f), 0.01));
  s.distance = max(s.distance, -sdfRoundBox(p - vec3(1.7f, -0.9f, 0.9f), vec3(0.06f, .3f, 0.5f), 0.01));
  return s;
}

Surface sdfPedal(vec3 p, float factor) {
  const float norm = 7.f;
  p *= norm;
  p.x += factor * smoothstep(0.f, 1.f, 0.5f-p.y*.4f);
  Surface s = createSurface();
  s.distance = sdfEllipsoid(p, vec3(0.5f, 0.5f, 0.2f));
  s.color = vec3(218.f / 255.f,165.f / 255.f,32.f / 255.f);
  s.distance = smin(s.distance, sdfRoundBox(p - vec3(0.f, 0.8f, 0.f), vec3(0.3f, 1.f, 0.1f), 0.04), 0.5) / norm;
  s.material = MAT_METAL;
  return s;
}

Surface sdfPiano(vec3 p) {
  float box = sdfBox(p + vec3(0.f, 1.f, 0.2f), vec3(1.7f, 0.3f, 0.6f));
  Surface keys;
  keys.distance = 999999.f;
  if (box < EPSILON) {
    keys = sdfKeys2(p + vec3(1.63f, 0.95f, 0.2f), 6);
    box = 99999.f;
  }

  Surface bds;
  float bd = sdfBox(p - vec3(0.0f, -0.7f, 1.5f), vec3(0.31f, 0.21f, 0.11f));
  bds.distance = min(bd, box);
  if (bd < EPSILON) {
    Surface pedals = mins(mins(
      sdfPedal(p - vec3(0.15f, -0.7f, 1.5f), -1.f),
      sdfPedal(p - vec3(0.0f, -0.7f, 1.5f), 0.f)),
      sdfPedal(p - vec3(-0.15f, -0.7f, 1.5f), 1.f));
    return mins(pedals, mins(sdfMusicStand(p), mins(keys, sdfFrame(p))));
  } else {
    return mins(bds, mins(sdfMusicStand(p), mins(keys, sdfFrame(p))));
  }
}

Surface sdfVase(vec3 p) {
  Surface s = createSurface();
  s.distance = sdfCappedCone(p, vec3(0.f, 0.f, 0.f), vec3(0.f, 0.0, -0.7f), 0.02, 0.2);
  s.distance = smin(s.distance, sdfSphere(p, vec3(0.f), 0.25), 0.4);
  s.distance = smin(s.distance, sdfCappedCone(p, vec3(0.f, 0.f, 0.f), vec3(0.f, 0.f, 0.5f), 0.02, 0.2), 0.5);
  s.color = vec3(0.f, 1.f, 0.f);
  s.material = MAT_MARBLE;
  return s;
}

Surface sdfTable(vec3 p) {
  Surface table = createSurface();
  table.distance = sdRoundedCylinder(p.xzy, 0.5, 0.1, 0.2f);
  table.distance = max(table.distance, -sdRoundedCylinder(p.xzy - vec3(0.f, 0.1f, 0.f), 0.4, 0.1, 0.21f));
  table.distance = smin(table.distance, sdRoundedCylinder(p.xzy - vec3(0.f, 0.8f, 0.5f), 0.05, 0.01, 1.f), 0.1f);
  table.distance = smin(table.distance, sdRoundedCylinder(p.xzy - vec3(0.f, 0.8f, -0.5f), 0.05, 0.01, 1.f), 0.1f);
  table.distance = smin(table.distance, sdRoundedCylinder(p.xzy - vec3(0.5f, 0.8f, 0.f), 0.05, 0.01, 1.f), 0.1f);
  table.distance = smin(table.distance, sdRoundedCylinder(p.xzy - vec3(-0.5f, 0.8f, 0.f), 0.05, 0.01, 1.f), 0.1f);
  table.color = vec3(0.f, 0.f, 1.f);
  table.material = MAT_WOOD;

  return mins(table, sdfVase(p - vec3(0.f, 0.f, -0.82f)));
}

Surface sceneSDF(vec3 p) {
  Surface ground = createSurface();
  ground.distance = sdfPlane(p, vec3(0.f, 0.f, -1.f), 1.55f);
  ground.color = vec3(1.f, 0.f, 1.f);
  ground.material = MAT_TILE;
  Surface vase = sdfTable((p - vec3(2.5f, 0.f, 0.7f)) * 2.f);
  vase.distance /= 2.f;
  Surface piano = sdfPiano(p - vec3(0.f, 1.f, 0.f));


  return mins(vase, mins(ground, piano));
}

const float d = 0.001f;
vec3 sceneSDFGrad(vec3 queryPos) {
  vec3 diffVec = vec3(d, 0.f, 0.f);
  return normalize(vec3(
      sceneSDF(queryPos + diffVec).distance - sceneSDF(queryPos - diffVec).distance ,
      sceneSDF(queryPos + diffVec.yxz).distance  - sceneSDF(queryPos - diffVec.yxz).distance ,
      sceneSDF(queryPos + diffVec.zyx).distance  - sceneSDF(queryPos - diffVec.zyx).distance 
    ));
}

Ray getRay(vec2 uv)
{
  Ray r;
  
  vec3 look = normalize(u_Ref - u_Eye);
  vec3 camera_RIGHT = normalize(cross(u_Up, look));
  vec3 camera_UP = u_Up;
  
  float aspect_ratio = u_Dimensions.x / u_Dimensions.y;
  vec3 screen_vertical = camera_UP * FOV_TAN; 
  vec3 screen_horizontal = camera_RIGHT * aspect_ratio * FOV_TAN;
  vec3 screen_point = (look + uv.x * screen_horizontal + uv.y * screen_vertical);
  
  r.origin = (screen_point + u_Eye) / 2.f;
  r.direction = normalize(screen_point - u_Eye);

  return r;
}

const float MIN_STEP = EPSILON * 2.f;
Intersection getRaymarchedIntersection(vec2 uv)
{
  Intersection intersection;
  intersection.distance_t = -1.0;
  Ray ray = getRay(uv);

  float distance_t = 0.f;
  for (int step = 0; step < MAX_RAY_STEPS; step++) {
    vec3 point = ray.origin + ray.direction * distance_t;
    Surface s = sceneSDF(point);

    if (s.distance < EPSILON) {
      intersection.distance_t = s.distance;
      intersection.position = point;
      intersection.normal = sceneSDFGrad(point);
      intersection.surface = s;

      return intersection;
    }

    distance_t += max(s.distance, MIN_STEP);
  }

  return intersection;
}


vec3 colorWheel(float angle) {
    vec3 a = vec3(0.5, 0.5, 0.5);
    vec3 b = vec3(0.5, 0.5, 0.5);
    vec3 c = vec3(1.0, 1.0, 1.0);
    vec3 d = vec3(0.00, 0.10, 0.20);
    return a + b * cos(2.f * 3.14159 * (c * angle + d));
}

vec3 colorWheelWood(float angle) {
    vec3 a = vec3(0.500, 0.500, 0.500);
    vec3 b = vec3(0.500, 0.500, 0.500);
    vec3 c = vec3(1.000, 1.000, 1.000);
    vec3 d = vec3(0.000, 0.333, 0.667);
    return a + b * cos(2.f * 3.14159 * (c * angle + d));
}

float getShadowMask(vec3 ls, vec3 sp) {
  vec3 ro = sp;
  float maxt = length(sp - ls);
  vec3 rd = (ls - sp) / maxt;
  float t = 0.05f;
  float penumbra = 1.f;
  const float k2 = 128.f;
  for (int i = 0; i < 128 && t < maxt; i++) {
    float h = sceneSDF(ro + rd*t).distance;
    if (h < EPSILON) {
      return 0.f;
    }

    penumbra = min(penumbra, k2 * h / t);
    t += h;
  }

  penumbra = clamp( penumbra, 0.0, 1.0 );
  return penumbra*penumbra*(3.0-2.0*penumbra);
}

const vec3 light = vec3(10.f, 14.f, -4.f);
const float ambientTerm = 0.2;
vec3 getSceneColor(vec2 uv) {
  Intersection intersection = getRaymarchedIntersection(uv);
  const vec3 light1 = vec3(-1.0, -2.0, -1.0);
  const vec3 lightCol1 = vec3(0.4f);
  const vec3 light2 = vec3(1.0, -2.0, -1.0);
  const vec3 lightCol2 = vec3(1.f, 0.f, 0.f);
  const vec3 light3 = vec3(6.0, 7.0, -1.0);
  const vec3 lightCol3 = vec3(0.5f, 1.f, 0.5f);

  float diffuseTerm = dot(intersection.normal, normalize(light1 - intersection.position));
  diffuseTerm = clamp(diffuseTerm, 0.f, 1.f);
  float diffuseTerm2 = dot(intersection.normal, normalize(light2 - intersection.position));
  diffuseTerm2 = clamp(diffuseTerm2, 0.f, 1.f);
  float diffuseTerm3 = dot(intersection.normal, normalize(light3 - intersection.position));
  diffuseTerm3 = clamp(diffuseTerm3, 0.f, 1.f);
  if (abs(intersection.distance_t) < EPSILON)
  {
    if (intersection.surface.material == MAT_FLAT) {
      return (intersection.surface.color * (diffuseTerm + ambientTerm) * lightCol1 +
              intersection.surface.color * (diffuseTerm2) * lightCol2 + 
              intersection.surface.color * (diffuseTerm3) * lightCol3);
    } else if (intersection.surface.material == MAT_MARBLE) {
      float diffuseTerm = dot(intersection.normal, normalize(light1 - intersection.position));
      diffuseTerm = clamp(diffuseTerm, 0.f, 1.f);
      return colorWheel(fbmPerlin(intersection.position * 2.f, 0.5f, 0.0f, 1.f, 2, 0.6, 3.f)) * (diffuseTerm + ambientTerm);
    } else if (intersection.surface.material == MAT_WOOD) {
      float diffuseTerm = dot(intersection.normal, normalize(light1 - intersection.position));
      diffuseTerm = clamp(diffuseTerm, 0.f, 1.f);
      float perl = fbmPerlin(intersection.position, 0.7f, 0.0f, 4.f, 2, 0.6, 1.9f) - 0.1f;
      perl = floor(perl * 200.f) / 200.f;
      vec3 color = colorWheelWood(perl * 90.f);
      color.r = clamp(color.r,0.25,0.32);
      color.g = clamp(color.g,0.20,0.22);
      color.b = clamp(color.b,0.10,0.11);
      color = normalize(color) * vec3(1.40,1.50,1.15) * vec3(0.9f, 0.9f, 0.9f);
      return (color * (diffuseTerm + ambientTerm) * lightCol1 +
              color * (diffuseTerm2) * lightCol2 +
              color * (diffuseTerm3) * lightCol3);
    } else if (intersection.surface.material == MAT_METAL) {
      float diffuseTerm = dot(intersection.normal, normalize(light1 - intersection.position));
      diffuseTerm = clamp(diffuseTerm, 0.f, 1.f);
    
      float lightIntensity = diffuseTerm + ambientTerm; 
      float bf_highlight = max(pow(dot(normalize(intersection.normal), normalize(light1 - intersection.position)), 12.f), 0.f);
      return intersection.surface.color * (lightIntensity + bf_highlight);
    } else if (intersection.surface.material == MAT_TILE) {
      float diffuseTerm = dot(intersection.normal, normalize(light1 - intersection.position));
      diffuseTerm = clamp(diffuseTerm, 0.f, 1.f)* getShadowMask(light1, intersection.position);
      vec4 wp = worley_noise(intersection.position.xy / 5.f);
      float grey = (1.f + cos(randomNoise3(wp.zw))) / 2.f;
      return (vec3(grey) * (diffuseTerm + ambientTerm) * lightCol1 +
              vec3(grey) * (diffuseTerm2) * lightCol2 +
              vec3(grey) * (diffuseTerm3) * lightCol3);
    } else {
      return vec3(0.f);
    }
  }

  return vec3(0.7, 0.2, 0.2);
}

void main() {
  // Time varying pixel color
  vec3 col = getSceneColor(fs_Pos);

  // Output to screen
  out_Col = vec4(col, 1.0);
}