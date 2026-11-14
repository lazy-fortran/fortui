#version 450
// Glyph and image quads: pixel positions, texture coordinates, colour.
layout(location = 0) in vec2 pos;
layout(location = 1) in vec2 uv;
layout(location = 2) in vec4 color;
layout(set = 1, binding = 0) uniform View { vec4 viewport; vec4 xf; vec4 extra; };
layout(location = 0) out vec2 v_uv;
layout(location = 1) out vec4 v_color;
void main() {
    gl_Position = vec4(pos.x / viewport.x * 2.0 - 1.0, 1.0 - pos.y / viewport.y * 2.0, 0.0, 1.0);
    v_uv = uv;
    v_color = color;
}
