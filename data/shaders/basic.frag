#version 450

layout(location = 0) in vec3 fragCoord;
layout(location = 1) in float vertexIndex;
layout(location = 0) out vec4 fragColor;

void main() {
    fragColor = vec4(fragCoord.z, vertexIndex * 0.1, 0.0, 1.0);
}
