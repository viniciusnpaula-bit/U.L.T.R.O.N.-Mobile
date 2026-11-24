#version 460 core

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform float uEnergy;

out vec4 fragColor;

void main() {
  vec2 res = max(uSize, vec2(1.0));
  vec2 uv = (FlutterFragCoord().xy - 0.5 * res) / min(res.x, res.y);
  float r = length(uv);
  float e = clamp(uEnergy, 0.0, 1.2);

  float breathe = 0.012 * (0.35 + e) * sin(uTime * 2.6);

  // Luminous soft white-rose inner singularity (matches reference geodesic core)
  float coreWhite = exp(-pow(r / (0.045 + 0.014 * e + breathe), 2.0));
  float innerMist = exp(-pow(r / (0.145 + 0.025 * e + breathe), 2.0));
  float outerHalo = exp(-pow(r / (0.31 + 0.03 * e), 2.0));

  // Subtle holographic horizontal scanlines inside the geodesic disk
  float diskMask = 1.0 - smoothstep(0.24, 0.34, r);
  float scan = 0.88 + 0.12 * sin(FlutterFragCoord().y * 2.4 - uTime * 1.2);
  float scanDisk = diskMask * (0.10 + 0.04 * e) * scan;

  vec3 deepCrimson = vec3(0.32, 0.03, 0.07);
  vec3 roseCrimson = vec3(0.86, 0.24, 0.34);
  vec3 softPink = vec3(1.00, 0.72, 0.76);
  vec3 pureCore = vec3(1.00, 0.94, 0.95);

  vec3 color = deepCrimson * (outerHalo * 0.65 + scanDisk)
             + roseCrimson * innerMist * (0.62 + 0.28 * e)
             + softPink * pow(innerMist, 2.2) * (0.45 + 0.25 * e)
             + pureCore * coreWhite * (0.85 + 0.25 * e);

  float edgeFade = 1.0 - smoothstep(0.38, 0.495, r);
  float alpha = clamp((outerHalo * 0.55 + innerMist * 0.78 + coreWhite * 0.92 + scanDisk) * edgeFade, 0.0, 1.0);

  fragColor = vec4(color * alpha, alpha);
}
