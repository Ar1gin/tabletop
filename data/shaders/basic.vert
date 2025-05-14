#version 450

layout(location = 0) in vec3 inCoord;
layout(location = 0) out float vertexIndex;
layout(location = 1) out float depth;

layout(set = 1, binding = 0) uniform Camera{
    mat4 transform;
} camera;
layout(set = 1, binding = 1) uniform Object{
    mat4 transform;
} object;


void main() {
    vertexIndex = gl_VertexIndex;
    vec4 outPos = vec4(inCoord, 1.0) * object.transform * camera.transform;
    depth = outPos.z / outPos.w;
    gl_Position = outPos;
}
