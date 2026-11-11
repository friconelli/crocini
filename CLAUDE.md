# Crocini

App macOS SwiftUI (SwiftPM, nessuna dipendenza) per impaginare elementi da tagliare su un foglio, con segni di taglio e PDF. Struttura copiata da port-manager/dustbuster: `Sources/Crocini`, `Scripts/build_app.sh`, `Resources/Info.plist`.

- Tutte le misure nel codice sono in **millimetri**, origine in alto a sinistra; il PDF converte in punti (`PDFExporter.pointsPerMM`).
- `LayoutEngine` (Models.swift) è puro e testabile: griglia centrata, margine effettivo = max(margine, abbondanza + lunghezza segni + 1).
- Bundle id `com.federicomancinelli.crocini`. Nessun repository GitHub ancora.
- **Icona**: generata con Codex (`codex exec`), artwork in `icon/`. NIENTE bordo grigio: l'artwork deve essere a tutto campo, senza contorni né ombre; la tessera arrotondata con margine trasparente la compone lo script, mai l'immagine generata. macOS 26 aggiunge comunque un suo bordo sfumato alle icone: per verificare estrarre l'immagine dall'.icns dell'app installata.
- Nel Bash tool `cp` è interattivo: usare `/bin/cp -f`.
- **Build universale** (arm64 + x86_64, deve girare anche su Mac Intel): `build_app.sh` usa `--arch arm64 --arch x86_64` e fallisce se `lipo` non trova entrambe. Target macOS 13: non usare API più nuove senza `#available`.
- Prova dell'interfaccia senza permessi schermo: `Crocini.app/Contents/MacOS/Crocini --art file.png --snapshot out.png` salva la finestra in PNG e chiude.
- UI: Theme.swift (magenta #EE2177, SectionCard, PrimaryButtonStyle, ChipButtonStyle), anteprima animata in PreviewView (Animatable su `progress`), drag&drop in ArtworkDropZone.swift (si rilascia ovunque nella finestra).
- **Font**: Bricolage Grotesque (OFL, `Resources/Fonts`, copiato nel bundle da build_app.sh e dichiarato con `ATSApplicationFontsPath`). Nel codice usare sempre `Theme.font(...)`, mai `.system(...)`.
- Zoom/pan dell'anteprima: Viewport.swift (ViewportState + InteractionLayer NSView per rotella, pinch, mouse, tasti con monitor locale + ZoomBar). Il Canvas disegna tutta la vista con zoom/offset animabili; prove: `--zoom 3 --pan 120,-300` insieme a `--snapshot`.
- **Icona**: i crocini dell'artwork Codex sono neri e sul magenta si vedevano poco → `make_icon.sh` li ricolora in giallo (`Scripts/recolor_marks.swift`, `MARK_COLOR=RRGGBB` per cambiare); `icon/Crocini-art.png` resta l'originale.
- **Lingue**: app in italiano e inglese. Le chiavi sono i testi italiani; traduzioni in `Resources/en.lproj` e `it.lproj` (copiate nel bundle da build_app.sh). I testi letterali SwiftUI si traducono da soli, quelli costruiti a codice vanno con `L("…")`; i componenti con etichette (SectionCard, FieldRow, MMField, ChipLabel) usano `LocalizedStringKey`. Nuova stringa → aggiungerla in entrambi i .strings. Prova: `Crocini --snapshot out.png -AppleLanguages "(en)"`.
- **UI in quadricromia**: Theme.swift ha i colori di processo (cyan #00AEEF, magenta #EC008C, yellow #FFF200, ink K) e le "lastre" (`Plate`) usate da SectionCard (icona della scheda, ombra piena all'hover) e ChipButtonStyle; `CMYKBar` in cima alla finestra, `HalftoneBackdrop` (retino C M Y) sullo sfondo dell'anteprima, bordo tricolore rotante sulla zona di caricamento, pulsante principale con bordo e ombra nera piena. Nuovi controlli: scegliere una lastra, non un colore a caso.
