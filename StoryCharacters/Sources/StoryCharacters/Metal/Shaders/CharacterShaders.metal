// CharacterShaders.metal — StoryCharacters Metal renderer.
// One full-screen triangle draws the whole character with signed-distance fields; a second
// instanced pass draws the sparkle field. Geometry follows docs/CONTRACT.md §2–§3 exactly.
// This file is embedded verbatim in Metal/CharacterShaderSource.swift (runtime fallback).
// Never use a backslash in this file: the Swift mirror is a raw string literal.
#include <metal_stdlib>
using namespace metal;

// MARK: - Uniforms (mirror of Swift CharacterUniforms: 35 x float4 = 560 bytes, same order)

struct CharacterUniforms {
    float4 viewport;        // width, height (pixels), aspect, time (s)
    float4 transform;       // offsetX, offsetY, scaleX, scaleY
    float4 bodyParams;      // tilt, breathe, glow, wiggle
    float4 armsAccessory;   // armL, armR, accessory, accessory2
    float4 legsBounce;      // legL, legR, bounce, spare
    float4 eyesA;           // eyeOpenL, eyeOpenR, gazeX, gazeY
    float4 eyesB;           // pupil, eyeScale, lowerLidL, lowerLidR
    float4 brows;           // browRaiseL, browRaiseR, browTiltL, browTiltR
    float4 head;            // blush, headTilt, headTurn, headNod
    float4 mouthA;          // open, width, smile, round
    float4 mouthB;          // upperTeeth, lowerTeeth, tongue, press
    float4 fxA;             // tears, sweat, hearts, zzz
    float4 fxB;             // question, exclamation, sparkleBurst, sparkleRate (pose)
    float4 layoutA;         // eyeOffsetX, eyeY, eyeRadiusX, eyeRadiusY
    float4 layoutB;         // irisRadius, pupilRadius, browY, browLength
    float4 layoutC;         // browThickness, mouthY, mouthWidth, mouthHeight
    float4 layoutD;         // cheekX, cheekY, cheekRadius, faceScale
    float4 layoutE;         // faceOffsetY, radiusScale, centerOffsetY, spare (the renderer stores idle.breathDepth here)
    float4 style;           // bodyShape, features (bitmask as float), glowStrength, sparkleRate (design)
    float4 idle;            // floatAmplitude, floatFrequency, wobbleAmplitude, flickerRate
    float4 colBodyTop;
    float4 colBodyBottom;
    float4 colHighlight;
    float4 colShadow;
    float4 colAccent;
    float4 colAccent2;
    float4 colIris;
    float4 colPupil;
    float4 colSclera;
    float4 colCheek;
    float4 colGlow;
    float4 colMouthInner;
    float4 colTongue;
    float4 colTeeth;
    float4 colOutline;
};

// MARK: - DesignFeatures bits (shared with Swift)

constant uint kFeatArms        = 1u << 0;
constant uint kFeatLegs        = 1u << 1;
constant uint kFeatFloats      = 1u << 2;
constant uint kFeatHood        = 1u << 3;
constant uint kFeatBrain       = 1u << 4;
constant uint kFeatMoonMark    = 1u << 5;
constant uint kFeatDome        = 1u << 6;
constant uint kFeatLeaves      = 1u << 7;
constant uint kFeatCloudCurl   = 1u << 8;
constant uint kFeatBookAndWand = 1u << 9;
constant uint kFeatDarkFace    = 1u << 10;
constant uint kFeatInnerFlame  = 1u << 11;
constant uint kFeatFlicker     = 1u << 13;
constant uint kFeatStarPattern = 1u << 14;
constant uint kFeatEyeSparkles = 1u << 15;

constant float kPi = 3.14159265358979;
constant float kTwoPi = 6.28318530717959;

// MARK: - Small helpers

static inline bool hasFeature(uint features, uint bit) {
    return (features & bit) != 0u;
}

// Counter-clockwise rotation (y up).
static inline float2 rot(float2 v, float a) {
    float c = cos(a);
    float s = sin(a);
    return float2(c * v.x - s * v.y, s * v.x + c * v.y);
}

// Coverage of the interior of a signed distance (1 inside, 0 outside), anti-aliased.
static inline float fillAA(float d, float aa) {
    return 1.0 - smoothstep(-aa, aa, d);
}

// Coverage of a stroke of half-width hw centred on the zero level set.
static inline float strokeAA(float d, float hw, float aa) {
    return 1.0 - smoothstep(hw - aa, hw + aa, abs(d));
}

// Premultiplied "over" compositing: dst is premultiplied, col is straight colour with coverage a.
static inline float4 blendOver(float4 dst, float3 col, float a) {
    return float4(col * a + dst.rgb * (1.0 - a), a + dst.a * (1.0 - a));
}

static inline float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// Integer hash of a grid cell, 24-bit result in [0, 1). Pure integer arithmetic, so the CPU mirror
// (CharacterPaths.cellHash in the Canvas renderer) produces bit-identical values.
static inline float cellHash(int2 cell, uint salt) {
    uint h = uint(cell.x) * 73856093u;
    h ^= uint(cell.y) * 19349663u;
    h ^= salt * 83492791u;
    h ^= h >> 16;
    h *= 2146121005u;
    h ^= h >> 15;
    h *= 2221713035u;
    h ^= h >> 16;
    return float(h & 16777215u) / 16777216.0;
}

// Piecewise-linear radial falloff matching the Canvas glow gradients: 1 at the centre, `mid` at
// `midLoc` (fraction of the radius), 0 at the radius and beyond.
static inline float radialFalloff(float dist, float radius, float midLoc, float mid) {
    float x = clamp(dist / max(radius, 1e-4), 0.0, 1.0);
    return (x < midLoc) ? mix(1.0, mid, x / midLoc) : mix(mid, 0.0, (x - midLoc) / (1.0 - midLoc));
}

// MARK: - Signed distance primitives (R units)

static inline float sdCircle(float2 p, float2 c, float r) {
    return length(p - c) - r;
}

static inline float sdEllipse(float2 p, float2 c, float2 r) {
    float2 q = (p - c) / r;
    return (length(q) - 1.0) * min(r.x, r.y);
}

static inline float sdBox(float2 p, float2 c, float2 he) {
    float2 d = abs(p - c) - he;
    return length(max(d, float2(0.0))) + min(max(d.x, d.y), 0.0);
}

static inline float sdRoundBox(float2 p, float2 c, float2 he, float r) {
    return sdBox(p, c, he - float2(r)) - r;
}

static inline float sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a;
    float2 ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
    return length(pa - ba * h);
}

static inline float sdCapsule(float2 p, float2 a, float2 b, float r) {
    return sdSegment(p, a, b) - r;
}

// Capsule with different radii at both ends (ra at pa, rb at pb).
static inline float sdUnevenCapsule(float2 p, float2 pa, float2 pb, float ra, float rb) {
    p -= pa;
    pb -= pa;
    float h = max(dot(pb, pb), 1e-6);
    float2 q = float2(dot(p, float2(pb.y, -pb.x)), dot(p, pb)) / h;
    q.x = abs(q.x);
    float b = ra - rb;
    float2 c = float2(sqrt(max(h - b * b, 1e-6)), b);
    float k = c.x * q.y - c.y * q.x;
    float m = dot(c, q);
    float n = dot(q, q);
    if (k < 0.0) {
        return sqrt(h * n) - ra;
    }
    if (k > c.x) {
        return sqrt(h * (n + 1.0 - 2.0 * q.y)) - rb;
    }
    return m - ra;
}

// Five-point star, one point straight up; r = outer radius, rf = inner/outer ratio.
static inline float sdStar5(float2 p, float r, float rf) {
    const float2 k1 = float2(0.809016994375, -0.587785252292);
    const float2 k2 = float2(-k1.x, k1.y);
    p.x = abs(p.x);
    p -= 2.0 * max(dot(k1, p), 0.0) * k1;
    p -= 2.0 * max(dot(k2, p), 0.0) * k2;
    p.x = abs(p.x);
    p.y -= r;
    float2 ba = rf * float2(-k1.y, k1.x) - float2(0.0, 1.0);
    float h = clamp(dot(p, ba) / dot(ba, ba), 0.0, r);
    return length(p - ba * h) * sign(p.y * ba.x - p.x * ba.y);
}

// Soft four-point star (astroid metric), approximate distance.
static inline float sdStar4(float2 p, float r) {
    float rr = max(r, 1e-5);
    float2 q = abs(p) / rr;
    float s = sqrt(q.x) + sqrt(q.y);
    return (s - 1.0) * rr * 0.5;
}

// Heart with its tip at the origin and lobes reaching y = 1 (unit size).
static inline float sdHeart(float2 p) {
    p.x = abs(p.x);
    if (p.y + p.x > 1.0) {
        float2 e = p - float2(0.25, 0.75);
        return sqrt(dot(e, e)) - 0.3535534;
    }
    float2 a = p - float2(0.0, 1.0);
    float2 b = p - 0.5 * max(p.x + p.y, 0.0);
    return sqrt(min(dot(a, a), dot(b, b))) * sign(p.x - p.y);
}

// Distance to an Archimedean spiral centre line r = a + b * theta, theta in [0, turns * 2pi].
// Only windings whose angle lies inside the range count; otherwise the nearest point is one of the two
// end points (round caps), so the stroke never closes into a full circle.
static inline float sdSpiral(float2 p, float a, float b, float turns) {
    float r = length(p);
    float t = atan2(p.y, p.x);
    float maxTheta = turns * kTwoPi;
    float rEnd = a + b * maxTheta;
    float d = min(length(p - float2(a, 0.0)), length(p - rEnd * float2(cos(maxTheta), sin(maxTheta))));
    float k = round(((r - a) / max(b, 1e-5) - t) / kTwoPi);
    for (int j = -1; j <= 1; j++) {
        float theta = t + kTwoPi * (k + float(j));
        if (theta >= 0.0 && theta <= maxTheta) {
            d = min(d, abs(r - (a + b * theta)));
        }
    }
    return d;
}

// MARK: - Body silhouettes (§3.5), unit space before the body transform

// Teardrop family: circle r 0.85 at (0, -0.15) smoothly joined (smin k) to a cone from (0, ya) radius ra
// to the tip at (tipX, yb) radius 0.04.
static inline float sdTeardrop(float2 q, float tipX, float ya, float ra, float yb, float k) {
    float dc = sdCircle(q, float2(0.0, -0.15), 0.85);
    float dt = sdUnevenCapsule(q, float2(0.0, ya), float2(tipX, yb), ra, 0.04);
    return smin(dc, dt, k);
}

// Drop body (§3.5): rounded tip near (tipX, 1.02), convex sides. Parameters fitted to the Canvas Bezier
// outline (control points (+-0.78, 0.55)): half-widths 0.55 at y 0.55 and 0.31 at y 0.75, IoU 0.995.
// The tip sways by shearing the upright drop sideways by tipX * smoothstep(0.05, 1.15, y): the Canvas path moves only
// the tip and its neighbouring control points, which this matches (IoU 0.994 at tipX 0.18; rotating the cone: 0.968).
static inline float sdDrop(float2 q, float tipX) {
    float2 u = float2(q.x - tipX * smoothstep(0.05, 1.15, q.y), q.y);
    return sdTeardrop(u, 0.0, 0.30, 0.40, 0.98, 0.40);
}

// Centre line of the hood curl: quadratic Bezier from (0, 0.90) to (0.55, 1.05) with control point (0.25, 1.25),
// the same curve as the Canvas hoodBody tube.
static inline float2 hoodCurl(float t) {
    float u = 1.0 - t;
    return u * u * float2(0.0, 0.90) + 2.0 * u * t * float2(0.25, 1.25) + t * t * float2(0.55, 1.05);
}

// Hooded wisp: drop whose tip curls to the upper-right, fitted to the Canvas hoodBody (IoU 0.997). The base is the
// same polar outline r(theta) = dropCircleRadius + 0.30 sin^2(theta) (upper half only); the curl is a tube tapering
// 0.22 -> 0.08 along hoodCurl, as three uneven capsules. Static like the Canvas path (no wiggle sway).
static inline float sdHood(float2 q) {
    float len = length(q);
    float s = q.y / max(len, 1e-5);
    float r = 0.5 * (-0.3 * s + sqrt(0.09 * s * s + 2.8)) + 0.30 * max(s, 0.0) * max(s, 0.0);
    float d = (len - r) * 0.9;
    float2 c0 = hoodCurl(0.0);
    float2 c1 = hoodCurl(1.0 / 3.0);
    float2 c2 = hoodCurl(2.0 / 3.0);
    float2 c3 = hoodCurl(1.0);
    d = min(d, sdUnevenCapsule(q, c0, c1, 0.22, 0.22 - 0.14 / 3.0));
    d = min(d, sdUnevenCapsule(q, c1, c2, 0.22 - 0.14 / 3.0, 0.22 - 0.28 / 3.0));
    d = min(d, sdUnevenCapsule(q, c2, c3, 0.22 - 0.28 / 3.0, 0.08));
    return d;
}

// Cloud: union of five circles, flattened below y = -0.70.
static inline float sdCloud(float2 q) {
    float d = sdCircle(q, float2(0.0, 0.0), 0.75);
    d = smin(d, sdCircle(q, float2(-0.55, -0.10), 0.55), 0.08);
    d = smin(d, sdCircle(q, float2(0.55, -0.10), 0.55), 0.08);
    d = smin(d, sdCircle(q, float2(-0.25, 0.35), 0.50), 0.08);
    d = smin(d, sdCircle(q, float2(0.30, 0.40), 0.48), 0.08);
    d = max(d, -0.70 - q.y);
    return d;
}

// Flame (§3.5): the drop with its upper half modulated r * (1 + 0.06 sin(5t + 3w) + 0.03 sin(9t - 2w)) and the upper
// part swayed sideways by 0.22 sin(w) smoothstep(0.1, 1.05, y), mirroring the Canvas CharacterPaths.flamePoint
// (IoU 0.989...0.992 over the wiggle cycle).
static inline float sdFlame(float2 q, float wig, float flicker) {
    float2 u = float2(q.x - 0.22 * sin(wig) * smoothstep(0.1, 1.05, q.y), q.y);
    float d = sdDrop(u, 0.0);
    float theta = atan2(u.y, u.x);
    float upper = smoothstep(-0.15, 0.25, q.y);
    float m = 0.06 * sin(5.0 * theta + 3.0 * wig) + 0.03 * sin(9.0 * theta - 2.0 * wig) + flicker;
    return d - m * length(u) * upper;
}

static inline float sdBody(float2 q, int shape, float wig, float flicker) {
    if (shape == 1) {
        // Fitted to the Canvas star (outer 1.05, inner 0.52, rounding 0.12): IoU 0.99.
        return sdStar5(q, 0.955, 0.50) - 0.04;
    }
    if (shape == 2) {
        return sdDrop(q, 0.18 * sin(wig));
    }
    if (shape == 3) {
        return sdHood(q);
    }
    if (shape == 4) {
        return sdCloud(q);
    }
    if (shape == 5) {
        return sdFlame(q, wig, flicker);
    }
    return length(q) - 1.0;
}

// Vertical gradient + soft highlight ellipse + rim darkening (§3.5 shading).
static inline float3 bodyColor(float2 q, float d, constant CharacterUniforms& u) {
    float t = clamp(q.y * 0.5 + 0.5, 0.0, 1.0);
    float3 col = mix(u.colBodyBottom.rgb, u.colBodyTop.rgb, t);
    float2 hp = rot(q - float2(-0.35, 0.45), 0.5235988);
    float hd = length(hp / float2(0.35, 0.22));
    float hl = (1.0 - smoothstep(0.35, 1.0, hd)) * 0.35;
    col = mix(col, u.colHighlight.rgb, hl);
    float rim = clamp((d + 0.08) / 0.08, 0.0, 1.0);
    col = mix(col, u.colShadow.rgb, 0.35 * rim * rim);
    return col;
}

// Body-gradient colour at height y (used for limbs and the cloud curl).
static inline float3 bodyGradient(float y, constant CharacterUniforms& u) {
    float t = clamp(y * 0.5 + 0.5, 0.0, 1.0);
    return mix(u.colBodyBottom.rgb, u.colBodyTop.rgb, t);
}

// Water-drop glyph used by tears and sweat, same outline as the Canvas `smallDrop`: round bottom of radius r
// at c, pointed tip 2.3 r above it.
static inline float sdWaterDrop(float2 p, float2 c, float r) {
    return sdUnevenCapsule(p, c + float2(0.0, r * 2.2), c, r * 0.1, r);
}

// Canvas cheek gradient as a function of distance / radius: alpha 1, 0.78, 0.30, 0 at 0, 0.35, 0.70, 1
// (a Gaussian truncated at the cheek radius).
static inline float cheekFalloff(float x) {
    float t = clamp(x, 0.0, 1.0);
    if (t < 0.35) {
        return mix(1.0, 0.78, t / 0.35);
    }
    if (t < 0.70) {
        return mix(0.78, 0.30, (t - 0.35) / 0.35);
    }
    return mix(0.30, 0.0, (t - 0.70) / 0.30);
}

// Robe of the .hood feature: teardrop circle r 1.28 at (0,-0.25) with a peak at (peakX, 1.38). The cone is fitted to
// the Canvas CharacterPaths.robe Bezier outline (side controls (+-1.15, 0.75), tip controls (+-0.22, 0.38)): IoU 0.986.
static inline float sdRobe(float2 q, float peakX) {
    float dc = sdCircle(q, float2(0.0, -0.25), 1.28);
    float dp = sdUnevenCapsule(q, float2(0.0, 0.30), float2(peakX, 1.30), 0.50, 0.05);
    return smin(dc, dp, 0.40);
}

// MARK: - Face (§3.1–§3.4). `f` is the face-frame point (head transform already inverted).

// One eye. side = -1 (viewer's left) or +1 (viewer's right).
static float4 drawEye(float4 acc, float2 f, float side, float eyeOpen, float lowerLid, float clip,
                      bool darkFace, bool sparkles, float aa, constant CharacterUniforms& u) {
    float sc = max(u.layoutD.w, 1e-3);
    float oy = u.layoutE.x;
    float es = max(u.eyesB.y, 0.05);
    float2 c = float2(side * u.layoutA.x * sc, oy + u.layoutA.y * sc);
    float rx = max(u.layoutA.z * sc * es, 1e-3);
    float ry = max(u.layoutA.w * sc * es, 1e-3);
    float turn = u.head.z;
    if (side * turn < 0.0) {
        rx *= (1.0 - 0.15 * min(abs(turn), 1.0));
    }
    float o = clamp(eyeOpen, 0.0, 1.3);
    float ryo = ry * max(o, 1.0);
    float top = -ryo + 2.0 * ryo * min(o, 1.0);
    float bot = -ryo + 2.0 * ryo * 0.55 * clamp(lowerLid, 0.0, 1.0);
    float2 lp = f - c;
    if (o < 0.04 || top - bot < 0.02) {
        // Closed or squeezed-shut eye (blink, wink, laughing, sleep): a lash line where the lids meet.
        // Same curve as the Canvas renderer: quadratic from (-0.9 rx, lineY + 0.02) to (+0.9 rx, lineY + 0.02)
        // with control (0, lineY - 0.06), i.e. y = lineY + 0.02 - 0.04 (1 - xn^2); width 0.035, round caps,
        // brow colour (outline, alpha 0.9).
        float lineY = (o < 0.04) ? (-0.2 * ryo) : (0.5 * (top + bot));
        float hx = 0.9 * rx;
        float xn = clamp(lp.x / hx, -1.0, 1.0);
        float curveY = lineY + 0.02 - 0.04 * (1.0 - xn * xn);
        float slope = (abs(lp.x) < hx) ? (0.08 * xn / hx) : 0.0;
        float dy = (lp.y - curveY) / sqrt(1.0 + slope * slope);
        float dl = length(float2(max(abs(lp.x) - hx, 0.0), dy)) - 0.0175;
        return blendOver(acc, u.colOutline.rgb, fillAA(dl, aa) * 0.9 * clip);
    }
    float dEll = sdEllipse(lp, float2(0.0), float2(rx, ryo));
    float dVis = max(dEll, max(lp.y - top, bot - lp.y));
    float cov = fillAA(dVis, aa) * clip;
    if (cov <= 0.002) {
        return acc;
    }
    float irisR = max(u.layoutB.x * sc * es, 1e-3);
    float2 gazeN = clamp(float2(u.eyesA.z, u.eyesA.w), float2(-1.0), float2(1.0));
    float2 io = gazeN * max(float2(rx - irisR, ryo - irisR), float2(0.0)) * 0.85;
    float2 ip = lp - io;
    float irisDist = length(ip);
    float3 col = darkFace ? u.colAccent.rgb : u.colSclera.rgb;
    if (darkFace) {
        float halo = 0.6 * (1.0 - smoothstep(irisR * 0.9, irisR * 1.6, irisDist));
        col = mix(col, u.colIris.rgb, halo);
    }
    // iris: radial gradient, 35 % darker at the rim, thin limbal ring
    float di = irisDist - irisR;
    float t = clamp(irisDist / max(irisR, 1e-4), 0.0, 1.0);
    float3 irisCol = u.colIris.rgb * (1.0 - 0.35 * t);
    col = mix(col, irisCol, fillAA(di, aa));
    col = mix(col, u.colPupil.rgb, 0.35 * strokeAA(di + 0.0075, 0.0075, aa));
    // pupil
    float pr = u.layoutB.y * sc * es * max(u.eyesB.x, 0.0);
    col = mix(col, u.colPupil.rgb, fillAA(irisDist - pr, aa));
    // highlights follow gaze at 25 %
    float2 gz = io * 0.25;
    float2 h1 = float2(-0.38 * rx, 0.42 * ryo) + gz;
    float2 h2 = float2(0.30 * rx, -0.30 * ryo) + gz;
    col = mix(col, float3(1.0), 0.95 * fillAA(length(lp - h1) - 0.30 * irisR, aa));
    col = mix(col, float3(1.0), 0.95 * fillAA(length(lp - h2) - 0.13 * irisR, aa));
    if (sparkles) {
        float2 s1 = float2(0.10 * rx, 0.10 * ryo) + gz;
        float2 s2 = float2(-0.20 * rx, -0.35 * ryo) + gz;
        col = mix(col, float3(1.0), 0.9 * fillAA(sdStar4(lp - s1, 0.12 * irisR), aa));
        col = mix(col, float3(1.0), 0.9 * fillAA(sdStar4(lp - s2, 0.12 * irisR), aa));
    }
    // Soft shadow hugging the top lid: a band 0.18 ry tall right under the lid line, outline alpha 0.18 at
    // the lid fading linearly to 0 (same gradient band as the Canvas renderer).
    float lidD = top - lp.y;
    float topShade = 0.18 * (1.0 - clamp(lidD / (0.18 * ryo), 0.0, 1.0));
    col = mix(col, u.colOutline.rgb, topShade);
    return blendOver(acc, col, cov);
}

// One brow: curved capsule in the outline colour (§3.2).
static float4 drawBrow(float4 acc, float2 f, float side, float clip, float aa, constant CharacterUniforms& u) {
    float sc = u.layoutD.w;
    float oy = u.layoutE.x;
    // Clamped to the documented FacePose range like the Canvas brows (the rig allows up to 1.2).
    float raise = clamp((side < 0.0) ? u.brows.x : u.brows.y, -1.0, 1.0);
    float tiltB = (side < 0.0) ? u.brows.z : u.brows.w;
    float2 c = float2(side * u.layoutA.x * sc, oy + u.layoutB.z * sc + 0.12 * raise);
    float halfLen = max(u.layoutB.w * sc * 0.5, 1e-3);
    float th = u.layoutC.x * sc * (1.0 - 0.2 * max(0.0, -raise));
    float ang = (side < 0.0) ? (0.55 * tiltB) : (-0.55 * tiltB);
    float2 lp = rot(f - c, -ang);
    float xn = clamp(lp.x / halfLen, -1.0, 1.0);
    lp.y -= 0.03 * (1.0 - xn * xn);
    float d = length(float2(max(abs(lp.x) - halfLen, 0.0), lp.y)) - th * 0.5;
    float cov = fillAA(d, aa) * 0.9 * clip;
    return blendOver(acc, u.colOutline.rgb, cov);
}

// Viseme-driven mouth (§3.3): inverse smile warp, asymmetric ellipse, lip line, teeth, tongue.
static float4 drawMouth(float4 acc, float2 f, float clip, float aa, constant CharacterUniforms& u) {
    float sc = u.layoutD.w;
    float oy = u.layoutE.x;
    float open = clamp(u.mouthA.x, 0.0, 1.0);
    float width = clamp(u.mouthA.y, -1.0, 1.0);
    float smile = clamp(u.mouthA.z, -1.0, 1.0);
    float rnd = clamp(u.mouthA.w, 0.0, 1.0);
    float upperTeeth = clamp(u.mouthB.x, 0.0, 1.0);
    float lowerTeeth = clamp(u.mouthB.y, 0.0, 1.0);
    float tongue = clamp(u.mouthB.z, 0.0, 1.0);
    float press = clamp(u.mouthB.w, 0.0, 1.0);
    float W = u.layoutC.z * sc;
    float H = u.layoutC.w * sc;
    float2 c = float2(0.10 * u.head.z, oy + u.layoutC.y * sc + 0.05 * u.head.w - 0.03 * open);
    float w = max(W * (1.0 + 0.45 * width) * (1.0 - 0.55 * rnd) * (1.0 - 0.5 * press), 0.01);
    float h = max((0.02 + H * open * (1.0 + 0.4 * rnd)) * (1.0 - 0.85 * press), 0.003);
    float2 lp = f - c;
    // The smile warp is only defined on the mouth (|x| <= w); beyond the corners it stays at the corner value.
    float xc = clamp(lp.x / w, -1.0, 1.0);
    float lift = smile * 0.6 * W * (xc * xc - 0.33);
    float y = lp.y - lift;
    float hEff = (y > 0.0) ? (0.70 * h) : h;
    // Gradient-normalised ellipse distance, close to metric for flat mouths (resting line, p/b/m press).
    // The ellipse lies inside its bounding box, so the box distance is a lower bound of the true distance:
    // taking the max removes the estimate's underestimation beyond the corners of very flat ellipses.
    float2 rr = float2(w, hEff);
    float2 mp = float2(lp.x, y);
    float k0 = length(mp / rr);
    float k1 = length(mp / (rr * rr));
    float d = max(k0 * (k0 - 1.0) / max(k1, 1e-4), sdBox(mp, float2(0.0), rr));
    float cov = fillAA(d, aa);
    float lineA = 0.35 * min(1.0, open * 8.0 + press);
    float hw = 0.006 * (1.0 + press);
    float lineCov = strokeAA(d, hw, aa) * lineA;
    if (cov <= 0.002 && lineCov <= 0.002) {
        return acc;
    }
    float3 col = u.colMouthInner.rgb;
    // Teeth and tongue fade in with the jaw (same gate as the Canvas renderer), so a closed mouth stays a clean
    // lip line.
    float gate = smoothstep(0.02, 0.05, open);
    // teeth bands (clipped to the interior)
    float teethTop = 0.70 * h - 0.45 * h * upperTeeth;
    float upCov = fillAA(teethTop - y, aa) * step(0.001, upperTeeth) * gate;
    col = mix(col, u.colTeeth.rgb, upCov);
    float teethBot = -h + 0.35 * h * lowerTeeth;
    float lowCov = fillAA(y - teethBot, aa) * step(0.001, lowerTeeth) * gate;
    col = mix(col, u.colTeeth.rgb, lowCov);
    // tongue
    float2 tc = float2(0.0, -h * (1.0 - 0.45 * tongue));
    float2 tr = float2(0.55 * w, max(0.45 * h * tongue, 1e-4));
    float dt = sdEllipse(float2(lp.x, y), tc, tr);
    col = mix(col, u.colTongue.rgb, fillAA(dt, aa) * step(0.001, tongue) * gate);
    acc = blendOver(acc, col, cov * clip);
    acc = blendOver(acc, u.colOutline.rgb, lineCov * clip);
    return acc;
}

// Cheeks (§3.4): soft blobs in the cheek colour with the Canvas renderer's truncated-Gaussian falloff.
static float4 drawCheeks(float4 acc, float2 f, float clip, constant CharacterUniforms& u) {
    float sc = u.layoutD.w;
    float oy = u.layoutE.x;
    float r = max(u.layoutD.z * sc, 1e-3);
    float blush = clamp(u.head.x, 0.0, 1.0);
    float2 cl = float2(-u.layoutD.x * sc, oy + u.layoutD.y * sc);
    float2 cr = float2(u.layoutD.x * sc, oy + u.layoutD.y * sc);
    float2 dl = (f - cl) / r;
    float2 dr = (f - cr) / r;
    float aL = clamp(0.22 + 0.6 * blush + 0.3 * clamp(u.eyesB.z, 0.0, 1.0), 0.0, 1.0) * cheekFalloff(length(dl));
    float aR = clamp(0.22 + 0.6 * blush + 0.3 * clamp(u.eyesB.w, 0.0, 1.0), 0.0, 1.0) * cheekFalloff(length(dr));
    acc = blendOver(acc, u.colCheek.rgb, aL * clip);
    acc = blendOver(acc, u.colCheek.rgb, aR * clip);
    return acc;
}

// MARK: - Limbs and accessories (§3.6). `q` is the body-frame point.

static float4 drawLegs(float4 acc, float2 q, float aa, constant CharacterUniforms& u) {
    float3 col = u.colBodyBottom.rgb * 0.85;
    float2 cl = float2(-0.36, -1.12 + 0.25 * clamp(u.legsBounce.x, 0.0, 1.0));
    float2 cr = float2(0.36, -1.12 + 0.25 * clamp(u.legsBounce.y, 0.0, 1.0));
    float d = min(sdRoundBox(q, cl, float2(0.13, 0.15), 0.10), sdRoundBox(q, cr, float2(0.13, 0.15), 0.10));
    float rim = clamp((d + 0.05) / 0.05, 0.0, 1.0);
    col = mix(col, u.colShadow.rgb, 0.3 * rim * rim);
    return blendOver(acc, col, fillAA(d, aa));
}

// Arms are drawn behind the body; the part that sticks out gets a contact shadow near the body.
static float4 drawArms(float4 acc, float2 q, float dBody, float aa, constant CharacterUniforms& u) {
    float armL = clamp(u.armsAccessory.x, -1.0, 1.0);
    float armR = clamp(u.armsAccessory.y, -1.0, 1.0);
    float2 aL = float2(-0.92, -0.20);
    float2 bL = float2(-1.32, -0.20 + 0.90 * armL);
    float2 aR = float2(0.92, -0.20);
    float2 bR = float2(1.32, -0.20 + 0.90 * armR);
    float dL = min(sdCapsule(q, aL, bL, 0.16), sdCircle(q, bL, 0.19));
    float dR = min(sdCapsule(q, aR, bR, 0.16), sdCircle(q, bR, 0.19));
    float d = min(dL, dR);
    float3 col = bodyGradient(q.y, u);
    float rim = clamp((d + 0.06) / 0.06, 0.0, 1.0);
    col = mix(col, u.colShadow.rgb, 0.3 * rim * rim);
    float contact = 1.0 - smoothstep(-0.02, 0.14, dBody);
    col = mix(col, u.colShadow.rgb, 0.25 * contact);
    return blendOver(acc, col, fillAA(d, aa));
}

// Robe colour: accent, darker towards the bottom and the rim (the caller darkens the hood interior).
static float3 robeColor(float2 q, float dRobe, constant CharacterUniforms& u) {
    float t = clamp(q.y * 0.4 + 0.6, 0.0, 1.0);
    float3 col = mix(u.colAccent.rgb * 0.72, u.colAccent.rgb, t);
    float rim = clamp((dRobe + 0.10) / 0.10, 0.0, 1.0);
    col *= (1.0 - 0.35 * rim * rim);
    return col;
}

// .starPattern (§3.6): one tiny star per 0.28 R grid cell, hash-placed in the middle half of its cell, alpha 0.7.
// The Canvas renderer builds the same field (CharacterPaths.robeStarField) from the same integer hash.
static float starPattern(float2 q, float aa) {
    float cs = 0.28;
    float2 cellF = floor(q / cs);
    int2 cell = int2(cellF);
    float h1 = cellHash(cell, 1u);
    float h2 = cellHash(cell, 2u);
    float h3 = cellHash(cell, 3u);
    float2 cp = (cellF + 0.5 + (float2(h1, h2) - 0.5) * 0.5) * cs;
    float sz = 0.022 + 0.02 * h3;
    float d = sdStar4(q - cp, sz);
    return fillAA(d, aa) * 0.7;
}

static float4 drawDarkFace(float4 acc, float2 q, float bodyCov, float aa, constant CharacterUniforms& u) {
    float d = sdEllipse(q, float2(0.0, -0.08), float2(0.72, 0.80));
    float3 col = u.colAccent.rgb;
    float vig = smoothstep(-0.45, 0.0, d);
    col = mix(col * 1.8, col, vig);
    return blendOver(acc, col, fillAA(d, aa) * bodyCov);
}

// .innerFlame (§3.5): lighter drop at scale 0.58 (swelling 10 % with accessory2), offset (0, -0.18), alpha 0.85;
// its tip sways with a phase lead like the Canvas renderer. The caller passes palette.accent, or palette.highlight
// for .dome designs whose accent is the dark wooden base (same rule as the Canvas renderer).
static float4 drawInnerFlame(float4 acc, float2 q, float wig, float swell, float3 col, float bodyCov, float aa) {
    float k = 0.58 * (1.0 + 0.10 * swell);
    float2 lq = (q - float2(0.0, -0.18)) / k;
    float d = sdDrop(lq, 0.18 * sin(wig + 0.9)) * k;
    float cov = fillAA(d, aa + 0.03) * 0.85;
    return blendOver(acc, col, cov * bodyCov);
}

// Spark's brain (§3.6): the Canvas CharacterPaths.brain lobes and brainGrooves curves. `bp` is the brain frame in which
// the Canvas coordinates apply directly (overall radius 0.30, scaled by k = 1 + 0.08 accessory about (0, 0.62)); the
// figure is mirror-symmetric, so the right-hand lobes and curls are evaluated at (|x|, y).
static float4 drawBrain(float4 acc, float2 q, float aa, constant CharacterUniforms& u) {
    float a = clamp(u.armsAccessory.z, 0.0, 1.0);
    float k = 1.0 + 0.08 * a;
    float2 c = float2(0.0, 0.62);
    float2 bp = (q - c) / k;
    float2 m = float2(abs(bp.x), bp.y);
    float db = sdCircle(m, float2(0.13, 0.03), 0.165);
    db = smin(db, sdCircle(m, float2(0.21, -0.06), 0.115), 0.02);
    db = smin(db, sdCircle(m, float2(0.08, 0.14), 0.135), 0.02);
    float d = db * k;
    float3 col = u.colAccent.rgb;
    float shade = clamp(0.3 - bp.y * 1.6667, 0.0, 1.0);
    col = mix(col, u.colAccent2.rgb, 0.4 * shade);
    // Grooves: quadratic Beziers approximated by polylines through B(0), B(1/3), B(2/3), B(1) (B(1/2) for the gently
    // bent central fissure); chord error <= 0.006, stroke width 0.025 R in accent2 like the Canvas stroke.
    float g = min(sdSegment(bp, float2(0.0, -0.16), float2(0.015, 0.05)),
                  sdSegment(bp, float2(0.015, 0.05), float2(0.0, 0.26)));
    g = min(g, sdSegment(m, float2(0.22, 0.02), float2(0.17556, 0.09111)));
    g = min(g, sdSegment(m, float2(0.17556, 0.09111), float2(0.12222, 0.11778)));
    g = min(g, sdSegment(m, float2(0.12222, 0.11778), float2(0.06, 0.10)));
    g = min(g, sdSegment(m, float2(0.14, -0.12), float2(0.12889, -0.06444)));
    g = min(g, sdSegment(m, float2(0.12889, -0.06444), float2(0.09556, -0.03111)));
    g = min(g, sdSegment(m, float2(0.09556, -0.03111), float2(0.04, -0.02)));
    col = mix(col, u.colAccent2.rgb, fillAA(g * k - 0.0125, aa));
    float rim = clamp((d + 0.04) / 0.04, 0.0, 1.0);
    col = mix(col, u.colAccent2.rgb * 0.8, 0.5 * rim * rim);
    // Pulse glow: radial halo of radius 1.7 x the brain radius, alpha 0.6 accessory (Canvas accent2 glow gradient).
    float glow = a * 0.6 * radialFalloff(length(q - c), 0.30 * k * 1.7, 0.45, 0.4);
    acc = blendOver(acc, u.colAccent2.rgb, glow);
    return blendOver(acc, col, fillAA(d, aa));
}

static float4 drawMoonMark(float4 acc, float2 q, float aa, constant CharacterUniforms& u) {
    float a = clamp(u.armsAccessory.z, 0.0, 1.0);
    float d = max(sdCircle(q, float2(0.0, 0.55), 0.17), -sdCircle(q, float2(0.08, 0.60), 0.14));
    // Glow: radial halo r 0.40 centred on the crescent, alpha 0.8 (0.4 + 0.6 accessory) (Canvas accent2 glow gradient).
    float glow = (0.4 + 0.6 * a) * 0.8 * radialFalloff(length(q - float2(-0.03, 0.56)), 0.40, 0.45, 0.4);
    acc = blendOver(acc, u.colAccent2.rgb, glow);
    return blendOver(acc, u.colAccent2.rgb, fillAA(d, aa));
}

static float4 drawCapAndLeaves(float4 acc, float2 q, float dBody, float time, float aa, constant CharacterUniforms& u) {
    float a = clamp(u.armsAccessory.z, 0.0, 1.0);
    float edgeY = 0.35 - 0.09 * (0.5 + 0.5 * cos(q.x * 10.0));
    float dCap = max(dBody, edgeY - q.y);
    float3 capCol = u.colAccent.rgb;
    float t = clamp(q.y * 0.8, 0.0, 1.0);
    capCol = mix(capCol * 0.8, capCol, t);
    float2 hp = rot(q - float2(-0.30, 0.75), 0.5235988);
    float hl = (1.0 - smoothstep(0.3, 1.0, length(hp / float2(0.30, 0.15)))) * 0.3;
    capCol = mix(capCol, u.colHighlight.rgb, hl);
    float rim = clamp((dCap + 0.05) / 0.05, 0.0, 1.0);
    capCol = mix(capCol, capCol * 0.7, 0.5 * rim * rim);
    float under = (1.0 - smoothstep(0.0, 0.07, edgeY - q.y)) * step(q.y, edgeY);
    acc = blendOver(acc, u.colShadow.rgb, 0.25 * under * fillAA(dBody, aa));
    acc = blendOver(acc, capCol, fillAA(dCap, aa));
    // Leaves wiggle +-8 degrees with accessory at 2.5 rad/s; stem and veins in the cap colour darkened 30 %
    // (same geometry and colours as the Canvas renderer).
    float wob = 0.1396 * a * sin(time * 2.5);
    float2 l1 = rot(q - float2(-0.25, 1.05), 0.6109 - wob);
    float2 l2 = rot(q - float2(0.30, 1.08), -0.6981 + wob);
    float d1 = sdEllipse(l1, float2(0.0), float2(0.15, 0.07));
    float d2 = sdEllipse(l2, float2(0.0), float2(0.15, 0.07));
    float dl = min(d1, d2);
    float3 darkCap = u.colAccent.rgb * 0.7;
    float stem = sdCapsule(q, float2(0.0, 0.90), float2(0.03, 1.10), 0.035);
    float v1 = length(float2(max(abs(l1.x) - 0.12, 0.0), l1.y)) - 0.006;
    float v2 = length(float2(max(abs(l2.x) - 0.12, 0.0), l2.y)) - 0.006;
    float3 lcol = mix(u.colAccent2.rgb, darkCap, fillAA(min(v1, v2), aa));
    acc = blendOver(acc, darkCap, fillAA(stem, aa));
    acc = blendOver(acc, lcol, fillAA(dl, aa));
    return acc;
}

// .cloudCurl (§3.6): spiral stroke width 0.14 at (-0.45, 0.75), bouncing 0.06 sin(4t) with accessory2.
static float4 drawCloudCurl(float4 acc, float2 q, float time, float aa, constant CharacterUniforms& u) {
    float b = clamp(u.armsAccessory.w, 0.0, 1.0);
    float2 c = float2(-0.45, 0.75 + 0.06 * sin(time * 4.0) * b);
    float2 lp = q - c;
    if (dot(lp, lp) > 0.30) {
        return acc;
    }
    // Same curve as the Canvas spiral (radius 0.30 at angle 0.9 pi winding counter-clockwise 1.25 turns
    // in to radius 0.05). Mirrored in y and rotated by -0.6 pi it becomes r = 0.05 + b theta, theta in [0, 2.5 pi].
    float2 sp = rot(float2(lp.x, -lp.y), -0.6 * kPi);
    float d = sdSpiral(sp, 0.05, 0.25 / (1.25 * kTwoPi), 1.25) - 0.07;
    float3 col = bodyGradient(q.y, u);
    col = mix(col, u.colHighlight.rgb, 0.3 * (1.0 - smoothstep(0.0, 0.3, length(lp - float2(-0.08, 0.10)))));
    float rim = clamp((d + 0.05) / 0.05, 0.0, 1.0);
    col = mix(col, u.colShadow.rgb, 0.3 * rim * rim);
    acc = blendOver(acc, u.colShadow.rgb, 0.2 * (1.0 - smoothstep(0.0, 0.08, d)) * step(0.0, d));
    return blendOver(acc, col, fillAA(d, aa));
}

static float4 drawBookAndWand(float4 acc, float2 q, float aa, constant CharacterUniforms& u) {
    float a1 = clamp(u.armsAccessory.z, 0.0, 1.0);
    float a2 = clamp(u.armsAccessory.w, 0.0, 1.0);
    // Book: rounded rect 0.50 x 0.38, corner 0.06, at (-0.98, -0.45) rotated 15 degrees.
    float2 bc = float2(-0.98, -0.45);
    float2 lp = rot(q - bc, -0.2618);
    float dCover = sdRoundBox(lp, float2(0.0), float2(0.25, 0.19), 0.06);
    float starA = 0.5 + 0.5 * a1;
    float3 col = mix(u.colAccent2.rgb * 0.7, u.colAccent2.rgb, clamp(lp.y * 2.0 + 0.6, 0.0, 1.0));
    float rim = clamp((dCover + 0.04) / 0.04, 0.0, 1.0);
    col = mix(col, u.colOutline.rgb, 0.4 * rim * rim);
    // Page edge: rounded rect 0.05 x 0.32, corner 0.015, at (0.215, 0) in palette.teeth (Canvas pageEdge).
    float dEdge = sdRoundBox(lp, float2(0.215, 0.0), float2(0.025, 0.16), 0.015);
    col = mix(col, u.colTeeth.rgb, fillAA(dEdge, aa));
    acc = blendOver(acc, col, fillAA(dCover, aa));
    // Cover star like the Canvas book: a soft glow halo of radius 0.24 around the star (glow gradient 1, 0.45 at 0.4, 0),
    // then the 4-point star (radius 0.09, upright: only its centre follows the book) in palette.highlight, both at
    // alpha 0.5 + 0.5 accessory.
    float2 sc = bc + rot(float2(-0.04, 0.02), 0.2618);
    acc = blendOver(acc, u.colGlow.rgb, starA * radialFalloff(length(q - sc), 0.24, 0.4, 0.45));
    float dStar = sdStar4(q - sc, 0.09);
    acc = blendOver(acc, u.colHighlight.rgb, starA * fillAA(dStar, aa));
    // Wand: capsule (0.85,-0.30) -> (1.25,0.35), radius 0.05, star at the tip.
    float2 wa = float2(0.85, -0.30);
    float2 wb = float2(1.25, 0.35);
    float dW = sdCapsule(q, wa, wb, 0.05);
    float2 dir = normalize(wb - wa);
    float2 nrm = float2(-dir.y, dir.x);
    float off = dot(q - wa, nrm);
    float3 wcol = u.colShadow.rgb;
    wcol = mix(wcol, u.colHighlight.rgb, 0.35 * fillAA(abs(off - 0.02) - 0.012, aa));
    acc = blendOver(acc, wcol, fillAA(dW, aa));
    // Tip: 4-point star at (1.28, 0.40) in the highlight colour, radius 0.11 + 0.03 accessory2. The glow
    // (alpha = accessory2) is a finite radial halo of radius 0.28 measured with a metric distance, so it
    // never reaches the early-out contour (same gradient as the Canvas renderer).
    float2 tip = float2(1.28, 0.40);
    acc = blendOver(acc, u.colGlow.rgb, a2 * radialFalloff(length(q - tip), 0.28, 0.4, 0.45));
    float dTip = sdStar4(q - tip, 0.11 + 0.03 * a2);
    acc = blendOver(acc, u.colHighlight.rgb, fillAA(dTip, aa));
    return acc;
}

// MARK: - Dome (world space `p`, so the jar does not move with the body)

static float4 drawDomeBase(float4 acc, float2 p, float aa, constant CharacterUniforms& u) {
    float dBase = sdRoundBox(p, float2(0.0, -1.55), float2(1.70, 0.25), 0.12);
    float3 col = u.colAccent.rgb;
    float t = clamp((p.y + 1.80) / 0.50, 0.0, 1.0);
    col = mix(col * 0.65, col * 1.1, t);
    float grain = sin(p.x * 18.0 + sin(p.y * 30.0) * 1.5) * 0.5 + 0.5;
    col *= (0.94 + 0.06 * grain);
    float dPlate = sdRoundBox(p, float2(0.0, -1.55), float2(0.55, 0.11), 0.04);
    col = mix(col, u.colAccent.rgb * 0.55, fillAA(dPlate, aa));
    col = mix(col, u.colAccent2.rgb, 0.25 * strokeAA(dPlate, 0.008, aa));
    float rim = clamp((dBase + 0.04) / 0.04, 0.0, 1.0);
    col = mix(col, u.colAccent.rgb * 0.5, 0.5 * rim * rim);
    acc = blendOver(acc, float3(0.0), 0.25 * exp(-max(dBase, 0.0) / 0.15) * step(0.0, dBase) * step(p.y, -1.6));
    return blendOver(acc, col, fillAA(dBase, aa));
}

// Dome glass outline (§3.6): circle r 1.55 at (0, 0.10) united with the box x in [-1.55, 1.55], y in [-1.30, 0.10].
static inline float sdDomeGlass(float2 p) {
    return min(sdCircle(p, float2(0.0, 0.10), 1.55), sdBox(p, float2(0.0, -0.60), float2(1.55, 0.70)));
}

// Glass layer composited over `acc`. With acc = 0 it returns the glass alone (premultiplied), which the sparkle pass
// uses to put the fireflies under the glass.
static float4 drawDomeGlass(float4 acc, float2 p, float aa, constant CharacterUniforms& u) {
    float dG = sdDomeGlass(p);
    float inside = fillAA(dG, aa);
    float3 glass = u.colAccent2.rgb;
    acc = blendOver(acc, glass, 0.10 * inside);
    acc = blendOver(acc, glass, 0.35 * strokeAA(dG, 0.015, aa));
    float dS = sdCapsule(p, float2(-1.05, 0.45), float2(-0.55, 1.30), 0.05);
    acc = blendOver(acc, float3(1.0), 0.35 * fillAA(dS, aa + 0.02));
    float dS2 = sdCapsule(p, float2(-1.22, 0.05), float2(-1.15, 0.30), 0.03);
    acc = blendOver(acc, float3(1.0), 0.25 * fillAA(dS2, aa + 0.02));
    float refl = strokeAA(dG + 0.10, 0.03, aa) * (1.0 - smoothstep(-1.30, -0.80, p.y)) * 0.15;
    acc = blendOver(acc, float3(1.0), refl);
    return acc;
}

// MARK: - Comic effects (§3.7)

// "?" glyph centred on the origin: an open ring (hook), a short stem and a dot.
static inline float sdQuestionGlyph(float2 lp) {
    float2 rl = lp - float2(0.0, 0.14);
    float ring = abs(length(rl) - 0.10) - 0.03;
    float ang = atan2(rl.y, rl.x);
    if (ang < -1.5708) {
        // Open lower-left sector of the hook: distance to the two arc ends (round caps, continuous field).
        ring = min(length(rl - float2(-0.10, 0.0)), length(rl - float2(0.0, -0.10))) - 0.03;
    }
    float stem = sdCapsule(lp, float2(0.0, 0.04), float2(0.0, -0.06), 0.03);
    float dotD = sdCircle(lp, float2(0.0, -0.16), 0.038);
    return min(ring, min(stem, dotD));
}

// "!" glyph centred on the origin: a tapering bar and a dot.
static inline float sdExclamationGlyph(float2 lp) {
    float bar = sdUnevenCapsule(lp, float2(0.0, 0.20), float2(0.0, -0.04), 0.045, 0.03);
    float dotD = sdCircle(lp, float2(0.0, -0.15), 0.04);
    return min(bar, dotD);
}

static float4 drawEffects(float4 acc, float2 p, float2 q, float2 f, float time, float aa, constant CharacterUniforms& u) {
    float tears = clamp(u.fxA.x, 0.0, 1.0);
    float sweat = clamp(u.fxA.y, 0.0, 1.0);
    float hearts = clamp(u.fxA.z, 0.0, 1.0);
    float zzz = clamp(u.fxA.w, 0.0, 1.0);
    float question = clamp(u.fxB.x, 0.0, 1.0);
    float excl = clamp(u.fxB.y, 0.0, 1.0);
    // Tears, sweat, hearts and zzz follow the Canvas renderer's paths, timing and colours.
    float3 dropCol = float3(0.6, 0.8, 1.0);
    if (tears > 0.002) {
        // Head frame: (+-(eyeOffsetX + 0.05) s, faceOffsetY + eyeY s - 0.35), sliding down 0.15 fract(0.8 t).
        float sc = u.layoutD.w;
        float oy = u.layoutE.x;
        float slide = 0.15 * fract(time * 0.8);
        float ty = oy + u.layoutA.y * sc - 0.35 - slide;
        float2 c1 = float2(-(u.layoutA.x + 0.05) * sc, ty);
        float2 c2 = float2((u.layoutA.x + 0.05) * sc, ty);
        float d = min(sdWaterDrop(f, c1, 0.07), sdWaterDrop(f, c2, 0.07));
        acc = blendOver(acc, dropCol, tears * fillAA(d, aa));
    }
    if (sweat > 0.002) {
        // Head frame (moves with the head like the Canvas renderer): (+0.75, +0.55) sliding down 0.10 fract(0.9 t).
        float2 c = float2(0.75, 0.55 - 0.10 * fract(time * 0.9));
        float d = sdWaterDrop(f, c, 0.07);
        acc = blendOver(acc, dropCol, sweat * fillAA(d, aa));
    }
    if (hearts > 0.002) {
        // Three hearts in palette.tongue rising from (+-0.9, 0.9): heart k (size s = 0.10 + 0.03 k, half width ~ s,
        // tip 0.9 s below its centre) at x = side (0.9 + 0.08 sin(2 t + k)), y = 0.9 + 0.75 life.
        float3 hcol = u.colTongue.rgb;
        for (int i = 0; i < 3; i++) {
            float fi = float(i);
            float life = fract(time * 0.55 + fi / 3.0);
            float side = (i == 1) ? -1.0 : 1.0;
            float2 c = float2(side * (0.9 + 0.08 * sin(time * 2.0 + fi)), 0.9 + 0.75 * life);
            float s = 0.10 + 0.03 * fi;
            float k = 1.6 * s;
            float d = sdHeart((p - c + float2(0.0, 0.9 * s)) / k) * k;
            float a = hearts * sin(kPi * life);
            acc = blendOver(acc, hcol, a * fillAA(d, aa));
        }
    }
    if (zzz > 0.002) {
        // Three white "z" glyphs with an outline-coloured drop shadow, like the Canvas Text glyphs: glyph k is set
        // at font size F = (0.20 + 0.07 k)(0.8 + 0.4 life) R around (0.70 + 0.22 k + 0.25 life, 1.25 + 0.30 k + 0.45 life);
        // the lowercase z is about 0.54 F tall and sits 0.09 F below that anchor; the shadow is offset (0.05 F, -0.05 F).
        float3 shadowCol = u.colOutline.rgb;
        for (int i = 0; i < 3; i++) {
            float fi = float(i);
            float life = fract(time * 0.45 + fi / 3.0);
            float fontSize = (0.20 + 0.07 * fi) * (0.8 + 0.4 * life);
            float2 c = float2(0.70 + 0.22 * fi + 0.25 * life, 1.25 + 0.30 * fi + 0.45 * life - 0.09 * fontSize);
            float2 lp = p - c;
            float reach = 0.6 * fontSize;
            if (dot(lp, lp) > reach * reach) {
                continue;
            }
            float s = 0.27 * fontSize;
            float th = 0.22 * s;
            float2 sp = lp - float2(0.05 * fontSize, -0.05 * fontSize);
            float dz = min(sdCapsule(lp, float2(-0.68 * s, 0.78 * s), float2(0.68 * s, 0.78 * s), th),
                           sdCapsule(lp, float2(-0.68 * s, -0.78 * s), float2(0.68 * s, -0.78 * s), th));
            dz = min(dz, sdCapsule(lp, float2(0.60 * s, 0.70 * s), float2(-0.60 * s, -0.70 * s), th));
            float ds = min(sdCapsule(sp, float2(-0.68 * s, 0.78 * s), float2(0.68 * s, 0.78 * s), th),
                           sdCapsule(sp, float2(-0.68 * s, -0.78 * s), float2(0.68 * s, -0.78 * s), th));
            ds = min(ds, sdCapsule(sp, float2(0.60 * s, 0.70 * s), float2(-0.60 * s, -0.70 * s), th));
            float a = zzz * sin(kPi * life);
            acc = blendOver(acc, shadowCol, a * 0.6 * fillAA(ds, aa));
            acc = blendOver(acc, float3(1.0), a * fillAA(dz, aa));
        }
    }
    float bob = 0.03 * sin(time * 3.0);
    // Glyphs at (0.75, 1.35) about 0.45 R tall (spanning y 1.15...1.62), like the Canvas 0.55 R text, in the Canvas glyph
    // style (same as the zzz above): white with an outline-coloured drop shadow (alpha 0.6) offset (0.05 F, -0.05 F),
    // F = 0.55 R.
    float2 shadowOff = float2(0.0275, -0.0275);
    if (question > 0.002) {
        float2 lp = p - float2(0.75, 1.35 + bob);
        float d = sdQuestionGlyph(lp);
        float ds = sdQuestionGlyph(lp - shadowOff);
        acc = blendOver(acc, u.colOutline.rgb, question * 0.6 * fillAA(ds, aa));
        acc = blendOver(acc, float3(1.0), question * fillAA(d, aa));
    }
    if (excl > 0.002) {
        float2 lp = p - float2(0.75, 1.35 + bob);
        float d = sdExclamationGlyph(lp);
        float ds = sdExclamationGlyph(lp - shadowOff);
        acc = blendOver(acc, u.colOutline.rgb, excl * 0.6 * fillAA(ds, aa));
        acc = blendOver(acc, float3(1.0), excl * fillAA(d, aa));
    }
    return acc;
}

// MARK: - Character pass: one full-screen triangle

struct CharacterVaryings {
    float4 position [[position]];
    float2 ndc;
};

vertex CharacterVaryings characterVertex(uint vid [[vertex_id]]) {
    CharacterVaryings out;
    float2 pos = float2((vid == 1u) ? 3.0 : -1.0, (vid == 2u) ? 3.0 : -1.0);
    out.position = float4(pos, 0.0, 1.0);
    out.ndc = pos;
    return out;
}

fragment float4 characterFragment(CharacterVaryings in [[stage_in]],
                                  constant CharacterUniforms& u [[buffer(0)]]) {
    // Pixel -> R units (§2): R = 0.5 * min(w, h) * radiusScale, origin shifted by centerOffsetY.
    float w = max(u.viewport.x, 1.0);
    float h = max(u.viewport.y, 1.0);
    float mn = max(min(w, h) * u.layoutE.y, 1e-3);
    float2 p = float2(in.ndc.x * w / mn, in.ndc.y * h / mn - u.layoutE.z);
    float2 fw = fwidth(p);
    float aa = max(max(fw.x, fw.y), 1e-4);
    float time = u.viewport.w;
    uint features = uint(max(u.style.y, 0.0) + 0.5);
    int shape = int(u.style.x + 0.5);
    float wig = u.bodyParams.w;

    bool floats = hasFeature(features, kFeatFloats);
    bool hasHood = hasFeature(features, kFeatHood);
    bool hasDome = hasFeature(features, kFeatDome);
    bool darkFace = hasFeature(features, kFeatDarkFace);
    bool sparkles = hasFeature(features, kFeatEyeSparkles);
    bool starPat = hasFeature(features, kFeatStarPattern);

    // Inverse body transform (§2): undo translate, tilt about the anchor, scale about the anchor.
    // Breathing is added on top of body.scale (§3.5), scaled by the design's idle.breathDepth, which the renderer
    // stores in the spare layoutE.w slot.
    float2 anchor = floats ? float2(0.0, 0.0) : float2(0.0, -1.0);
    float breathe = u.bodyParams.y * u.layoutE.w;
    float sx = max(u.transform.z - 0.015 * breathe, 0.05);
    float sy = max(u.transform.w + 0.025 * breathe, 0.05);
    float2 q = p - u.transform.xy;
    q = anchor + rot(q - anchor, u.bodyParams.x);
    q = anchor + (q - anchor) / float2(sx, sy);
    float aaB = aa / min(sx, sy);

    float flicker = hasFeature(features, kFeatFlicker) ? (0.012 * sin(time * (8.0 + 6.0 * u.idle.w) + q.y * 7.0)) : 0.0;
    float dBody = sdBody(q, shape, wig, flicker);

    // Outer glow (§3.5). Evaluated everywhere (clamped to its edge value inside) so it stays continuous
    // across the silhouette's anti-aliasing band; the opaque body covers it inside.
    float glowA = clamp(u.style.z * u.bodyParams.z * exp(-max(dBody, 0.0) / 0.35) * 0.7, 0.0, 1.0);
    float4 acc = float4(u.colGlow.rgb * glowA, glowA);

    // Face frame: invert the head transform (§2) — rotate by headTilt about (0, faceOffsetY), shift by turn/nod.
    float2 c0 = float2(0.0, u.layoutE.x);
    float2 f = q - float2(0.10 * u.head.z, 0.06 * u.head.w);
    f = c0 + rot(f - c0, u.head.y);

    // Early-out far from the body: only the glow and the floating comic effects (hearts, zzz, glyphs) live there.
    if (dBody > 1.45 && !hasDome) {
        return drawEffects(acc, p, q, f, time, aaB, u);
    }

    // 1. Dome base behind everything.
    if (hasDome) {
        acc = drawDomeBase(acc, p, aa, u);
    }

    // 2. Robe back (.hood): the body shows only through the face opening.
    // Robe colour and star pattern are evaluated once and reused for the robe front (step 5).
    float opening = 1.0;
    float robeCov = 0.0;
    float3 robeBase = float3(0.0);
    float robeStars = 0.0;
    if (hasHood) {
        float peakX = 0.08 * sin(wig);
        float dRobe = sdRobe(q, peakX);
        robeCov = fillAA(dRobe, aaB);
        float dOpen = sdEllipse(q, float2(0.0, 0.05), float2(0.80, 0.84));
        opening = fillAA(dOpen, aaB);
        robeBase = robeColor(q, dRobe, u);
        robeStars = starPat ? starPattern(q, aaB) : 0.0;
        // The hood interior seen through the face opening is darker.
        acc = blendOver(acc, mix(robeBase, robeBase * 0.45, opening), robeCov);
        acc = blendOver(acc, u.colAccent2.rgb, robeStars * robeCov * (1.0 - opening));
    }

    // 3. Limbs behind the body.
    if (hasFeature(features, kFeatLegs)) {
        acc = drawLegs(acc, q, aaB, u);
    }
    if (hasFeature(features, kFeatArms)) {
        acc = drawArms(acc, q, dBody, aaB, u);
    }

    // 4. Body with shading, then the dark face / inner flame layers.
    float bodyCov = fillAA(dBody, aaB) * opening;
    acc = blendOver(acc, bodyColor(q, dBody, u), bodyCov);
    if (starPat && !hasHood) {
        acc = blendOver(acc, u.colAccent2.rgb, starPattern(q, aaB) * bodyCov);
    }
    if (darkFace) {
        acc = drawDarkFace(acc, q, bodyCov, aaB, u);
    }
    if (hasFeature(features, kFeatInnerFlame)) {
        float3 innerCol = hasDome ? u.colHighlight.rgb : u.colAccent.rgb;
        acc = drawInnerFlame(acc, q, wig, clamp(u.armsAccessory.w, 0.0, 1.0), innerCol, bodyCov, aaB);
    }

    // 5. Robe front over the body (below y = -0.55, slightly curved collar).
    float front = 0.0;
    if (hasHood) {
        float collar = -0.55 + 0.05 * q.x * q.x;
        front = robeCov * (1.0 - smoothstep(collar - aaB, collar + aaB, q.y));
        acc = blendOver(acc, robeBase, front);
        acc = blendOver(acc, u.colAccent2.rgb, robeStars * front);
    }

    // 6. Accessories on the body.
    if (hasFeature(features, kFeatBrain)) {
        acc = drawBrain(acc, q, aaB, u);
    }
    if (hasFeature(features, kFeatMoonMark)) {
        acc = drawMoonMark(acc, q, aaB, u);
    }
    if (hasFeature(features, kFeatLeaves)) {
        acc = drawCapAndLeaves(acc, q, dBody, time, aaB, u);
    }
    if (hasFeature(features, kFeatCloudCurl)) {
        acc = drawCloudCurl(acc, q, time, aaB, u);
    }

    // 7. Face (in the head frame `f` computed above), clipped to the body, the hood opening and the robe front.
    float faceClip = fillAA(dBody + 0.01, aaB) * opening * (1.0 - front);
    acc = drawCheeks(acc, f, faceClip, u);
    acc = drawEye(acc, f, -1.0, u.eyesA.x, u.eyesB.z, faceClip, darkFace, sparkles, aaB, u);
    acc = drawEye(acc, f, 1.0, u.eyesA.y, u.eyesB.w, faceClip, darkFace, sparkles, aaB, u);
    acc = drawBrow(acc, f, -1.0, faceClip, aaB, u);
    acc = drawBrow(acc, f, 1.0, faceClip, aaB, u);
    acc = drawMouth(acc, f, faceClip, aaB, u);

    // 8. Hand-held props in front of the body.
    if (hasFeature(features, kFeatBookAndWand)) {
        acc = drawBookAndWand(acc, q, aaB, u);
    }

    // 9. Comic effects, 10. dome glass in front of everything.
    acc = drawEffects(acc, p, q, f, time, aaB, u);
    if (hasDome) {
        acc = drawDomeGlass(acc, p, aa, u);
    }
    return acc;
}

// MARK: - Sparkle pass: 60 instanced quads (40 ambient + 20 burst), §3.8

struct SparkleVaryings {
    float4 position [[position]];
    float2 uv;
    float2 world;
    float alpha [[flat]];
};

vertex SparkleVaryings sparkleVertex(uint vid [[vertex_id]],
                                     uint iid [[instance_id]],
                                     constant CharacterUniforms& u [[buffer(0)]]) {
    SparkleVaryings out;
    float i = float(iid);
    float time = u.viewport.w;
    // precise::sin: the hash argument reaches ~770 rad, where fast-math sin drifts from Swift's Float sin.
    float seed = fract(precise::sin(i * 12.9898) * 43758.5453);
    float seed2 = fract(seed * 7.1 + 0.37);
    uint features = uint(max(u.style.y, 0.0) + 0.5);
    bool dome = hasFeature(features, kFeatDome);
    // .dome: `accessory` turns the first round(20 accessory) burst slots into extra ambient fireflies
    // (instances 40..., ambient formula, same seeds as the Canvas renderer's boost particles).
    float boost = dome ? floor(clamp(u.armsAccessory.z, 0.0, 1.0) * 20.0 + 0.5) : 0.0;
    bool burst = iid >= 40u && (i - 40.0) >= boost;
    float T = burst ? 0.6 : (2.2 + 1.8 * seed2);
    float t = fract(time / T + seed);
    float dir = (seed2 > 0.5) ? 1.0 : -1.0;
    float ang = seed * 6.2831853 + time * 0.15 * dir;
    float rad = burst ? (0.3 + 1.4 * t) : (1.10 + 0.60 * fract(seed * 3.3));
    // One position formula for ambient and burst particles (§3.8: a burst only changes rate, rad and lifetime).
    float2 pos = float2(cos(ang) * rad, sin(ang) * rad * 0.6 + (t - 0.5) * 0.6);
    float env = sin(kPi * t);
    float size = 0.05 * (0.6 + fract(seed * 5.5)) * env;
    float rate = burst ? clamp(u.fxB.z, 0.0, 1.0) : clamp(u.fxB.w, 0.0, 1.0);
    float alpha = env * rate;
    if (dome && sdDomeGlass(pos) > size * 2.3) {
        // Fireflies live inside the glass: a quad entirely outside it (corner distance 1.6 sqrt(2) size) is culled here;
        // sparkleFragment clips the others per pixel at the glass wall, like the Canvas clip.
        alpha = 0.0;
    }
    if (alpha <= 0.004) {
        // Invisible particle: collapse the quad so it produces no fragments.
        size = 0.0;
    }
    float cx = (vid == 1u || vid == 4u || vid == 5u) ? 1.0 : -1.0;
    float cy = (vid == 2u || vid == 3u || vid == 5u) ? 1.0 : -1.0;
    float2 corner = float2(cx, cy);
    float w = max(u.viewport.x, 1.0);
    float h = max(u.viewport.y, 1.0);
    float mn = max(min(w, h) * u.layoutE.y, 1e-3);
    float2 world = pos + corner * size * 1.6;
    float2 ndc = float2(world.x * mn / w, (world.y + u.layoutE.z) * mn / h);
    out.position = float4(ndc, 0.0, 1.0);
    out.uv = corner;
    out.world = world;
    out.alpha = alpha;
    return out;
}

fragment float4 sparkleFragment(SparkleVaryings in [[stage_in]],
                                constant CharacterUniforms& u [[buffer(0)]]) {
    float2 a = abs(in.uv) * 1.6;
    float s = sqrt(a.x) + sqrt(a.y);
    float star = 1.0 - smoothstep(0.55, 1.0, s);
    float core = exp(-dot(in.uv, in.uv) * 5.0) * 0.6;
    float m = clamp(star + core, 0.0, 1.0) * in.alpha;
    float2 fw = fwidth(in.world);
    float aa = max(max(fw.x, fw.y), 1e-4);
    uint features = uint(max(u.style.y, 0.0) + 0.5);
    if (hasFeature(features, kFeatDome)) {
        // Canvas order: fireflies clipped to the glass, then the glass G over them. The character pass already left
        // G + (1 - G.a) D in the target, so adding (1 - G.a) S here yields G + (1 - G.a) (D + S): the fireflies sit under
        // the glass and its highlights, tinted by it, without a third pass.
        float4 glass = drawDomeGlass(float4(0.0), in.world, aa, u);
        m *= fillAA(sdDomeGlass(in.world), aa) * (1.0 - glass.a);
    }
    float3 col = mix(u.colGlow.rgb, float3(1.0), 0.5);
    return float4(col * m, m);
}
