#version 450

layout(location = 0) in vec3 inCoord;
layout(location = 1) in vec2 inUV;
layout(location = 0) out vec2 outUV;

layout(set = 1, binding = 0) uniform Camera{
    mat4 transform;
} camera;
layout(set = 1, binding = 1) uniform Object{
    mat4 transform;
} object;

void main() {
    gl_Position = vec4(inCoord, 1.0) * object.transform * camera.transform;
    gl_ClipDistance[0] = gl_Position.z;
    outUV = inUV;
}
