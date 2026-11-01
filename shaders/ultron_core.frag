#include <flutter/runtime_effect.glsl>
precision highp float;
uniform vec2 uSize; uniform float uTime; uniform vec4 uTint; out vec4 fragColor;
void main(){ vec2 p=(FlutterFragCoord().xy-0.5*uSize)/min(uSize.x,uSize.y); float r=length(p); float a=atan(p.y,p.x); float r1=0.22+0.012*sin(a*5.0+uTime*0.7); float r2=0.34+0.009*cos(a*7.0-uTime*0.5); float g1=exp(-abs(r-r1)*180.0); float g2=exp(-abs(r-r2)*150.0); float g3=exp(-abs(r-0.46)*130.0); float core=exp(-r*r*150.0)*(0.75+0.25*sin(uTime*2.0)); float glow=exp(-r*5.5)*0.12; vec3 c=uTint.rgb*(g1*0.65+g2*0.48+g3*0.25+core+glow); fragColor=vec4(c,clamp(g1+g2+g3+core+glow,0.0,1.0)); }
