class_name JerseyData
extends RefCounted

## Trikot-Muster-Modi, müssen mit player_jersey.gdshader übereinstimmen.
enum Pattern {
	SOLID,
	STRIPES_H,
	STRIPES_V,
	HALF_SPLIT,
	COLOR_BLOCK,
	HOOPS_TRICOLOR,
	SASH,
	CHECKERBOARD,
	PINSTRIPE,
	GRADIENT_V,
	GRADIENT_RADIAL,
	GRADIENT_DIAGONAL,
	GRADIENT_DUAL,
	RAINBOW,
	HOLOGRAPHIC,
	CAMO,
	FLAME,
}

enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

const RARITY_NAMES := {
	Rarity.COMMON: "Gewöhnlich",
	Rarity.UNCOMMON: "Ungewöhnlich",
	Rarity.RARE: "Selten",
	Rarity.EPIC: "Episch",
	Rarity.LEGENDARY: "Legendär",
}

## Gesamt-Drop-Chance pro Stufe in %, wird beim Öffnen gleichmäßig auf die
## Trikots dieser Stufe aufgeteilt.
const RARITY_WEIGHT := {
	Rarity.COMMON: 40.0,
	Rarity.UNCOMMON: 28.0,
	Rarity.RARE: 18.0,
	Rarity.EPIC: 10.0,
	Rarity.LEGENDARY: 4.0,
}

const RARITY_COLOR := {
	Rarity.COMMON: Color(0.7, 0.72, 0.75),
	Rarity.UNCOMMON: Color(0.35, 0.8, 0.4),
	Rarity.RARE: Color(0.3, 0.55, 0.95),
	Rarity.EPIC: Color(0.65, 0.35, 0.9),
	Rarity.LEGENDARY: Color(0.95, 0.65, 0.15),
}

## id 0 = Standard-Trikot: immer im Besitz, feste Team-Farbe (nicht in Kisten).
## Alle anderen 20 Trikots sind team-unabhängige Skins, die per Kiste erlost werden.
const JERSEYS := [
	{"id": 0, "name": "Standard", "rarity": Rarity.COMMON, "pattern": Pattern.SOLID, "loot": false},

	# --- Gewöhnlich (einfarbig) ---
	{"id": 1, "name": "Kreide-Weiß", "rarity": Rarity.COMMON, "pattern": Pattern.SOLID,
		"color_a": Color(0.95, 0.95, 0.97), "loot": true},
	{"id": 2, "name": "Tinten-Schwarz", "rarity": Rarity.COMMON, "pattern": Pattern.SOLID,
		"color_a": Color(0.08, 0.08, 0.09), "loot": true},
	{"id": 3, "name": "Sturmgrau", "rarity": Rarity.COMMON, "pattern": Pattern.SOLID,
		"color_a": Color(0.45, 0.47, 0.5), "loot": true},
	{"id": 4, "name": "Waldgrün", "rarity": Rarity.COMMON, "pattern": Pattern.SOLID,
		"color_a": Color(0.1, 0.35, 0.18), "loot": true},

	# --- Ungewöhnlich (zweifarbig, einfaches Muster) ---
	{"id": 5, "name": "Kirsch-Streifen", "rarity": Rarity.UNCOMMON, "pattern": Pattern.STRIPES_H,
		"color_a": Color(0.7, 0.1, 0.15), "color_b": Color(0.95, 0.95, 0.95), "loot": true},
	{"id": 6, "name": "Bernstein-Streifen", "rarity": Rarity.UNCOMMON, "pattern": Pattern.STRIPES_V,
		"color_a": Color(0.9, 0.6, 0.05), "color_b": Color(0.15, 0.15, 0.17), "loot": true},
	{"id": 7, "name": "Ozean-Split", "rarity": Rarity.UNCOMMON, "pattern": Pattern.HALF_SPLIT,
		"color_a": Color(0.05, 0.55, 0.55), "color_b": Color(0.08, 0.12, 0.3), "loot": true},
	{"id": 8, "name": "Block-Trikot Lila", "rarity": Rarity.UNCOMMON, "pattern": Pattern.COLOR_BLOCK,
		"color_a": Color(0.35, 0.1, 0.5), "color_b": Color(0.85, 0.65, 0.15), "loot": true},

	# --- Selten (mehrfarbig / auffälliges Muster) ---
	{"id": 9, "name": "Bunte Ringel", "rarity": Rarity.RARE, "pattern": Pattern.HOOPS_TRICOLOR,
		"color_a": Color(0.8, 0.15, 0.15), "color_b": Color(0.95, 0.8, 0.1), "color_c": Color(0.1, 0.3, 0.85), "loot": true},
	{"id": 10, "name": "Diagonale Schärpe", "rarity": Rarity.RARE, "pattern": Pattern.SASH,
		"color_a": Color(0.07, 0.07, 0.08), "color_b": Color(0.1, 0.85, 0.85), "loot": true},
	{"id": 11, "name": "Schachbrett Pink", "rarity": Rarity.RARE, "pattern": Pattern.CHECKERBOARD,
		"color_a": Color(0.95, 0.15, 0.55), "color_b": Color(0.08, 0.08, 0.09), "loot": true},
	{"id": 12, "name": "Nadelstreifen Marine", "rarity": Rarity.RARE, "pattern": Pattern.PINSTRIPE,
		"color_a": Color(0.06, 0.1, 0.25), "color_b": Color(0.85, 0.87, 0.92), "loot": true},

	# --- Episch (Farbverläufe) ---
	{"id": 13, "name": "Sonnenuntergang", "rarity": Rarity.EPIC, "pattern": Pattern.GRADIENT_V,
		"color_a": Color(0.95, 0.5, 0.1), "color_b": Color(0.3, 0.08, 0.4), "loot": true},
	{"id": 14, "name": "Nova", "rarity": Rarity.EPIC, "pattern": Pattern.GRADIENT_RADIAL,
		"color_a": Color(0.95, 0.97, 1.0), "color_b": Color(0.05, 0.35, 0.95), "loot": true},
	{"id": 15, "name": "Sturmfront", "rarity": Rarity.EPIC, "pattern": Pattern.GRADIENT_DIAGONAL,
		"color_a": Color(0.55, 0.58, 0.62), "color_b": Color(0.05, 0.75, 0.85), "loot": true},
	{"id": 16, "name": "Magma", "rarity": Rarity.EPIC, "pattern": Pattern.GRADIENT_DUAL,
		"color_a": Color(0.9, 0.2, 0.05), "color_b": Color(0.08, 0.08, 0.09), "loot": true},

	# --- Legendär (extravagant) ---
	{"id": 17, "name": "Prisma", "rarity": Rarity.LEGENDARY, "pattern": Pattern.RAINBOW, "loot": true},
	{"id": 18, "name": "Hologramm", "rarity": Rarity.LEGENDARY, "pattern": Pattern.HOLOGRAPHIC, "loot": true},
	{"id": 19, "name": "Tarnung Digital", "rarity": Rarity.LEGENDARY, "pattern": Pattern.CAMO,
		"color_a": Color(0.2, 0.25, 0.15), "color_b": Color(0.08, 0.1, 0.07), "color_c": Color(0.55, 0.5, 0.35), "loot": true},
	{"id": 20, "name": "Flammenbrand", "rarity": Rarity.LEGENDARY, "pattern": Pattern.FLAME,
		"color_a": Color(0.95, 0.6, 0.05), "color_b": Color(0.95, 0.9, 0.4), "color_c": Color(0.15, 0.03, 0.02), "loot": true},
]

static func get_by_id(id: int) -> Dictionary:
	for j in JERSEYS:
		if j["id"] == id:
			return j
	return JERSEYS[0]

static func get_loot_table() -> Array:
	return JERSEYS.filter(func(j): return j.get("loot", false))
