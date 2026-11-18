#version 460 core

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform float uEnergy;

out vec4 fragColor;

float hash21(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}

float plasmaField(vec2 p, float t, float e) {
  float a = atan(p.y, p.x);
  float r = length(p);
  float swirl1 = sin(p.x * 7.5 + cos(p.y * 6.5 - t * 1.4)) * cos(p.y * 7.0 + t * 1.1);
  float swirl2 = sin(r * 18.0 - t * (2.6 + e * 2.0) + sin(a * 4.0 + t * 0.9));
  float swirl3 = cos(a * 6.0 - r * 12.0 + t * 1.7) * 0.5;
  return clamp(0.5 + 0.28 * swirl1 + 0.22 * swirl2 + 0.14 * swirl3, 0.0, 1.0);
}

void main() {
  vec2 res = max(uSize, vec2(1.0));
  vec2 uv = (FlutterFragCoord().xy - 0.5 * res) / min(res.x, res.y);
  float r = length(uv);
  float angle = atan(uv.y, uv.x);
  float e = clamp(uEnergy, 0.0, 1.2);

  float pulse = 0.018 * e * sin(uTime * 4.2);

  // Outer volumetric aura
  float outerGlow = exp(-r * (4.4 - 1.2 * e)) * 0.72;

  // Inner reactor containment sphere
  float sphereR = 0.245 + pulse;
  float insideSphere = 1.0 - smoothstep(sphereR - 0.015, sphereR + 0.012, r);
  float plasma = plasmaField(uv * (1.0 + 0.15 * e), uTime, e);

  // Molten energy filaments stronger toward center and rim
  float fresnel = smoothstep(sphereR * 0.45, sphereR, r) * insideSphere;
  float singularity = exp(-pow(r / (0.068 + 0.025 * e + pulse * 0.4), 2.0));
  float iris = exp(-pow((r - 0.105) / 0.018, 2.0)) * (0.55 + 0.45 * sin(angle * 8.0 + uTime * 2.4));

  // Crisp containment rim
  float containmentRim = exp(-pow((r - sphereR) / 0.008, 2.0));

  // Subtle rotating radar sweep outside sphere
  float sweepAngle = fract((angle - uTime * (1.3 + e * 0.8)) / 6.2831853);
  float sweepFade = pow(sweepAngle, 6.0) * smoothstep(0.18, 0.26, r) * (1.0 - smoothstep(0.36, 0.47, r));

  // Deep obsidian void + crimson reactor palette
  vec3 obsidian = vec3(0.05, 0.005, 0.012);
  vec3 deepCrimson = vec3(0.42, 0.01, 0.04);
  vec3 vividCrimson = vec3(0.92, 0.04, 0.09);
  vec3 hotEmber = vec3(1.00, 0.42, 0.36);
  vec3 coreWhite = vec3(1.00, 0.90, 0.88);

  vec3 sphereCol = mix(obsidian, deepCrimson, plasma * 0.75)
                 + vividCrimson * (fresnel * 0.85 + pow(plasma, 2.4) * 0.55) * insideSphere;

  vec3 color = deepCrimson * outerGlow
             + sphereCol
             + vividCrimson * (containmentRim * (0.75 + 0.45 * e) + iris * 0.5 + sweepFade * 0.35)
             + hotEmber * singularity * (0.85 + 0.4 * e)
             + coreWhite * exp(-pow(r / 0.028, 2.0)) * (0.7 + 0.3 * e);

  float edgeFade = 1.0 - smoothstep(0.41, 0.495, r);
  float alpha = clamp((outerGlow * 0.8 + insideSphere * 0.96 + containmentRim + sweepFade * 0.5 + singularity) * edgeFade, 0.0, 1.0);

  fragColor = vec4(color * alpha, alpha);
}
