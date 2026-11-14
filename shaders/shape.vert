#version 450
// Instanced shapes pulled from a storage buffer: rectangles (optionally rounded,
// bordered or checker-patterned), line segments and points. Positions are
// physical pixels; canvas layers pass world coordinates and a transform.
struct Shape { vec4 geo; vec4 fill; vec4 stroke; vec4 p; };
layout(std430, set = 0, binding = 0) readonly buffer Shapes { Shape shapes[]; };
layout(set = 1, binding = 0) uniform View {
    vec4 viewport;   // xy: target size in pixels
    vec4 xf;         // x: scale, yz: offset (world to pixels), w: world size scale
    vec4 extra;      // x: minimum point diameter in pixels, y: pixel size scale
};
layout(location = 0) flat out vec4 v_geo;
layout(location = 1) flat out vec4 v_fill;
layout(location = 2) flat out vec4 v_stroke;
layout(location = 3) flat out vec4 v_p;

void main() {
    Shape s = shapes[gl_InstanceIndex];
    int kind = int(s.p.z);
    vec2 lo, hi;
    vec4 geo = s.geo;
    vec4 p = s.p;
    if (kind == 0) {
        lo = geo.xy;
        hi = geo.xy + geo.zw;
        if (p.x > 0.0 || fract(p.y) != 0.0) { lo -= 1.0; hi += 1.0; }
    } else if (kind == 1) {
        vec2 a = xf.x * geo.xy + xf.yz;
        vec2 b = xf.x * geo.zw + xf.yz;
        geo = vec4(a, b);
        float r = 0.5 * p.y * (p.w > 0.5 ? extra.y : 1.0) + 1.0;
        p.y *= (p.w > 0.5 ? extra.y : 1.0);
        lo = min(a, b) - r;
        hi = max(a, b) + r;
    } else {
        vec2 c = xf.x * geo.xy + xf.yz;
        float d = max(geo.z * (p.w > 0.5 ? xf.w : extra.y), extra.x);
        geo = vec4(c, 0.5 * d, 0.0);
        lo = c - 0.5 * d - 1.0;
        hi = c + 0.5 * d + 1.0;
    }
    int v = gl_VertexIndex;
    vec2 corner = vec2((v == 1 || v == 2 || v == 4) ? 1.0 : 0.0,
                       (v == 2 || v == 4 || v == 5) ? 1.0 : 0.0);
    vec2 pos = mix(lo, hi, corner);
    gl_Position = vec4(pos.x / viewport.x * 2.0 - 1.0, 1.0 - pos.y / viewport.y * 2.0, 0.0, 1.0);
    v_geo = geo;
    v_fill = s.fill;
    v_stroke = s.stroke;
    v_p = p;
}
