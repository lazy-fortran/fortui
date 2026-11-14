#version 450
layout(set = 2, binding = 0) uniform sampler2D tex;
layout(location = 0) in vec2 v_uv;
layout(location = 1) in vec4 v_color;
layout(location = 0) out vec4 o;
void main() {
    vec4 c = v_color * texture(tex, v_uv);
    o = vec4(c.rgb * c.a, c.a);
}
