#version 450

layout(location = 0) in vec3 inCoord;
layout(location = 0) out vec3 outCoord;
layout(location = 1) out float vertexIndex;

void main() {
    outCoord = inCoord * 0.5 + 0.5;
    vertexIndex = gl_VertexIndex;
    gl_Position = vec4(inCoord, 1.0);
}
