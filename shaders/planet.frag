#version 460 core

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uZoom;
uniform float uYaw;
uniform float uPitch;

uniform sampler2D uEquirect;

out vec4 fragColor;

// Same map as planetDirection in lib/services/little_planet.dart.
void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 ndc = (frag / uSize) * 2.0 - vec2(1.0);
  float nx = ndc.x * (uSize.x / uSize.y);
  float ny = -ndc.y;
  float rho = length(vec2(nx, ny)) / max(uZoom, 0.05);
  float theta = 2.0 * atan(rho);
  float azimuth = atan(ny, nx);
  float viewX = sin(theta) * cos(azimuth);
  float viewY = sin(theta) * sin(azimuth);
  float viewZ = cos(theta);
  float cosPitch = cos(uPitch);
  float sinPitch = sin(uPitch);
  float pitchedY = viewY * cosPitch + viewZ * sinPitch;
  float pitchedZ = -viewY * sinPitch + viewZ * cosPitch;
  float cosYaw = cos(uYaw);
  float sinYaw = sin(uYaw);
  float worldX = viewX * cosYaw + pitchedZ * sinYaw;
  float worldY = pitchedY;
  float worldZ = -viewX * sinYaw + pitchedZ * cosYaw;
  float longitude = atan(worldX, worldZ);
  float latitude = asin(clamp(worldY, -1.0, 1.0));
  float u = longitude / (2.0 * 3.14159265) + 0.5;
  float v = 0.5 - latitude / 3.14159265;
  fragColor = texture(uEquirect, vec2(u, v));
}
