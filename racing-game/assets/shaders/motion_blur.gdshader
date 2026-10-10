shader_type canvas_item;
render_mode blend_mix;

// Радиальное размытие экрана на высокой скорости (HUD включает его после 100 км/ч).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float amount : hint_range(0.0, 2.0) = 0.0;
uniform vec2 center = vec2(0.5, 0.5);
const int SAMPLES = 8;
uniform float vignette = 0.6;

void fragment() {
	vec2 uv = UV;
	vec2 direction = uv - center;
	vec4 color = texture(screen_tex, uv);

	if (amount > 0.001) {
		vec4 accum = color;
		float total = 1.0;
		for (int i = 1; i < SAMPLES; i++) {
			float t = float(i) / float(SAMPLES);
			accum += texture(screen_tex, uv - direction * amount * 0.14 * t);
			total += 1.0;
		}
		color = accum / total;
	}

	// Лёгкая виньетка усиливает ощущение скорости.
	float dist = length(direction);
	float dark = smoothstep(0.95, 0.3, dist);
	color.rgb *= mix(1.0, mix(1.0, dark, vignette), clamp(amount, 0.0, 1.0));
	COLOR = color;
}
