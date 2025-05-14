#version 450

layout(location = 0) in float vertexIndex;
layout(location = 1) in float depth;
layout(location = 0) out vec4 fragColor;

void main() {
    fragColor = vec4(
        depth,
        0.0,
        0.0,
        1.0
    );
}
