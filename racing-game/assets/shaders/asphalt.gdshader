shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Трипланарный асфальт + разметка.
// UV.x — поперёк дороги (0 = левый край, 1 = правый),
// UV.y — вдоль дороги (единица = 4 метра, см. TrackBuilder).

uniform vec4 asphalt_color : source_color = vec4(0.13, 0.13, 0.15, 1.0);
uniform vec4 marking_color : source_color = vec4(0.92, 0.92, 0.88, 1.0);
uniform float roughness_value : hint_range(0.0, 1.0) = 0.8;
uniform float noise_scale = 1.4;
uniform float grain_amount : hint_range(0.0, 1.0) = 0.45;
uniform float line_width : hint_range(0.0, 0.2) = 0.05;
uniform float center_line_width : hint_range(0.0, 0.2) = 0.03;
uniform float marking_repeat = 0.35;
uniform float wear_amount : hint_range(0.0, 1.0) = 0.25;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(cell);
	float b = hash21(cell + vec2(1.0, 0.0));
	float c = hash21(cell + vec2(0.0, 1.0));
	float d = hash21(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		value += amplitude * value_noise(p);
		p *= 2.03;
		amplitude *= 0.5;
	}
	return value;
}

// Трипланар: смешиваем три проекции шума по мировой нормали.
float triplanar(vec3 world_pos, vec3 world_normal) {
	vec3 blend = pow(abs(world_normal), vec3(4.0));
	blend /= max(blend.x + blend.y + blend.z, 0.0001);
	float px = fbm(world_pos.yz * noise_scale);
	float py = fbm(world_pos.xz * noise_scale);
	float pz = fbm(world_pos.xy * noise_scale);
	return px * blend.x + py * blend.y + pz * blend.z;
}

void fragment() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);

	float grain = triplanar(world_pos, world_normal);
	float patches = fbm(world_pos.xz * 0.15);
	vec3 base = asphalt_color.rgb * (1.0 - grain_amount * 0.45 + grain * grain_amount);
	// Потёртости в колее.
	base = mix(base, base * 1.25, patches * wear_amount);

	float u = UV.x;
	float v = UV.y;
	// Краевые линии и прерывистая осевая.
	float edge_left = 1.0 - smoothstep(line_width * 0.55, line_width, u);
	float edge_right = smoothstep(1.0 - line_width, 1.0 - line_width * 0.55, u);
	float dash = step(0.5, fract(v * marking_repeat));
	float center = (1.0 - smoothstep(center_line_width * 0.5, center_line_width, abs(u - 0.5))) * dash;
	float marking = clamp(edge_left + edge_right + center, 0.0, 1.0);

	ALBEDO = mix(base, marking_color.rgb, marking);
	ROUGHNESS = clamp(roughness_value - marking * 0.35, 0.05, 1.0);
	METALLIC = 0.0;
	SPECULAR = 0.4;
}
