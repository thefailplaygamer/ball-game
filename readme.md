# Ball

Ein Ragdoll-Fußballspiel für LAN-Partien, gebaut mit Godot 4.7.

Zwei Teams zu je fünf Spielern treten in einer geschlossenen Glas-Arena gegeneinander an. Die Spielfiguren balancieren sich über einen Physik-Regler selbst aufrecht — wer angerempelt wird oder eine Grätsche abbekommt, kippt um und muss erst wieder auf die Beine kommen.

**[Aktuelle Version herunterladen](https://github.com/thefailplaygamer/ball-game/releases/latest)** — einzelne `Ball.exe` für Windows, keine Installation nötig.

## Spielprinzip

- **5 gegen 5**: Torwart, drei Verteidiger und ein Stürmer pro Team. Die Position wird nach dem Beitreten über eine Feldkarte gewählt.
- **Zwei Halbzeiten à 5 Minuten** mit 15 Sekunden Pause dazwischen. Die Uhr steht während Torjubel, Wiederholung und Pause still.
- **Ausdauer**: Sprinten, Schießen und Grätschen kosten Ausdauer, die sich im Stehen wieder auffüllt.
- **Zeitstrafe**: Nach drei erfolgreichen Grätschen wandert man für 10 Sekunden vom Platz.
- **Tor-Wiederholung**: Nach jedem Treffer läuft automatisch eine Zeitlupe aus seitlicher Kameraperspektive.

## Steuerung

| Taste | Aktion |
|---|---|
| `W` `A` `S` `D` | Laufen |
| `Umschalt` | Sprinten (kostet Ausdauer) |
| `Leertaste` | Schießen — Richtung und Höhe folgen dem Blick |
| `Strg` | Grätschen |
| Maus | Umsehen |
| Linke Maustaste (halten) | Kamera dreht sich zum Ball |
| `Tab` | Spielstand-Übersicht |
| `Esc` | Pausenmenü |
| `Enter` | Chat |

## Chat-Befehle

Für alle Spieler:

| Befehl | Wirkung |
|---|---|
| `/vs`, `/votestart` | Für Spielstart stimmen |
| `/vw`, `/votewarmup` | Für Rückkehr in die Aufwärmphase stimmen |
| `/ping` | Eigenen Ping anzeigen |
| `/help` | Befehlsübersicht |

Nur für den Host:

| Befehl | Wirkung |
|---|---|
| `/dummy`, `/bot` | Test-Spielfigur einsetzen |
| `/cleardummies` | Alle Test-Figuren entfernen |
| `/start` | Spiel sofort starten |
| `/pause`, `/resume` | Uhr anhalten bzw. weiterlaufen lassen |
| `/halftime` | Halbzeit erzwingen |
| `/settime <s\|mm:ss>` | Restzeit setzen, z.B. `/settime 1:30` |
| `/addtime <s>` | Zeit addieren (negative Werte ziehen ab) |
| `/end` | Spiel beenden |
| `/kick <Name>` | Spieler aus der Lobby werfen |
| `/swap <Name>` | Spieler ins andere Team schieben |

## Netzwerk

Gespielt wird über ENet auf **Port 7777**, bis zu **8 Spieler** gleichzeitig. Der Host startet die Partie, alle anderen tragen dessen IP ein — die eigene lokale IP steht direkt im Hauptmenü.

Der Host simuliert die komplette Physik; die Clients bekommen Positionen und Rotationen synchronisiert. Läuft der Host über das Internet statt im LAN, muss Port 7777 entsprechend weitergeleitet werden.

## Trikots

29 Trikots in fünf Seltenheitsstufen, von schlichten Vereinsklassikern bis zu voll animierten legendären Mustern. Sie werden aus Kisten erlost und im Inventar ausgerüstet; die Muster sind komplett als Shader umgesetzt, es gibt keine Bilddateien dafür.

Accounts und Inventar liegen in einer Supabase-Instanz — das Anmelden, Kisten öffnen und Ausrüsten braucht daher eine Internetverbindung. **Die eigentlichen LAN-Partien laufen komplett offline.**

## Aufbau des Projekts

```
RagdollSoccer/game/       Godot-Projekt des Spiels
  scenes/                 Szenen (Match, Menü, Inventar, Spieler, Ball)
  scripts/                Spiellogik, Netzwerk, Supabase-Anbindung
  shaders/                Rasen, Stadion, Ball, Trikot-Muster
  assets/                 Audio, Schriften, die eine Grastextur
RagdollSoccer/launcher/   Separates Godot-Projekt für den Auto-Updater
supabase/schema.sql       Datenbankschema für Accounts und Inventar
```

Fast alle Oberflächen im Spiel — Rasen mit Spielfeldmarkierungen, Tribünen samt Publikum, Ballmuster, Tornetz, Trikots — werden im Shader berechnet statt aus Texturdateien geladen. Deshalb kommt das Projekt mit einer einzigen Bilddatei aus.

## Selbst bauen

Nötig ist Godot **4.7.1** (Standard-Version, nicht .NET) mit den Windows-Export-Templates.

```bash
godot --headless --path RagdollSoccer/game --export-release "Windows Desktop"
```

Die fertige `Ball.exe` landet in `RagdollSoccer/builds/windows/`. Zum Öffnen im Editor einfach `RagdollSoccer/game/project.godot` laden.

## Lizenzen

Schriften und Audiodateien stammen aus freien Quellen, die Nachweise stehen in `RagdollSoccer/game/assets/fonts/CREDITS.txt`, `assets/audio/CREDITS.txt` und `assets/textures/CREDITS.txt`.
