# Quellmodelle

Eigene `.blend`, `.glb`, `.gltf` oder `.tscn`-Dateien hier ablegen und zunächst im Godot-Editor importieren lassen. Diese Quelldateien werden versioniert. Die eingebauten Demos benötigen keine externen Dateien.

Blender-Dateien benötigen eine funktionierende Blender-Installation. Falls die automatische Erkennung fehlschlägt: **Editor → Editor Settings → Filesystem → Import → Blender → Blender Path** auf den Blender-Installationsordner einstellen.

Kreaturenfamilien verwenden kompatible Skelette. Starre Ausrüstung wird an benannte Knochen angehängt; verformbare externe Teile brauchen identische Knochen, Rest- und Rig-Transformationen. Animationen dürfen Transformationen und Blend Shapes enthalten. Physik, prozedurale Animationstreiber und Materialanimationen werden nicht gebacken.
