import Foundation

/// Runtime fallback for the Metal shader library. SwiftPM ships `Shaders/CharacterShaders.metal` as a
/// compiled `default.metallib` inside `Bundle.module`; when that library cannot be loaded the renderer
/// compiles this source at runtime (`MTLDevice.makeLibrary(source:options:)`).
///
/// The text below is byte-identical to `Metal/Shaders/CharacterShaders.metal` (enforced by
/// `tools/check.py` and `MetalShaderTests`). Edit the `.metal` file and regenerate this one;
/// never edit the string by hand.
public enum CharacterShaderSource {
    /// Metal Shading Language source of the character and sparkle pipelines.
    public static let msl: String = #"""
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
    float4 layoutE;         // faceOffsetY, radiusScale, centerOffsetY, spare
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

static inline float hash11(float n) {
    return fract(sin(n * 12.9898) * 43758.5453);
}

static inline float hash21(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
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
    float2 q = abs(p) / max(r, 1e-5);
    float s = sqrt(q.x) + sqrt(q.y);
    return (s - 1.0) * r * 0.5;
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

// Archimedean spiral stroke centre line: r = a + b * theta, theta in [0, turns * 2pi].
static inline float sdSpiral(float2 p, float a, float b, float turns) {
    float r = length(p);
    float t = atan2(p.y, p.x);
    float maxTheta = turns * kTwoPi;
    float k = round(((r - a) / max(b, 1e-5) - t) / kTwoPi);
    float theta = clamp(t + kTwoPi * k, 0.0, maxTheta);
    float d0 = abs(r - (a + b * theta));
    float thetaB = clamp(t + kTwoPi * (k - 1.0), 0.0, maxTheta);
    float d1 = abs(r - (a + b * thetaB));
    float thetaC = clamp(t + kTwoPi * (k + 1.0), 0.0, maxTheta);
    float d2 = abs(r - (a + b * thetaC));
    return min(d0, min(d1, d2));
}

// MARK: - Body silhouettes (§3.5), unit space before the body transform

// Teardrop: circle r 0.85 at (0, -0.15) smoothly joined to a tip at (tipX, 1.05); convex sides.
static inline float sdDrop(float2 q, float tipX) {
    float dc = sdCircle(q, float2(0.0, -0.15), 0.85);
    float dt = sdUnevenCapsule(q, float2(0.0, 0.25), float2(tipX, 1.01), 0.60, 0.04);
    return smin(dc, dt, 0.30);
}

// Hooded wisp: drop whose tip curls to the upper-right (0,0.9) -> (0.25,1.25) -> (0.55,1.05).
static inline float sdHood(float2 q, float wig) {
    float sway = 0.06 * sin(wig);
    float dc = sdCircle(q, float2(0.0, -0.15), 0.85);
    float2 p0 = float2(0.0, 0.90);
    float2 p1 = float2(0.25 + sway, 1.25);
    float2 p2 = float2(0.55 + sway * 1.5, 1.05);
    float neck = sdUnevenCapsule(q, float2(0.0, 0.20), p0, 0.62, 0.22);
    float c1 = sdUnevenCapsule(q, p0, p1, 0.22, 0.15);
    float c2 = sdUnevenCapsule(q, p1, p2, 0.15, 0.08);
    float d = smin(dc, neck, 0.30);
    d = smin(d, c1, 0.10);
    d = smin(d, c2, 0.08);
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

// Flame: drop with the upper half modulated r * (1 + 0.06 sin(5t + 3w) + 0.03 sin(9t - 2w)).
static inline float sdFlame(float2 q, float wig, float flicker) {
    float tipX = 0.22 * sin(wig);
    float d = sdDrop(q, tipX);
    float theta = atan2(q.y, q.x);
    float upper = smoothstep(-0.15, 0.25, q.y);
    float r = length(q);
    float m = 0.06 * sin(5.0 * theta + 3.0 * wig) + 0.03 * sin(9.0 * theta - 2.0 * wig) + flicker;
    d -= m * r * upper;
    return d;
}

static inline float sdBody(float2 q, int shape, float wig, float flicker) {
    if (shape == 1) {
        return sdStar5(q, 0.93, 0.45) - 0.12;
    }
    if (shape == 2) {
        return sdDrop(q, 0.18 * sin(wig));
    }
    if (shape == 3) {
        return sdHood(q, wig);
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

// Water-drop glyph used by tears and sweat: round bottom at c, small point above.
static inline float sdWaterDrop(float2 p, float2 c, float r) {
    return sdUnevenCapsule(p, c + float2(0.0, r * 1.15), c, r * 0.12, r);
}

// Robe of the .hood feature: teardrop circle r 1.28 at (0,-0.25) with a peak at (peakX, 1.38).
static inline float sdRobe(float2 q, float peakX) {
    float dc = sdCircle(q, float2(0.0, -0.25), 1.28);
    float dp = sdUnevenCapsule(q, float2(0.0, 0.30), float2(peakX, 1.33), 0.90, 0.05);
    return smin(dc, dp, 0.30);
}

// MARK: - Face (§3.1–§3.4). `f` is the face-frame point (head transform already inverted).

// One eye. side = -1 (viewer's left) or +1 (viewer's right).
static float4 drawEye(float4 acc, float2 f, float side, float eyeOpen, float lowerLid, float clip,
                      bool darkFace, bool sparkles, float aa, constant CharacterUniforms& u) {
    float sc = u.layoutD.w;
    float oy = u.layoutE.x;
    float es = u.eyesB.y;
    float2 c = float2(side * u.layoutA.x * sc, oy + u.layoutA.y * sc);
    float rx = u.layoutA.z * sc * es;
    float ry = u.layoutA.w * sc * es;
    float turn = u.head.z;
    if (side * turn < 0.0) {
        rx *= (1.0 - 0.15 * abs(turn));
    }
    float o = max(eyeOpen, 0.0);
    float ryo = ry * max(o, 1.0);
    float top = -ryo + 2.0 * ryo * min(o, 1.0);
    float bot = -ryo + 2.0 * ryo * 0.55 * clamp(lowerLid, 0.0, 1.0);
    float2 lp = f - c;
    float dEll = sdEllipse(lp, float2(0.0), float2(rx, ryo));
    float dVis = max(dEll, max(lp.y - top, bot - lp.y));
    float cov = fillAA(dVis, aa) * clip;
    if (cov <= 0.002) {
        return acc;
    }
    float irisR = u.layoutB.x * sc * es;
    float2 io = float2(u.eyesA.z, u.eyesA.w) * float2(rx - irisR, ry - irisR) * 0.85;
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
    float2 h1 = float2(-0.38 * rx, 0.42 * ry) + gz;
    float2 h2 = float2(0.30 * rx, -0.30 * ry) + gz;
    col = mix(col, float3(1.0), 0.95 * fillAA(length(lp - h1) - 0.30 * irisR, aa));
    col = mix(col, float3(1.0), 0.95 * fillAA(length(lp - h2) - 0.13 * irisR, aa));
    if (sparkles) {
        float2 s1 = float2(0.10 * rx, 0.10 * ry) + gz;
        float2 s2 = float2(-0.20 * rx, -0.35 * ry) + gz;
        col = mix(col, float3(1.0), 0.9 * fillAA(sdStar4(lp - s1, 0.12 * irisR), aa));
        col = mix(col, float3(1.0), 0.9 * fillAA(sdStar4(lp - s2, 0.12 * irisR), aa));
    }
    // soft shadow hugging the top lid
    float topShade = 0.18 * (1.0 - smoothstep(-2.5 * aa, 0.0, dVis)) * smoothstep(0.0, 0.3 * ryo, lp.y);
    col = mix(col, u.colOutline.rgb, topShade);
    return blendOver(acc, col, cov);
}

// One brow: curved capsule in the outline colour (§3.2).
static float4 drawBrow(float4 acc, float2 f, float side, float clip, float aa, constant CharacterUniforms& u) {
    float sc = u.layoutD.w;
    float oy = u.layoutE.x;
    float raise = (side < 0.0) ? u.brows.x : u.brows.y;
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
    float xn = lp.x / w;
    float lift = smile * 0.6 * W * (xn * xn - 0.33);
    float y = lp.y - lift;
    float hEff = (y > 0.0) ? (0.70 * h) : h;
    float d = (length(float2(xn, y / hEff)) - 1.0) * min(w, hEff);
    float cov = fillAA(d, aa);
    float lineA = 0.35 * min(1.0, open * 8.0 + press);
    float hw = 0.006 * (1.0 + press);
    float lineCov = strokeAA(d, hw, aa) * lineA;
    if (cov <= 0.002 && lineCov <= 0.002) {
        return acc;
    }
    float3 col = u.colMouthInner.rgb;
    // teeth bands (clipped to the interior)
    float teethTop = 0.70 * h - 0.45 * h * upperTeeth;
    float upCov = fillAA(teethTop - y, aa) * step(0.001, upperTeeth);
    col = mix(col, u.colTeeth.rgb, upCov);
    float teethBot = -h + 0.35 * h * lowerTeeth;
    float lowCov = fillAA(y - teethBot, aa) * step(0.001, lowerTeeth);
    col = mix(col, u.colTeeth.rgb, lowCov);
    // tongue
    float2 tc = float2(0.0, -h * (1.0 - 0.45 * tongue));
    float2 tr = float2(0.55 * w, max(0.45 * h * tongue, 1e-4));
    float dt = sdEllipse(float2(lp.x, y), tc, tr);
    col = mix(col, u.colTongue.rgb, fillAA(dt, aa) * step(0.001, tongue));
    acc = blendOver(acc, col, cov * clip);
    acc = blendOver(acc, u.colOutline.rgb, lineCov * clip);
    return acc;
}

// Cheeks (§3.4): Gaussian blobs in the cheek colour.
static float4 drawCheeks(float4 acc, float2 f, float clip, constant CharacterUniforms& u) {
    float sc = u.layoutD.w;
    float oy = u.layoutE.x;
    float r = max(u.layoutD.z * sc, 1e-3);
    float blush = clamp(u.head.x, 0.0, 1.0);
    float2 cl = float2(-u.layoutD.x * sc, oy + u.layoutD.y * sc);
    float2 cr = float2(u.layoutD.x * sc, oy + u.layoutD.y * sc);
    float2 dl = (f - cl) / r;
    float2 dr = (f - cr) / r;
    float aL = clamp(0.22 + 0.6 * blush + 0.3 * clamp(u.eyesB.z, 0.0, 1.0), 0.0, 1.0) * exp(-2.0 * dot(dl, dl));
    float aR = clamp(0.22 + 0.6 * blush + 0.3 * clamp(u.eyesB.w, 0.0, 1.0), 0.0, 1.0) * exp(-2.0 * dot(dr, dr));
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

// Robe colour: accent, darker towards the bottom and the rim; the hood interior is darker still.
static float3 robeColor(float2 q, float dRobe, float interior, constant CharacterUniforms& u) {
    float t = clamp(q.y * 0.4 + 0.6, 0.0, 1.0);
    float3 col = mix(u.colAccent.rgb * 0.72, u.colAccent.rgb, t);
    float rim = clamp((dRobe + 0.10) / 0.10, 0.0, 1.0);
    col *= (1.0 - 0.35 * rim * rim);
    col = mix(col, col * 0.45, interior);
    return col;
}

// Hash-placed tiny twinkling stars (~one per 0.28 R cell) for the .starPattern feature.
static float starPattern(float2 q, float time, float aa) {
    float cs = 0.28;
    float2 cell = floor(q / cs);
    float h1 = hash21(cell);
    float h2 = hash21(cell + float2(17.3, 9.1));
    float h3 = hash21(cell + float2(3.7, 41.9));
    float2 cp = (cell + 0.5 + (float2(h1, h2) - 0.5) * 0.5) * cs;
    float sz = 0.022 + 0.02 * h3;
    float d = sdStar4(q - cp, sz);
    float tw = 0.65 + 0.35 * sin(time * 2.0 + h1 * kTwoPi);
    return fillAA(d, aa) * 0.7 * tw;
}

static float4 drawDarkFace(float4 acc, float2 q, float bodyCov, float aa, constant CharacterUniforms& u) {
    float d = sdEllipse(q, float2(0.0, -0.08), float2(0.72, 0.80));
    float3 col = u.colAccent.rgb;
    float vig = smoothstep(-0.45, 0.0, d);
    col = mix(col * 1.8, col, vig);
    return blendOver(acc, col, fillAA(d, aa) * bodyCov);
}

static float4 drawInnerFlame(float4 acc, float2 q, float wig, float3 col, float bodyCov, float aa) {
    float2 lq = (q - float2(0.0, -0.18)) / 0.58;
    float d = sdDrop(lq, 0.11 * sin(wig)) * 0.58;
    float cov = fillAA(d, aa + 0.03) * 0.85;
    return blendOver(acc, col, cov * bodyCov);
}

static float4 drawBrain(float4 acc, float2 q, float aa, constant CharacterUniforms& u) {
    float a = clamp(u.armsAccessory.z, 0.0, 1.0);
    float s = 0.30 * (1.0 + 0.08 * a);
    float2 lp = (q - float2(0.0, 0.62)) / s;
    float d = sdCircle(lp, float2(-0.45, 0.10), 0.52);
    d = smin(d, sdCircle(lp, float2(0.45, 0.10), 0.52), 0.15);
    d = smin(d, sdCircle(lp, float2(-0.20, 0.45), 0.45), 0.15);
    d = smin(d, sdCircle(lp, float2(0.20, 0.45), 0.45), 0.15);
    d = smin(d, sdCircle(lp, float2(-0.55, -0.30), 0.40), 0.15);
    d = smin(d, sdCircle(lp, float2(0.55, -0.30), 0.40), 0.15);
    float dl = d;
    d *= s;
    float aaL = aa / s;
    float3 col = u.colAccent.rgb;
    float shade = clamp(-lp.y * 0.5 + 0.3, 0.0, 1.0);
    col = mix(col, u.colAccent2.rgb, 0.4 * shade);
    float g0 = max(abs(lp.x) - 0.05, abs(lp.y - 0.1) - 0.75);
    float g1 = abs(length(lp - float2(-0.40, 0.05)) - 0.30) - 0.05;
    float g2 = abs(length(lp - float2(0.40, 0.05)) - 0.30) - 0.05;
    float g3 = abs(length(lp - float2(-0.15, -0.35)) - 0.22) - 0.05;
    float g4 = abs(length(lp - float2(0.25, 0.55)) - 0.20) - 0.05;
    float groove = min(min(g0, g1), min(g2, min(g3, g4)));
    float gCov = fillAA(groove, aaL) * (1.0 - smoothstep(-0.25, -0.05, dl));
    col = mix(col, u.colAccent2.rgb, gCov * 0.9);
    float rim = clamp((d + 0.04) / 0.04, 0.0, 1.0);
    col = mix(col, u.colAccent2.rgb * 0.8, 0.5 * rim * rim);
    float glow = a * 0.35 * exp(-max(d, 0.0) / 0.10);
    acc = blendOver(acc, u.colAccent2.rgb, glow);
    return blendOver(acc, col, fillAA(d, aa));
}

static float4 drawMoonMark(float4 acc, float2 q, float aa, constant CharacterUniforms& u) {
    float a = clamp(u.armsAccessory.z, 0.0, 1.0);
    float d = max(sdCircle(q, float2(0.0, 0.55), 0.17), -sdCircle(q, float2(0.08, 0.60), 0.14));
    float glow = (0.4 + 0.6 * a) * 0.6 * exp(-max(d, 0.0) / 0.10);
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
    float wob = 0.1396 * a * sin(time * 4.0);
    float2 l1 = rot(q - float2(-0.25, 1.05), 0.6109 - wob);
    float2 l2 = rot(q - float2(0.30, 1.08), -0.6981 - wob);
    float d1 = sdEllipse(l1, float2(0.0), float2(0.15, 0.07));
    float d2 = sdEllipse(l2, float2(0.0), float2(0.15, 0.07));
    float dl = min(d1, d2);
    float stem = sdCapsule(q, float2(0.0, 0.90), float2(0.02, 1.06), 0.025);
    float vein = min(abs(l1.y) - 0.008, abs(l2.y) - 0.008);
    float3 lcol = u.colAccent2.rgb;
    lcol = mix(lcol, lcol * 0.7, fillAA(vein, aa) * fillAA(dl + 0.02, aa));
    acc = blendOver(acc, u.colAccent2.rgb * 0.75, fillAA(stem, aa));
    acc = blendOver(acc, lcol, fillAA(dl, aa));
    return acc;
}

static float4 drawCloudCurl(float4 acc, float2 q, float aa, constant CharacterUniforms& u) {
    float b = clamp(u.armsAccessory.w, 0.0, 1.0);
    float2 c = float2(-0.45, 0.75 + 0.05 * b);
    float2 lp = q - c;
    float d = sdSpiral(lp, 0.06, 0.30 / (1.25 * kTwoPi), 1.25) - 0.07;
    float3 col = bodyGradient(q.y, u);
    col = mix(col, u.colHighlight.rgb, 0.3 * (1.0 - smoothstep(0.0, 0.3, length(lp - float2(-0.08, 0.10)))));
    float rim = clamp((d + 0.05) / 0.05, 0.0, 1.0);
    col = mix(col, u.colShadow.rgb, 0.3 * rim * rim);
    acc = blendOver(acc, u.colShadow.rgb, 0.2 * (1.0 - smoothstep(0.0, 0.08, d)) * step(0.0, d));
    return blendOver(acc, col, fillAA(d, aa));
}

static float4 drawBookAndWand(float4 acc, float2 q, float time, float aa, constant CharacterUniforms& u) {
    float a1 = clamp(u.armsAccessory.z, 0.0, 1.0);
    float a2 = clamp(u.armsAccessory.w, 0.0, 1.0);
    // Book: rounded rect 0.50 x 0.38, corner 0.06, at (-0.98, -0.45) rotated 15 degrees.
    float2 bc = float2(-0.98, -0.45);
    float2 lp = rot(q - bc, -0.2618);
    float dCover = sdRoundBox(lp, float2(0.0), float2(0.25, 0.19), 0.06);
    float starA = 0.5 + 0.5 * a1;
    acc = blendOver(acc, u.colGlow.rgb, 0.35 * starA * exp(-max(dCover, 0.0) / 0.12));
    float3 col = mix(u.colAccent2.rgb * 0.7, u.colAccent2.rgb, clamp(lp.y * 2.0 + 0.6, 0.0, 1.0));
    float dEdge = sdBox(lp, float2(0.225, 0.0), float2(0.03, 0.17));
    col = mix(col, u.colTeeth.rgb, fillAA(dEdge, aa));
    float dStar = sdStar4(lp - float2(-0.03, 0.02), 0.08);
    col = mix(col, u.colGlow.rgb, starA * 0.6 * exp(-max(dStar, 0.0) / 0.05));
    col = mix(col, mix(u.colGlow.rgb, float3(1.0), 0.5), starA * fillAA(dStar, aa));
    float rim = clamp((dCover + 0.04) / 0.04, 0.0, 1.0);
    col = mix(col, u.colOutline.rgb, 0.4 * rim * rim);
    acc = blendOver(acc, col, fillAA(dCover, aa));
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
    float tipR = 0.09 * (1.0 + 0.15 * sin(time * 6.0));
    float dTip = sdStar4(q - wb - float2(0.0, 0.06), tipR);
    float3 tipCol = mix(u.colGlow.rgb, float3(1.0), 0.5);
    acc = blendOver(acc, u.colGlow.rgb, (0.3 + 0.7 * a2) * 0.7 * exp(-max(dTip, 0.0) / 0.10));
    acc = blendOver(acc, tipCol, (0.6 + 0.4 * a2) * fillAA(dTip, aa));
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

static float4 drawDomeGlass(float4 acc, float2 p, float aa, constant CharacterUniforms& u) {
    float dG = min(sdCircle(p, float2(0.0, 0.10), 1.55), sdBox(p, float2(0.0, -0.60), float2(1.55, 0.70)));
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

static float4 drawEffects(float4 acc, float2 p, float2 q, float2 f, float time, float aa, constant CharacterUniforms& u) {
    float tears = clamp(u.fxA.x, 0.0, 1.0);
    float sweat = clamp(u.fxA.y, 0.0, 1.0);
    float hearts = clamp(u.fxA.z, 0.0, 1.0);
    float zzz = clamp(u.fxA.w, 0.0, 1.0);
    float question = clamp(u.fxB.x, 0.0, 1.0);
    float excl = clamp(u.fxB.y, 0.0, 1.0);
    float3 dropCol = float3(0.6, 0.8, 1.0);
    if (tears > 0.002) {
        float sc = u.layoutD.w;
        float oy = u.layoutE.x;
        float slide = 0.15 * fract(time * 0.8);
        float2 c1 = float2(-(u.layoutA.x + 0.05) * sc, oy + (u.layoutA.y - 0.35) * sc - slide);
        float2 c2 = float2((u.layoutA.x + 0.05) * sc, oy + (u.layoutA.y - 0.35) * sc - slide);
        float d = min(sdWaterDrop(f, c1, 0.07), sdWaterDrop(f, c2, 0.07));
        acc = blendOver(acc, dropCol, tears * fillAA(d, aa));
        float hl = min(length(f - c1 - float2(-0.02, 0.01)), length(f - c2 - float2(-0.02, 0.01))) - 0.018;
        acc = blendOver(acc, float3(1.0), tears * 0.8 * fillAA(hl, aa));
    }
    if (sweat > 0.002) {
        float2 c = float2(0.75, 0.55 - 0.10 * fract(time * 0.9));
        float d = sdWaterDrop(q, c, 0.07);
        acc = blendOver(acc, dropCol, sweat * fillAA(d, aa));
        acc = blendOver(acc, float3(1.0), sweat * 0.8 * fillAA(length(q - c - float2(-0.02, 0.01)) - 0.018, aa));
    }
    if (hearts > 0.002) {
        float3 hcol = float3(1.0, 0.42, 0.58);
        for (int i = 0; i < 3; i++) {
            float fi = float(i);
            float t = fract(time * 0.6 + fi * 0.333);
            float side = (i == 1) ? -1.0 : 1.0;
            float2 c = float2(side * (0.9 + 0.08 * sin(time * 3.0 + fi * 2.0)), 0.9 + 0.55 * t + 0.15 * fi);
            float s = 0.11 + 0.03 * fi;
            float d = sdHeart((p - c) / s) * s;
            float a = hearts * sin(kPi * t);
            acc = blendOver(acc, hcol, a * fillAA(d, aa));
            acc = blendOver(acc, float3(1.0), a * 0.7 * fillAA(length(p - c - float2(-0.30 * s, 0.75 * s)) - 0.12 * s, aa));
        }
    }
    if (zzz > 0.002) {
        float3 zcol = float3(0.90, 0.93, 1.0);
        for (int i = 0; i < 3; i++) {
            float fi = float(i);
            float t = fract(time * 0.45 + fi * 0.333);
            float2 c = float2(0.70 + 0.45 * t + 0.05 * sin(time * 2.0 + fi), 1.00 + 0.55 * t);
            float s = 0.05 + 0.05 * t;
            float2 lp = rot(p - c, -0.35);
            float top = sdRoundBox(lp, float2(0.0, s * 0.8), float2(s * 0.9, s * 0.18), s * 0.1);
            float bot = sdRoundBox(lp, float2(0.0, -s * 0.8), float2(s * 0.9, s * 0.18), s * 0.1);
            float2 dp = rot(lp, -0.73);
            float diag = sdRoundBox(dp, float2(0.0), float2(s * 1.2, s * 0.18), s * 0.1);
            float d = min(top, min(bot, diag));
            float a = zzz * sin(kPi * t);
            acc = blendOver(acc, zcol, a * fillAA(d, aa));
        }
    }
    float bob = 0.03 * sin(time * 3.0);
    float3 gcol = mix(u.colGlow.rgb, float3(1.0), 0.6);
    if (question > 0.002) {
        float2 c = float2(0.75, 1.35 + bob);
        float2 lp = (p - c) / 1.6;
        float2 rl = lp - float2(0.0, 0.14);
        float ring = abs(length(rl) - 0.10) - 0.03;
        float ang = atan2(rl.y, rl.x);
        if (ang < -1.5708) {
            ring = 1000.0;
        }
        float stem = sdCapsule(lp, float2(0.0, 0.04), float2(0.0, -0.06), 0.03);
        float dotD = sdCircle(lp, float2(0.0, -0.16), 0.038);
        float d = min(ring, min(stem, dotD)) * 1.6;
        acc = blendOver(acc, u.colGlow.rgb, question * 0.5 * exp(-max(d, 0.0) / 0.08));
        acc = blendOver(acc, gcol, question * fillAA(d, aa));
    }
    if (excl > 0.002) {
        float2 c = float2(0.75, 1.35 + bob);
        float2 lp = (p - c) / 1.6;
        float bar = sdUnevenCapsule(lp, float2(0.0, 0.20), float2(0.0, -0.04), 0.045, 0.03);
        float dotD = sdCircle(lp, float2(0.0, -0.15), 0.04);
        float d = min(bar, dotD) * 1.6;
        acc = blendOver(acc, u.colGlow.rgb, excl * 0.5 * exp(-max(d, 0.0) / 0.08));
        acc = blendOver(acc, gcol, excl * fillAA(d, aa));
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
    // Breathing is added on top of body.scale (§3.5).
    float2 anchor = floats ? float2(0.0, 0.0) : float2(0.0, -1.0);
    float breathe = u.bodyParams.y;
    float sx = max(u.transform.z - 0.015 * breathe, 0.05);
    float sy = max(u.transform.w + 0.025 * breathe, 0.05);
    float2 q = p - u.transform.xy;
    q = anchor + rot(q - anchor, u.bodyParams.x);
    q = anchor + (q - anchor) / float2(sx, sy);
    float aaB = aa / min(sx, sy);

    float flicker = hasFeature(features, kFeatFlicker) ? (0.012 * sin(time * (8.0 + 6.0 * u.idle.w) + q.y * 7.0)) : 0.0;
    float dBody = sdBody(q, shape, wig, flicker);

    // Outer glow (§3.5), then early-out far from the body (nothing but glow lives beyond 1.45 R).
    float4 acc = float4(0.0);
    if (dBody > 0.0) {
        float glowA = clamp(u.style.z * u.bodyParams.z * exp(-dBody / 0.35) * 0.7, 0.0, 1.0);
        acc = float4(u.colGlow.rgb * glowA, glowA);
    }
    if (dBody > 1.45 && !hasDome) {
        return acc;
    }

    // 1. Dome base behind everything.
    if (hasDome) {
        acc = drawDomeBase(acc, p, aa, u);
    }

    // 2. Robe back (.hood): the body shows only through the face opening.
    float opening = 1.0;
    float dRobe = 1000.0;
    float robeCov = 0.0;
    if (hasHood) {
        float peakX = 0.08 * sin(wig);
        dRobe = sdRobe(q, peakX);
        robeCov = fillAA(dRobe, aaB);
        float dOpen = sdEllipse(q, float2(0.0, 0.05), float2(0.80, 0.84));
        opening = fillAA(dOpen, aaB);
        acc = blendOver(acc, robeColor(q, dRobe, opening, u), robeCov);
        if (starPat) {
            acc = blendOver(acc, u.colAccent2.rgb, starPattern(q, time, aaB) * robeCov * (1.0 - opening));
        }
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
        acc = blendOver(acc, u.colAccent2.rgb, starPattern(q, time, aaB) * bodyCov);
    }
    if (darkFace) {
        acc = drawDarkFace(acc, q, bodyCov, aaB, u);
    }
    if (hasFeature(features, kFeatInnerFlame)) {
        // Lumie's accent is the wooden base, so dome designs use the highlight colour for the inner flame.
        float3 innerCol = hasDome ? u.colHighlight.rgb : u.colAccent.rgb;
        acc = drawInnerFlame(acc, q, wig, innerCol, bodyCov, aaB);
    }

    // 5. Robe front over the body (below y = -0.55, slightly curved collar).
    float front = 0.0;
    if (hasHood) {
        float collar = -0.55 + 0.05 * q.x * q.x;
        front = robeCov * (1.0 - smoothstep(collar - aaB, collar + aaB, q.y));
        acc = blendOver(acc, robeColor(q, dRobe, 0.0, u), front);
        if (starPat) {
            acc = blendOver(acc, u.colAccent2.rgb, starPattern(q, time, aaB) * front);
        }
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
        acc = drawCloudCurl(acc, q, aaB, u);
    }

    // 7. Face: invert the head transform (§2) — rotate by headTilt about (0, faceOffsetY), shift by turn/nod.
    float2 c0 = float2(0.0, u.layoutE.x);
    float2 f = q - float2(0.10 * u.head.z, 0.06 * u.head.w);
    f = c0 + rot(f - c0, u.head.y);
    float faceClip = fillAA(dBody + 0.01, aaB) * opening * (1.0 - front);
    acc = drawCheeks(acc, f, faceClip, u);
    acc = drawEye(acc, f, -1.0, u.eyesA.x, u.eyesB.z, faceClip, darkFace, sparkles, aaB, u);
    acc = drawEye(acc, f, 1.0, u.eyesA.y, u.eyesB.w, faceClip, darkFace, sparkles, aaB, u);
    acc = drawBrow(acc, f, -1.0, faceClip, aaB, u);
    acc = drawBrow(acc, f, 1.0, faceClip, aaB, u);
    acc = drawMouth(acc, f, faceClip, aaB, u);

    // 8. Hand-held props in front of the body.
    if (hasFeature(features, kFeatBookAndWand)) {
        acc = drawBookAndWand(acc, q, time, aaB, u);
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
    float alpha [[flat]];
};

vertex SparkleVaryings sparkleVertex(uint vid [[vertex_id]],
                                     uint iid [[instance_id]],
                                     constant CharacterUniforms& u [[buffer(0)]]) {
    SparkleVaryings out;
    float i = float(iid);
    float time = u.viewport.w;
    float seed = fract(sin(i * 12.9898) * 43758.5453);
    float seed2 = fract(seed * 7.1 + 0.37);
    bool burst = iid >= 40u;
    float T = burst ? 0.6 : (2.2 + 1.8 * seed2);
    float t = fract(time / T + seed);
    float dir = (seed2 > 0.5) ? 1.0 : -1.0;
    float ang = seed * 6.2831853 + time * 0.15 * dir;
    float rad = burst ? (0.3 + 1.4 * t) : (1.10 + 0.60 * fract(seed * 3.3));
    float2 pos = burst ? (float2(cos(ang), sin(ang)) * rad)
                       : float2(cos(ang) * rad, sin(ang) * rad * 0.6 + (t - 0.5) * 0.6);
    float env = sin(kPi * t);
    float size = 0.05 * (0.6 + fract(seed * 5.5)) * env;
    float rate = burst ? clamp(u.fxB.z, 0.0, 1.0) : clamp(u.fxB.w, 0.0, 1.0);
    float alpha = env * rate;
    uint features = uint(max(u.style.y, 0.0) + 0.5);
    if (hasFeature(features, kFeatDome)) {
        // Fireflies: confined to the jar; `accessory` boosts how many are lit.
        pos.x = clamp(pos.x, -1.30, 1.30);
        pos.y = clamp(pos.y * 1.3, -1.10, 1.35);
        float keep = step(fract(seed * 2.7), 0.55 + 0.45 * clamp(u.armsAccessory.z, 0.0, 1.0));
        alpha *= keep;
        size *= 0.8;
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
    float3 col = mix(u.colGlow.rgb, float3(1.0), 0.5);
    return float4(col * m, m);
}
"""#
}
