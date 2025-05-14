#version 450

layout(location = 0) in float vertexIndex;
layout(location = 1) in float depth;
layout(location = 0) out vec4 fragColor;

void main() {
    fragColor = vec4(
        depth,
        cos(vertexIndex * 0.5) * 0.25 + 0.75,
        sin(vertexIndex * 0.5) * 0.25 + 0.75,
        1.0
    );
}
