class_name JerseyData
extends RefCounted

## Trikot-Muster-Modi. Die Zahlenwerte MÜSSEN mit den Modus-Nummern in
## shaders/jersey_patterns.gdshaderinc übereinstimmen und sind bewusst nach
## Seltenheit sortiert (0–3 gewöhnlich … 21–25 legendär): die Shader lesen aus
## der Nummer ab, wie glänzend der Stoff ist und ob er leuchtet.
enum Pattern {
	# Gewöhnlich: schlicht, aber sauber verarbeitet
	SOLID,          # 0
	TONAL_STRIPES,  # 1
	HEATHER,        # 2
	CHEST_BAND,     # 3
	# Ungewöhnlich: klassische Vereinsmuster
	STRIPES_V,      # 4
	STRIPES_H,      # 5
	HALF_SPLIT,     # 6
	PINSTRIPE,      # 7
	SASH,           # 8
	GINGHAM,        # 9
	# Selten: geometrisch, dreifarbig
	CHEVRON,        # 10
	ARGYLE,         # 11
	HEX_GRID,       # 12
	SHARDS,         # 13
	DIGI_CAMO,      # 14
	TIGER,          # 15
	# Episch: Verläufe, Leuchten, dezente Bewegung
	SUNSET,         # 16
	NEBULA,         # 17
	CIRCUIT,        # 18
	FROST,          # 19
	MAGMA,          # 20
	# Legendär: voll animiert
	PRISM,          # 21
	HOLOFOIL,       # 22
	INFERNO,        # 23
	CYBERGRID,      # 24
	GALAXY,         # 25
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

## Wie stark das Icon die Kachel hinter dem Trikot in der Seltenheitsfarbe
## einfärbt — steigt bewusst deutlich an, damit ein Legendäres schon im
## Grid-Überblick heraussticht.
const RARITY_GLOW := {
	Rarity.COMMON: 0.0,
	Rarity.UNCOMMON: 0.1,
	Rarity.RARE: 0.22,
	Rarity.EPIC: 0.4,
	Rarity.LEGENDARY: 0.62,
}

## Muster mit genau EINEM Blickfang in der Mitte (Sonnenscheibe, Galaxienkern).
## Die dürfen auf Armen und Beinen nicht wiederholt werden, sonst klebt an jedem
## Gliedmaß noch eine zweite Sonne — player.gd gibt diesen Teilen dafür einen
## seitlichen Ausschnitt des Musters.
const FOCAL_PATTERNS := [Pattern.SUNSET, Pattern.GALAXY]

## id 0 = Standard-Trikot: immer im Besitz, feste Team-Farbe (nicht in Kisten).
## Alle anderen 28 Trikots sind team-unabhängige Skins, die per Kiste erlost
## werden — 6 gewöhnliche/ungewöhnliche/seltene, 5 epische, 5 legendäre.
##
## WARTUNGSHINWEIS: Neue Einträge mit "loot": true brauchen zusätzlich eine
## Zeile in public.jersey_weights (siehe supabase/schema.sql), sonst können sie
## nie aus einer Kiste fallen.
const JERSEYS := [
	{"id": 0, "name": "Standard", "rarity": Rarity.COMMON, "pattern": Pattern.SOLID, "loot": false},

	# --- Gewöhnlich: ruhige Vereinsklassiker ---
	{"id": 1, "name": "Kreide-Weiß", "rarity": Rarity.COMMON, "pattern": Pattern.SOLID,
		"color_a": Color(0.94, 0.95, 0.97), "loot": true},
	{"id": 2, "name": "Tinten-Schwarz", "rarity": Rarity.COMMON, "pattern": Pattern.SOLID,
		"color_a": Color(0.11, 0.11, 0.14), "loot": true},
	{"id": 3, "name": "Waldgrün", "rarity": Rarity.COMMON, "pattern": Pattern.SOLID,
		"color_a": Color(0.1, 0.32, 0.17), "loot": true},
	{"id": 4, "name": "Sturmgrau Melange", "rarity": Rarity.COMMON, "pattern": Pattern.HEATHER,
		"color_a": Color(0.38, 0.4, 0.44), "color_b": Color(0.62, 0.65, 0.7), "loot": true},
	{"id": 5, "name": "Ziegelrot Ton-in-Ton", "rarity": Rarity.COMMON, "pattern": Pattern.TONAL_STRIPES,
		"color_a": Color(0.6, 0.16, 0.13), "color_b": Color(0.42, 0.09, 0.08), "loot": true},
	{"id": 6, "name": "Marine Brustband", "rarity": Rarity.COMMON, "pattern": Pattern.CHEST_BAND,
		"color_a": Color(0.09, 0.14, 0.3), "color_b": Color(0.88, 0.89, 0.93), "loot": true},

	# --- Ungewöhnlich: klare Zweifarb-Muster ---
	{"id": 7, "name": "Kirsch-Streifen", "rarity": Rarity.UNCOMMON, "pattern": Pattern.STRIPES_V,
		"color_a": Color(0.72, 0.1, 0.16), "color_b": Color(0.95, 0.95, 0.96), "loot": true},
	{"id": 8, "name": "Bernstein-Ringel", "rarity": Rarity.UNCOMMON, "pattern": Pattern.STRIPES_H,
		"color_a": Color(0.92, 0.62, 0.06), "color_b": Color(0.12, 0.12, 0.14), "loot": true},
	{"id": 9, "name": "Ozean-Halbe", "rarity": Rarity.UNCOMMON, "pattern": Pattern.HALF_SPLIT,
		"color_a": Color(0.04, 0.52, 0.55), "color_b": Color(0.06, 0.12, 0.32),
		"color_c": Color(0.92, 0.93, 0.95), "loot": true},
	{"id": 10, "name": "Nadelstreifen Marine", "rarity": Rarity.UNCOMMON, "pattern": Pattern.PINSTRIPE,
		"color_a": Color(0.06, 0.1, 0.24), "color_b": Color(0.85, 0.87, 0.92), "loot": true},
	{"id": 11, "name": "Königsschärpe", "rarity": Rarity.UNCOMMON, "pattern": Pattern.SASH,
		"color_a": Color(0.07, 0.07, 0.09), "color_b": Color(0.12, 0.45, 0.92),
		"color_c": Color(0.9, 0.75, 0.25), "loot": true},
	{"id": 12, "name": "Karo Salbei", "rarity": Rarity.UNCOMMON, "pattern": Pattern.GINGHAM,
		"color_a": Color(0.14, 0.32, 0.25), "color_b": Color(0.82, 0.87, 0.74), "loot": true},

	# --- Selten: geometrisch, dreifarbig, auffällig ---
	{"id": 13, "name": "Chevron Kobalt", "rarity": Rarity.RARE, "pattern": Pattern.CHEVRON,
		"color_a": Color(0.07, 0.14, 0.4), "color_b": Color(0.1, 0.55, 0.95),
		"color_c": Color(0.92, 0.95, 1.0), "loot": true},
	{"id": 14, "name": "Argyle Burgund", "rarity": Rarity.RARE, "pattern": Pattern.ARGYLE,
		"color_a": Color(0.3, 0.05, 0.14), "color_b": Color(0.72, 0.16, 0.3),
		"color_c": Color(0.9, 0.78, 0.45), "loot": true},
	{"id": 15, "name": "Waben Zitrus", "rarity": Rarity.RARE, "pattern": Pattern.HEX_GRID,
		"color_a": Color(0.11, 0.11, 0.13), "color_b": Color(0.95, 0.72, 0.08),
		"color_c": Color(0.98, 0.95, 0.55), "loot": true},
	{"id": 16, "name": "Splitterglas", "rarity": Rarity.RARE, "pattern": Pattern.SHARDS,
		"color_a": Color(0.12, 0.14, 0.24), "color_b": Color(0.4, 0.16, 0.6),
		"color_c": Color(0.55, 0.9, 0.96), "loot": true},
	{"id": 17, "name": "Digitaltarn", "rarity": Rarity.RARE, "pattern": Pattern.DIGI_CAMO,
		"color_a": Color(0.19, 0.25, 0.16), "color_b": Color(0.08, 0.11, 0.08),
		"color_c": Color(0.53, 0.5, 0.34), "loot": true},
	{"id": 18, "name": "Tigerpfad", "rarity": Rarity.RARE, "pattern": Pattern.TIGER,
		"color_a": Color(0.95, 0.55, 0.05), "color_b": Color(0.08, 0.06, 0.05),
		"color_c": Color(0.99, 0.85, 0.45), "loot": true},

	# --- Episch: Verläufe mit Eigenleuchten und dezenter Bewegung ---
	{"id": 19, "name": "Sonnenuntergang", "rarity": Rarity.EPIC, "pattern": Pattern.SUNSET,
		"color_a": Color(0.98, 0.45, 0.12), "color_b": Color(0.2, 0.05, 0.35),
		"color_c": Color(0.99, 0.82, 0.35), "loot": true},
	{"id": 20, "name": "Nebula", "rarity": Rarity.EPIC, "pattern": Pattern.NEBULA,
		"color_a": Color(0.22, 0.1, 0.55), "color_b": Color(0.88, 0.2, 0.55),
		"color_c": Color(0.5, 0.85, 0.98), "loot": true},
	{"id": 21, "name": "Schaltkreis", "rarity": Rarity.EPIC, "pattern": Pattern.CIRCUIT,
		"color_a": Color(0.1, 0.95, 0.62), "color_b": Color(0.65, 0.99, 0.88),
		"color_c": Color(0.03, 0.07, 0.08), "loot": true},
	{"id": 22, "name": "Frostbruch", "rarity": Rarity.EPIC, "pattern": Pattern.FROST,
		"color_a": Color(0.72, 0.88, 0.97), "color_b": Color(0.09, 0.24, 0.45),
		"color_c": Color(0.96, 0.99, 1.0), "loot": true},
	{"id": 23, "name": "Magmakern", "rarity": Rarity.EPIC, "pattern": Pattern.MAGMA,
		"color_a": Color(0.98, 0.35, 0.05), "color_b": Color(0.99, 0.85, 0.35),
		"color_c": Color(0.09, 0.07, 0.07), "loot": true},

	# --- Legendär: voll animiert ---
	{"id": 24, "name": "Prisma", "rarity": Rarity.LEGENDARY, "pattern": Pattern.PRISM, "loot": true},
	{"id": 25, "name": "Hologramm", "rarity": Rarity.LEGENDARY, "pattern": Pattern.HOLOFOIL, "loot": true},
	{"id": 26, "name": "Flammenbrand", "rarity": Rarity.LEGENDARY, "pattern": Pattern.INFERNO,
		"color_a": Color(0.98, 0.42, 0.04), "color_b": Color(1.0, 0.92, 0.55),
		"color_c": Color(0.1, 0.03, 0.02), "loot": true},
	{"id": 27, "name": "Cybergitter", "rarity": Rarity.LEGENDARY, "pattern": Pattern.CYBERGRID,
		"color_a": Color(0.1, 0.95, 0.92), "color_b": Color(0.98, 0.16, 0.66),
		"color_c": Color(0.02, 0.03, 0.07), "loot": true},
	{"id": 28, "name": "Galaxie", "rarity": Rarity.LEGENDARY, "pattern": Pattern.GALAXY,
		"color_a": Color(0.38, 0.16, 0.78), "color_b": Color(0.96, 0.36, 0.76),
		"color_c": Color(0.02, 0.02, 0.06), "loot": true},
]

static func get_by_id(id: int) -> Dictionary:
	for j in JERSEYS:
		if j["id"] == id:
			return j
	return JERSEYS[0]

static func get_loot_table() -> Array:
	return JERSEYS.filter(func(j): return j.get("loot", false))

## Ab "Episch" bewegt sich das Muster von selbst (die Shader rechnen mit TIME);
## legendär zusätzlich mit pulsierender Aura im Icon.
static func is_animated(id: int) -> bool:
	var def := get_by_id(id)
	return int(def.get("rarity", Rarity.COMMON)) >= Rarity.EPIC
