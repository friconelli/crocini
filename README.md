# Crocini

App macOS (SwiftUI) per impaginare sul foglio biglietti da visita, flyer, locandine e altri elementi da tagliare: calcola quanti pezzi entrano, li dispone e aggiunge abbondanza e segni di taglio (i "crocini"). Esporta un PDF pronto per la tipografia o per il taglio a ghigliottina.

## Download

Scarica `Crocini.zip` dall'[ultima release](https://github.com/friconelli/crocini/releases/latest), aprilo e trascina **Crocini.app** in Applicazioni. L'app è universale: gira su Mac Apple Silicon e Intel (macOS 13 o successivo).

L'app è firmata ad-hoc (non notarizzata): al primo avvio fai clic destro → **Apri**, oppure da Terminale `xattr -dr com.apple.quarantine /Applications/Crocini.app`.

## Aggiornamenti

All'avvio l'app controlla le GitHub Releases; se c'è una versione più nuova compare una finestra (e un pulsante **Aggiorna** nella barra laterale) per scaricarla, sostituire l'app e riavviare con un clic. Controllo manuale: menu **Crocini → Verifica aggiornamenti…**.

## Funzionalità

Tutto è personalizzabile (misure in mm) e ha dei preset.

- **Preset di configurazione**: 9 predefiniti (biglietti 85×55 e 90×50, cartoline, segnalibri, flyer A6/DL/A5, locandine A3, etichette) e preset personali da salvare ed eliminare.
- **Foglio di stampa**: A4, A3, SRA3, A5, Lettera o misure libere; verticale/orizzontale; margine.
- **Elemento**: preset di formato o misure libere, distanza tra elementi, rotazione automatica/sì/no per far entrare più pezzi.
- **Abbondanza**: valore libero (0 = nessuna). Se la grafica la contiene già, viene usata così com'è; altrimenti si aggiunge con un **colore piatto** a scelta o ingrandendo la grafica.
- **Segni di taglio** (i crocini): spessore, lunghezza, colore, distanza dal rifilo (automatica o fissa), stili predefiniti; si possono disattivare.
- **Grafica** (PNG, JPEG, PDF…) ripetuta su tutti gli elementi; mostra le dimensioni del file e può impostare l'elemento sulla sua misura.
- **Anteprima con zoom e spostamento** come negli editor grafici:
  - rotella del mouse, pinch o ⌘ + scroll = zoom sul punto del cursore; scroll a due dita sul trackpad = sposta;
  - strumento **Mano** (H, oppure barra spaziatrice o tasto centrale del mouse per spostarsi al volo; doppio clic = adatta);
  - strumento **Lente** (Z): clic ingrandisce, ⌥ clic rimpicciolisce, trascinando si zooma su un'area;
  - barra in basso con percentuale (25–800%, dimensioni reali al 100%), + / − e «adatta»; menu Vista: ⌘= ⌘− ⌘0 ⌘1.
- Anteprima in tempo reale ed **Esporta PDF** (⌘E).

## Da fare

- Più grafiche diverse sullo stesso foglio (fronte/retro, pagine multiple).
- Segni di registro, barra colore, fustelle.
- Preferiti per le misure, salvataggio dei progetti.

## Requisiti

macOS 13+, Xcode per compilare.

## Build

```bash
./Scripts/build_app.sh --install      # compila e installa in /Applications
VERSION=0.1.0 ./Scripts/build_app.sh --zip
```

## Pubblicare una nuova versione

```bash
Scripts/release.sh 1.1.0 "Note di rilascio"   # albero git pulito: imposta la versione, compila, tagga, crea la release con Crocini.zip
```
