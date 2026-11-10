# Sprite Baker

Godot-Werkzeug für isometrische Sprite Sheets aus 3D-Modellen: animierte Kreaturen mit austauschbaren Teilen, statische Gegenstände und Umgebungsprops. Ausgabe sind **zugeschnittene PNG-Atlanten und ein engineunabhängiges JSON-Manifest (v2)**. Jeder Frame erhält sein Atlas-Rechteck, den Offset im gemeinsamen Bildraum und die ursprüngliche Größe; Farbe, Maske und Tiefe bleiben deckungsgleich. Die eingebaute Paper-Doll-Vorschau liest ausschließlich diese Exportdateien.

## Starten

Voraussetzungen: **Godot 4.6.1** mit funktionierendem Grafikrenderer; für `.blend` zusätzlich Blender (getestet mit **4.5.3 LTS**). Forward+ ist der Projektstandard. Es gibt keine Paketmanager- oder Plugin-Abhängigkeiten.

`project.godot` im Godot-Editor öffnen und mit **F5** starten, oder unter Windows:

```powershell
./scripts/run.ps1 app
./scripts/run.ps1 editor
# Alternativ eine offizielle Godot-Binary explizit angeben:
./scripts/run.ps1 app -Godot 'C:/Tools/Godot/Godot_v4.6.1-stable_win64_console.exe'
```

Das Startskript bevorzugt die lokale, ignorierte portable Installation unter `.tools/godot/`, danach `GODOT_PATH` bzw. `godot` aus PATH. `GODOT_BINARY` oder `-Godot` überschreibt die Auswahl. Ein kaputter Wrapper wird mit einer verständlichen Meldung abgelehnt. Die während der Entwicklung vorgefundenen Wrapper wurden nicht verändert; die funktionierende portable Kopie ist nicht Teil von Git.

## Erster Export

1. Die eingebaute Kreaturendemo ist sofort verfügbar. Für zwei austauschbare Helme **Konfiguration laden → `configs/demo_creature.json`** wählen. `demo_item.json` und `demo_prop.json` zeigen die statischen Workflows.
2. Unter **Teile** Slots, Varianten, Materialregionen und optionale Masken einstellen. Alle Varianten derselben Familie gehören in denselben Bake-Auftrag.
3. Unter **Animationen** Clips, Zeitbereiche und Abtastrate wählen. Die Kreaturendemo enthält eine bewegte Waffe und einen tatsächlich geskinnten Umhang.
4. **Profil einpassen** berücksichtigt sämtliche ausgewählten Varianten, Posen und Richtungen und sperrt Kamera, Raster und Tiefenraum. Danach die Konfiguration speichern.
5. **Sprite Sheets backen** schreibt einen neuen vollständigen Export. Die **PNG-Vorschau** öffnet das Ergebnis; Varianten, Blickrichtung, Frame und drei Farbtöne können geprüft werden.

Standard: orthografisch, 30° über der Horizontalen, 45° Ausgangsazimut, acht Richtungen, 12 Frames/Sekunde, 256 × 256 Zielpixel und 2× Exportauflösung. Kamera und Licht bleiben fest, die Modelle drehen sich um den gemeinsamen Ursprung. Die Schleifen-Endpose wird nicht doppelt aufgenommen.

Eine Konfigurationsänderung an Kamera, Animation oder Beleuchtung verlangt erneutes Einpassen. Bereits gesperrte Profile werden gegen stille Änderungen geprüft. Neue Varianten außerhalb des bisherigen Bildausschnitts werden abgelehnt. Zusammengehörige Teile nach einer Profiländerung gemeinsam neu exportieren.

## Eigene Modelle und Teile

Quellen beispielsweise unter `assets/` ablegen und **zuerst im Godot-Editor importieren lassen**. `.blend` wird über Blenders glTF-Export importiert; Blender muss dafür installiert sein. Falls nötig den Installationsordner in **Editor Settings → Filesystem → Import → Blender → Blender Path** eintragen. Der Baker rendert Godots importierte Materialien, nicht Blenders beliebige Shader-Nodes.

Im Tool **Modell wählen → Quelle untersuchen** verwenden. Die erkannten Meshes, Knochen und Animationen werden für die Konfiguration angeboten. Mehrere zusammengehörige Meshes können als ein Teil über ihren gemeinsamen Node-Pfad ausgewählt werden.

- Pro Kreaturenfamilie ein gemeinsames Rig. Externe verformbare Teile müssen Knochenstruktur, Restposen und Rig-Transformationen teilen; es findet kein Retargeting statt.
- Starre Ausrüstung erhält eine separate Quellszene und einen benannten Befestigungsknochen. Position, Rotation und Skalierung lassen sich pro Teil korrigieren.
- Für Varianten denselben Slot verwenden, beispielsweise `head`; Teil-IDs müssen eindeutig sein. Die PNG-Vorschau wählt höchstens eine Variante je Slot.
- Unterstützte Animationen bewegen Position, Rotation, Skalierung und Blend Shapes. Scripts, Physik, Material-/Visibility-Tracks und prozedurale Treiber gehören nicht zum Bake-Vertrag.
- Unterstützt werden Standardmaterialien mit deckender oder ausgeschnittener Transparenz. Benutzerdefinierte Shader, Overlays, Parallax-Mapping, Geometriewachstum und Fade-Effekte werden mit einer Fehlermeldung abgelehnt. Deckende, nicht einfärbbare Triplanar-Materialien werden originalgetreu unterstützt; Triplanar mit Alpha-Ausschnitt oder Farbmaske nicht. Partikel, CSG, MultiMeshes und andere zusätzliche Renderquellen werden nicht still in Datenkanäle übernommen.
- Ein Mesh kann nicht als separat isoliertes Teil unter einem anderen Mesh liegen. Solche Geometrie gemeinsam gruppieren oder unter reine Node3D-Container umordnen.

## Einfärbung und Verdeckung

Jedes Teil erhält **Farbe, RGB-Maske und RGB24-Tiefe**. Farbregionen werden pro Materialoberfläche zugeordnet oder aus einer RGB-Maskentextur gelesen. Die Oberfläche wird für markierte Bereiche neutralisiert; Texturdetails und gebackene Beleuchtung bleiben erhalten. Nicht markierte Pixel behalten ihre Farbe. Multiplikatives Färben kann schwarze Ausgangsflächen nicht aufhellen.

Jedes Teil wird vollständig und einzeln gerendert. Selbstschatten sind erlaubt; Schatten und Reflexionen zwischen austauschbaren Teilen werden nicht mitgebacken. Damit hängt ein Helm-Export nicht von einer bestimmten Waffe ab.

Im Zielprojekt muss ein Shader oder entsprechender Bild-Compositor pro Pixel die nächstgelegene gültige Tiefe auswählen. **Erst die zusammengesetzten Bilder herunterrechnen**, vorzugsweise im linearen Farbraum mit vormultipliziertem Alpha. Einfaches Übereinanderzeichnen normaler Sprite-Layer reicht bei sich kreuzender Ausrüstung nicht aus. Masken und gepackte Tiefen weder als sRGB laden noch bilinear filtern oder mit verlustbehafteter Texturkompression versehen.

Die vollständigen Datenfelder, Richtungs-/Pivot-Konventionen und Formeln stehen in [docs/export-format.md](docs/export-format.md). `src/core/compositor.gd` ist die Referenzimplementierung, `src/export/export_reader.gd` der reine PNG-/JSON-Verbraucher.

## Dateien und Grenzen

- `configs/`: versionierbare Beispielkonfigurationen; eigene JSON-Konfigurationen können daneben gespeichert werden.
- `assets/`: eigene versionierbare Quellen.
- `output/`: ignorierte Exporte. Externe Ordner sind auswählbar; vorhandene Exporte werden nicht überschrieben.
- `.partial-*`: abgebrochene oder fehlgeschlagene Ausgaben. Sie werden niemals als vollständige Exporte geöffnet und können nach Prüfung manuell entfernt werden.
- Seiten sind maximal 4096 × 4096 Pixel groß. Lange Animationen werden automatisch über mehrere Seiten verteilt, ohne Frames zu zerschneiden.
- Ein Auftrag ist auf 100.000 Teil-/Frame-/Richtungskombinationen begrenzt. Größere Aufträge in kleinere Exportgruppen teilen und jede zusammengehörige Gruppe gemeinsam einpassen.
- Echte Teiltransparenz, Glas, automatische Kleidungsanpassung, Bodenschatten und Pixel-Art-Paletten gehören nicht zum Exportvertrag. RGB24 bedeutet 24-Bit-Speicherung; die tatsächliche geometrische Genauigkeit ist zusätzlich durch GPU-Fließkommaarithmetik begrenzt.

## Prüfen

```powershell
./scripts/run.ps1 test          # Kernlogik, Szenen/Rigs, Export-I/O, UI
./scripts/run.ps1 render-test   # benötigt Grafikrenderer
./scripts/run.ps1 coverage      # Python 3, nur Standardbibliothek
./scripts/run.ps1 all-tests
```

Die Coverage-Prüfung instrumentiert ausschließlich temporäre Kopien unter `.godot/core-coverage/`. Sie erzwingt mindestens 80 % ausgeführte Anweisungen der nichtgrafischen Kernmodule; Quellcode bleibt unverändert. Testprotokolle stehen in `.tools/test-logs/`, Bilder unter `output/`.

Die GPU-Suite prüft RGB24-Grenzfälle, bytegenaue Daten-PNGs, Alpha-Ausschnitte und Rückseiten sowie acht Richtungen × zwei Animationsposen gegen eine gemeinsam gerenderte Referenz. Weitere Tests prüfen Abbruch im letzten Frame, ungültige Profile, überschrittene Bildgrenzen und den UI-Ablauf Einpassen → Speichern/Laden → Backen → PNG-Vorschau.

Optionaler Test einer **echten Blender-Datei**, in einem separaten Hintergrundprozess:

```powershell
& 'C:/Program Files/Blender Foundation/Blender 4.5/blender.exe' --background --factory-startup --python tests/create_blend_fixture.py
& '.tools/godot/Godot_v4.6.1-stable_win64_console.exe' --headless --editor --path . --import
& '.tools/godot/Godot_v4.6.1-stable_win64_console.exe' --path . --script tests/test_blend_import.gd
```

Die erzeugte Fixture liegt unter `tests/fixtures/generated/` und wird nicht versioniert. Der Test importiert sie über Godot, backt ihre Teile und rekonstruiert alle acht Richtungen aus den Exportdateien.

## Plunderground-Menschen und Rust-Auslieferung

Die originale modulare Menschenfamilie wird mit `scripts/prepare_human.py` aus
lokalen Referenzprojekten vorbereitet. Siehe [Menschen-Pipeline](docs/human-male.md)
für Quellen, Farbregionen, Ausrüstung und Bake-Aufrufe sowie
[Auslieferung an plunderground_rust](docs/delivery.md) für unveränderte Bundles,
Outfits und den engineübergreifenden Pixelvergleich.
