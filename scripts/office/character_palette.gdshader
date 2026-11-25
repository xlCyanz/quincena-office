// Paleta de un aspecto de personaje: cambia cada color exacto de from_colors por el de to_colors.
// Las tablas salen de data/sprites.json (characters.palettes); el tope de 48 es PALETTE_MAX de export_game.py.
shader_type canvas_item;

uniform int color_count = 0;
uniform vec3 from_colors[48];
uniform vec3 to_colors[48];

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec4 texel = texture(TEXTURE, UV);
	vec3 rgb = texel.rgb;
	for (int i = 0; i < color_count; i++) {
		// Medio paso de 8 bits de margen: la hoja es sin pérdida y se muestrea sin suavizar.
		if (all(lessThan(abs(texel.rgb - from_colors[i]), vec3(0.5 / 255.0)))) {
			rgb = to_colors[i];
			break;
		}
	}
	COLOR = vec4(rgb, texel.a) * tint;
}
