#version 450 core
out vec4 frag_color;

in vec2 tex_coord;
in flat int face_idx;
in vec3 world_pos;

uniform bool is_ramp;
uniform bool is_ladder;

uniform bool use_face_tex_scaling;
uniform float world_uv_scale;
uniform vec3 face_scale;

uniform vec4 color;
uniform vec4 emissive;
uniform float alpha_test;

uniform mat3 tex_transform;
uniform sampler2D tex;
uniform vec3 uAmbientColor;
uniform float uAmbientIntensity;
uniform vec3 uLightColor;
uniform float uLightIntensity;
uniform vec3 uLightDir;
uniform vec3 uFogColor;
uniform float uFogNear;
uniform float uFogFar;
uniform vec3 uCameraPosition;

void main() {
    vec2 scaled_tex_coord;

    if (use_face_tex_scaling) {
        vec2 scale;

        if (is_ramp) {
            switch (face_idx) {
                case 0:
                    scale = vec2(face_scale.x, sqrt(face_scale.z*face_scale.z + face_scale.y*face_scale.y));
                    break;
                case 1:
                    scale = face_scale.xz;
                    break;
                case 2:
                    scale = face_scale.zy;
                    break;
                case 3:
                    scale = face_scale.xy;
                    break;
            }
        } else if (is_ladder) {
            if (face_idx < 2) scale = face_scale.xy;
            else if (face_idx < 4) scale = face_scale.zy;
            else if (face_idx < 6) scale = face_scale.xz;
            else if (face_idx < 8) scale = face_scale.xy;
            else if (face_idx < 10) scale = face_scale.zy;
            else scale = face_scale.xz;
        } else {
            if (face_idx < 2) scale = face_scale.xy;
            else if (face_idx < 4) scale = face_scale.zy;
            else scale = face_scale.xz;
        }

        scaled_tex_coord = (1.0f / world_uv_scale) * scale * tex_coord;
        scaled_tex_coord.x = 0.5f + scaled_tex_coord.x - scale.x * 0.5f;
    } else {
        scaled_tex_coord = tex_coord;
    }

    vec3 t_tex_coord = tex_transform * vec3(scaled_tex_coord, 1.0f);
    frag_color = texture(tex, t_tex_coord.xy) * mix(color, emissive, 0.0f);
    // Cutout foliage stays in the opaque pass, with holes in color and depth.
    if (frag_color.a < alpha_test) discard;

    vec3 normal = normalize(cross(dFdx(world_pos), dFdy(world_pos)));
    float light_length = length(uLightDir);
    vec3 light_direction = light_length > 0.0001 ? uLightDir / light_length : vec3(0.0, 1.0, 0.0);
    float diffuse = max(dot(normal, light_direction), 0.0);
    vec3 lighting = uAmbientColor * uAmbientIntensity + uLightColor * (uLightIntensity * diffuse);
    // Three.js applies color management/tone mapping after accumulating light.
    // Keep the native path from saturating every textured face when the live
    // map's ambient and directional intensities sum above one.
    float peak_light = max(max(lighting.r, lighting.g), max(lighting.b, 1.0));
    lighting /= peak_light;
    // The map loader uses white as the neutral/default emissive value. Keep
    // that default neutral; explicit emissive materials need a separate
    // strength flag before they can be added without brightening every mesh.
    vec3 lit_rgb = frag_color.rgb * lighting;
    float fog_span = max(0.001, uFogFar - uFogNear);
    float fog_amount = clamp((length(world_pos - uCameraPosition) - uFogNear) / fog_span, 0.0, 1.0);
    frag_color = vec4(mix(lit_rgb, uFogColor, fog_amount), frag_color.a);
}
