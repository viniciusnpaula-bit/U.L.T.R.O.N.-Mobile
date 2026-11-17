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
  float angle = atan(uv.y, uv.x);

  float pulse = 0.08 * uEnergy * sin(uTime * 4.0);
  float wave = 0.025 * (0.4 + uEnergy) * sin(angle * 3.0 + uTime * 2.2)
             + 0.015 * cos(angle * 5.0 - uTime * 1.6);

  // Inner molten crimson core
  float coreMask = 1.0 - smoothstep(0.06 + pulse * 0.25, 0.22 + pulse * 0.4, r);
  float halo = exp(-r * (4.8 - 1.4 * clamp(uEnergy, 0.0, 1.0)));

  // Three concentric resonant rings
  float ring1 = exp(-pow((r - (0.21 + wave + pulse * 0.35)) / 0.014, 2.0));
  float ring2 = exp(-pow((r - (0.33 - wave * 0.7)) / 0.012, 2.0));
  float ring3 = exp(-pow((r - (0.44 + wave * 0.5)) / 0.010, 2.0));

  vec3 deepRed = vec3(0.45, 0.01, 0.04);
  vec3 crimson = vec3(0.90, 0.04, 0.08);
  vec3 ember = vec3(1.00, 0.32, 0.36);

  vec3 color = deepRed * halo * 0.75
             + crimson * (ring1 * 0.95 + ring2 * 0.75 + ring3 * 0.55)
             + ember * coreMask * (0.85 + 0.35 * uEnergy);

  float edgeFade = 1.0 - smoothstep(0.42, 0.50, r);
  float alpha = clamp((halo * 0.70 + coreMask + ring1 + ring2 * 0.85 + ring3 * 0.65) * edgeFade, 0.0, 1.0);

  fragColor = vec4(color * alpha, alpha);
}
