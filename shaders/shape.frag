#version 450
layout(location = 0) flat in vec4 v_geo;
layout(location = 1) flat in vec4 v_fill;
layout(location = 2) flat in vec4 v_stroke;
layout(location = 3) flat in vec4 v_p;
layout(location = 0) out vec4 o;

float round_box(vec2 q, vec2 half_size, float r) {
    vec2 d = abs(q) - half_size + r;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
}

vec4 premul(vec4 c, float coverage) { return vec4(c.rgb * c.a, c.a) * coverage; }

void main() {
    vec2 px = gl_FragCoord.xy;
    int kind = int(v_p.z);
    if (kind == 0) {
        if (v_p.w > 0.5) {
            ivec2 ip = ivec2(floor(px));
            o = ((ip.x + ip.y) & 1) == 0 ? premul(v_fill, 1.0) : premul(v_stroke, 1.0);
            return;
        }
        float r = v_p.x, bw = v_p.y;
        if (r <= 0.0 && bw <= 0.0) { o = premul(v_fill, 1.0); return; }
        vec2 half_size = 0.5 * v_geo.zw;
        float d = round_box(px - (v_geo.xy + half_size), half_size, min(r, min(half_size.x, half_size.y)));
        float outer = clamp(0.5 - d, 0.0, 1.0);
        float inner = bw > 0.0 ? clamp(0.5 - (d + bw), 0.0, 1.0) : outer;
        o = premul(v_fill, inner) + premul(v_stroke, outer - inner);
    } else if (kind == 1) {
        vec2 a = v_geo.xy, b = v_geo.zw, ab = b - a;
        float t = clamp(dot(px - a, ab) / max(dot(ab, ab), 1e-6), 0.0, 1.0);
        float d = length(px - a - t * ab) - 0.5 * v_p.y;
        o = premul(mix(v_fill, v_stroke, t), clamp(0.5 - d, 0.0, 1.0));
    } else {
        float d = length(px - v_geo.xy) - v_geo.z;
        o = premul(v_fill, clamp(0.5 - d, 0.0, 1.0));
    }
}
