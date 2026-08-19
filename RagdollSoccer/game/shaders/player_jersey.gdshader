shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_schlick_ggx;

// Trikot-Stoff am Spielermodell: Muster + Farben aus der gemeinsamen
// Musterbibliothek, dazu feines Webmuster und angedeutete Saum-Naht, damit
// keine Flaeche komplett flach wirkt.
//
// Je hoeher die Seltenheitsstufe eines Musters (= je hoeher pattern_mode),
// desto seidiger/metallischer der Stoff und desto staerker das Eigenleuchten.
// Die Grenzen 16 (Episch) und 21 (Legendaer) folgen der Sortierung von
// JerseyData.Pattern.

#include "res://shaders/jersey_patterns.gdshaderinc"

uniform int pattern_mode = 0;
uniform vec4 color_a : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 color_b : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 color_c : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float weave_scale = 60.0;
uniform float weave_strength : hint_range(0.0, 0.4) = 0.1;
uniform float emission_strength : hint_range(0.0, 4.0) = 1.6;
// Ausschnitt des Musters, den dieses Körperteil zeigt. Muster mit einem
// einzelnen Blickfang (Sonnenscheibe, Galaxienkern) würden sonst auf jedem
// Arm und Bein noch einmal komplett auftauchen — player.gd schiebt Arme und
// Beine deshalb auf einen schmalen Randstreifen (siehe _apply_body_color).
uniform vec2 uv_offset = vec2(0.0, 0.0);
uniform vec2 uv_scale = vec2(1.0, 1.0);
// Heller/dunkler Stoff fuer dasselbe Muster. Damit setzen sich Hose und
// Stutzen als eigene Kleidungsstuecke vom Trikot ab, ohne dass das Muster
// eines Skins dafuer angetastet oder gar ersetzt wird — ein einfarbiger
// Spieler sah sonst aus wie in einem Ganzkoerperanzug.
uniform float garment_shade : hint_range(0.4, 1.4) = 1.0;

void fragment() {
	vec2 puv = uv_offset + UV * uv_scale;
	float emit = 0.0;
	vec3 pattern = jersey_pattern(pattern_mode, puv, color_a.rgb, color_b.rgb, color_c.rgb, TIME, emit);

	// Hochwertige Trikots sind glatter gewebt: dort das Garnkorn zuruecknehmen,
	// sonst wuerde es die feinen Effektmuster (Hologramm, Gitter ...) zermahlen.
	float weave_mix = pattern_mode >= 21 ? 0.35 : (pattern_mode >= 16 ? 0.6 : 1.0);
	vec2 weave_uv = UV * weave_scale;
	float weave = jhash11(floor(weave_uv)) * 0.5 + jhash11(floor(weave_uv) + vec2(0.5)) * 0.5;
	float ws = weave_strength * weave_mix;
	vec3 base = pattern * (1.0 - ws * 0.5 + weave * ws);

	// Leichte horizontale Saum-/Nahtlinien fuer mehr Stoff-Charakter.
	float seam = smoothstep(0.0, 0.02, abs(fract(UV.y * 3.0) - 0.5) - 0.47);
	base = mix(base, base * 0.72, seam * 0.5 * weave_mix);

	float rough = 0.75;
	float metal = 0.0;
	if (pattern_mode >= 21) {
		rough = 0.24;
		metal = 0.4;
	} else if (pattern_mode >= 16) {
		rough = 0.5;
		metal = 0.12;
	}

	ALBEDO = base * garment_shade;
	EMISSION = pattern * emit * emission_strength;
	ROUGHNESS = clamp(rough + weave * 0.15, 0.0, 1.0);
	METALLIC = metal;
}
