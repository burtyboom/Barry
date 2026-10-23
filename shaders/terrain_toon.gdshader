shader_type spatial;
// Cartoon terrain: smooth soft-wrapped lighting over painted vertex colours.
// On top of the vertex colours we paint small-scale sand detail in world space:
//   UV.x = grain amount (0 = bush / rock, 1 = loose sand)
//   UV.y = ripple amount (wind ripples on soft dry sand only)
//   UV2.x = grass amount (bush floor: patches, dry spots, leaf litter)
// Detail fades out with distance (via fwidth) so it never shimmers.
render_mode diffuse_lambert_wrap, specular_disabled;

varying vec3 wpos;


vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

// integer hash -> 0..1, stable at large world coordinates
float hash2(vec2 p) {
	uvec2 v = uvec2(ivec2(floor(p)) + ivec2(100000));
	v = v * 1664525u + 1013904223u;
	v.x += v.y * 1664525u;
	v.y += v.x * 1664525u;
	v ^= v >> 16u;
	v.x += v.y * 1664525u;
	v.y += v.x * 1664525u;
	v ^= v >> 16u;
	return float(v.x ^ v.y) / 4294967295.0;
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash2(i);
	float b = hash2(i + vec2(1.0, 0.0));
	float c = hash2(i + vec2(0.0, 1.0));
	float d = hash2(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// fades a pattern of size `cell` out once a pixel covers more than ~half a cell
float detail_fade(float px, float cell) {
	return 1.0 - smoothstep(cell * 0.35, cell * 0.9, px);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 col = COLOR.rgb;
	vec2 p = wpos.xz;
	float px = length(fwidth(p));
	float grain = UV.x;
	float ripple = UV.y;
	float grassy = UV2.x;

	// broad mottling: breaks up the smooth vertex-colour gradients everywhere
	float m = vnoise(p * 0.35) * 0.6 + vnoise(p * 1.3) * 0.4;
	col *= 0.95 + m * 0.09;

	if (grain > 0.001) {
		// fine grains (2 cm, hard) over soft clumps (~12 cm, smooth)
		float g1 = vnoise(p / 0.025) - 0.5;
		float g2 = vnoise(p / 0.12 + 31.7) - 0.5;
		float k = 0.0;
		k += g1 * 0.07 * detail_fade(px, 0.02);
		k += g2 * 0.10 * detail_fade(px, 0.12);
		// round dark mineral specks (rutile / ilmenite) in the white sand
		vec2 sc = p / 0.07;
		vec2 cell = floor(sc);
		vec2 ctr = cell + 0.25 + 0.5 * vec2(hash2(cell + 3.1), hash2(cell + 9.7));
		float rad = 0.10 + 0.12 * hash2(cell + 5.5);
		float dotm = 1.0 - smoothstep(rad - 0.08, rad + 0.08, length(sc - ctr));
		k -= dotm * step(0.88, hash2(cell + 17.0)) * 0.28 * detail_fade(px, 0.03);
		col *= 1.0 + k * grain;
	}

	if (ripple > 0.001) {
		// wind ripples ~45 cm apart, wandering direction, sharp crest / soft trough
		float a = 0.9 + (vnoise(p * 0.05) - 0.5) * 1.2;
		vec2 dir = vec2(cos(a), sin(a));
		float ph = dot(p, dir) / 0.45 + vnoise(p * 0.6) * 2.5;
		float w = fract(ph);
		float crest = smoothstep(0.0, 0.75, w) * (1.0 - smoothstep(0.75, 1.0, w));
		// break the lines up so they don't look like a grid
		float breakup = smoothstep(0.25, 0.6, vnoise(p * 0.9 + 13.0));
		float r = (crest - 0.5) * 0.10 * breakup * detail_fade(px, 0.45);
		col *= 1.0 + r * ripple;
	}

	if (grassy > 0.001) {
		vec3 g = col;
		// cartoon patches: hard-edged lighter and darker blobs
		float pat = vnoise(p * 0.07) * 0.65 + vnoise(p * 0.23 + 5.0) * 0.35;
		g *= 1.0 + 0.16 * smoothstep(0.58, 0.62, pat);
		g *= 1.0 - 0.18 * (1.0 - smoothstep(0.36, 0.40, pat));
		// sun-dried yellow spots
		float dry = smoothstep(0.66, 0.70, vnoise(p * 0.045 + 50.0) * 0.8 + vnoise(p * 0.4) * 0.2);
		g = mix(g, g * vec3(1.35, 1.15, 0.62), dry * 0.55);
		// fine blade speckle
		g *= 1.0 + (vnoise(p / 0.06) - 0.5) * 0.16 * detail_fade(px, 0.06);
		g *= 1.0 + (vnoise(p / 0.25) - 0.5) * 0.12 * detail_fade(px, 0.25);
		// leaf litter: little brown and olive dots
		vec2 lc = p / 0.45;
		vec2 cell = floor(lc);
		vec2 ctr = cell + 0.25 + 0.5 * vec2(hash2(cell + 41.0), hash2(cell + 77.0));
		float leaf = 1.0 - smoothstep(0.09, 0.15, length((lc - ctr) * vec2(1.0, 1.7)));
		float lh = hash2(cell + 23.0);
		vec3 leaf_col = lh > 0.5 ? vec3(0.55, 0.40, 0.22) : vec3(0.48, 0.50, 0.25);
		g = mix(g, leaf_col, leaf * step(0.82, lh * 0.5 + hash2(cell + 61.0) * 0.5) * detail_fade(px, 0.08));
		col = mix(col, g, grassy);
	}

	ALBEDO = srgb_to_linear(col);
	ROUGHNESS = 1.0;
}
