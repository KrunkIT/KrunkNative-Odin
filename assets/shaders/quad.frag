#version 450 core
out vec4 frag_color;
in vec2 tex_coord;

uniform vec4 color;

uniform float aspect;
uniform float border_bottom_left_radius;
uniform float border_bottom_right_radius;
uniform float border_top_left_radius;
uniform float border_top_right_radius;

uniform float r_clip;
uniform float stroke_width;

uniform float tex_viewport[4];
uniform sampler2D tex;

void main() {
    vec2 scaled_size;
    vec2 scaled_tex_coord;

    if (aspect > 1.0f) {
        scaled_tex_coord = vec2(tex_coord.x * aspect, tex_coord.y);
        scaled_size = vec2(aspect, 1.0f);
    } else {
        scaled_tex_coord = vec2(tex_coord.x, tex_coord.y / aspect);
        scaled_size = vec2(1.0f, 1.0f / aspect);
    }

    bool is_corner = true;
    float max_radius;
    float radius;

    const float bottom_left_r = clamp(border_bottom_left_radius, 0.0f, 0.5f);
    const float bottom_right_r = clamp(border_bottom_right_radius, 0.0f, 0.5f);
    const float top_left_r = clamp(border_top_left_radius, 0.0f, 0.5f);
    const float top_right_r = clamp(border_top_right_radius, 0.0f, 0.5f);

    if (scaled_tex_coord.x < bottom_left_r && scaled_tex_coord.y < bottom_left_r) {
        max_radius = bottom_left_r;
        radius = sqrt(pow(bottom_left_r - scaled_tex_coord.x, 2.0f) + pow(bottom_left_r - scaled_tex_coord.y, 2.0f));
    } else if ((scaled_size.x - scaled_tex_coord.x) < bottom_right_r && scaled_tex_coord.y < bottom_right_r) {
        max_radius = bottom_right_r;
        radius = sqrt(pow(bottom_right_r - (scaled_size.x - scaled_tex_coord.x), 2.0f) + pow(bottom_right_r - scaled_tex_coord.y, 2.0f));
    } else if (scaled_tex_coord.x < top_left_r && (scaled_size.y - scaled_tex_coord.y) < top_left_r) {
        max_radius = top_left_r;
        radius = sqrt(pow(top_left_r - scaled_tex_coord.x, 2.0f) + pow(top_left_r - (scaled_size.y - scaled_tex_coord.y), 2.0f));
    } else if ((scaled_size.x - scaled_tex_coord.x) < top_right_r && (scaled_size.y - scaled_tex_coord.y) < top_right_r) {
        max_radius = top_right_r;
        radius = sqrt(pow(top_right_r - (scaled_size.x - scaled_tex_coord.x), 2.0f) + pow(top_right_r - (scaled_size.y - scaled_tex_coord.y), 2.0f));
    } else {
        is_corner = false;
    }

    float coverage = 1.0;
    if (stroke_width > 0.0) {
        // A rounded outline with a transparent interior, in the same units
        // as the corner radii. Derivatives keep thin HUD borders smooth.
        float r = bottom_left_r;
        vec2 q = abs(scaled_tex_coord - scaled_size * 0.5) - scaled_size * 0.5 + r;
        float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
        float aa = max(fwidth(d), 0.0001);
        coverage = (1.0 - smoothstep(-aa, 0.0, d)) * smoothstep(-stroke_width - aa, -stroke_width, d);
        if (coverage <= 0.0) discard;
    } else if (is_corner && radius > max_radius) discard;
    if (tex_coord.x > 1.0f - r_clip) discard;

    frag_color = texture(tex, vec2(
        tex_coord.x * tex_viewport[2] - tex_viewport[0],
        tex_coord.y * tex_viewport[3] - tex_viewport[1]
    )) * color;
    frag_color.a *= coverage;
}
