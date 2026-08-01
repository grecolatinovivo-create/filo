# FILO — regole del progetto

Daily puzzle game: un filo ininterrotto sulla griglia 5×5 per totalizzare
esattamente la Somma del Giorno. Due client: web (`index.html`, file unico
offline) e iOS nativo SwiftUI (`native-ios/`).

## Verità normative (in ordine di autorità)

1. `/home/claude/gioco/README.md` — regole §6, generatore §7, punteggio §8,
   condivisione §9, persistenza §11. (Copia di lavoro: il repo del web.)
2. `/home/claude/gioco/UX_SPEC.md` — design system, palette, motion, a11y.
3. `/home/claude/gioco/NEURO_SPEC.md` — microcopy ESATTO (mai riformulare).
4. Il JS di `index.html` (sezioni RNG/GENERATOR/RULES/SHARE) è l'implementazione
   di riferimento del motore.

## Generatore CONGELATO — parità web/iOS obbligatoria

- L'ordine delle chiamate `rng()` (mulberry32) è NORMATIVO: L_sarto, startIdx,
  Fisher-Yates nella DFS ([su, destra, giù, sinistra]), 25 valori, guardia
  T ≥ 20 → seed+1. Qualsiasi modifica rompe la sincronia mondiale dei puzzle.
- `native-ios/Tests/FiloCoreTests/reference.json` contiene 310 vettori esportati
  dal motore JS (via `#debug` + `window.__filoDebug.generateForSeed`): il test
  Swift di parità confronta valori, T, percorso completo, L e seedUsato.
  **Se un test di parità fallisce, si corregge lo Swift, MAI il riferimento.**
- Vettori congelati: 20260801→T=97/L=17, 20260802→T=84/L=17, 20261225→T=85/L=19.
- EPOCH: 2026-08-01 (mezzanotte locale) = FILO #1.
- `buildShareText`/`ShareText.build` devono coincidere carattere per carattere
  (esempi §9.2). Nessuna riga URL finché l'URL pubblico non esiste.

## Architettura iOS (`native-ios/`)

- `Sources/FiloCore/` — logica PURA (solo Foundation, compila su Linux):
  Mulberry32, Generator, Rules (GameEngine), Scoring, ShareText, FiloDate.
- `Sources/App/` — SwiftUI (iOS 17+), MAI WebView. Persistenza UserDefaults
  con schema equivalente a §11.2 (`filo.onboarded`, `filo.stats`, `filo.today`).
- Doppia natura: `Package.swift` (SPM, solo FiloCore + test, per `swift test`
  su Linux) e `project.yml` (XcodeGen: FiloCore framework + app + test).
  I file SwiftUI NON sono nel package SPM.

## Dottrina fabbrica-app (non negoziabile)

- Il codice è la sorgente di verità: NESSUN `.xcodeproj` nel repo, solo
  `project.yml` rigenerato in CI con XcodeGen.
- Nessun segreto nel repo. Firma cloud all'export con chiave API ASC
  (secrets: `ASC_API_KEY_P8`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `APPLE_TEAM_ID`).
- Build e rilascio SOLO in GitHub Actions (runner macOS). Rilascio manuale
  via `workflow_dispatch`. Build number = `github.run_number` (mai a mano);
  `MARKETING_VERSION` si alza a mano in `project.yml`.
- `timeout-minutes` su ogni job; `concurrency: cancel-in-progress` sui check
  macOS; archivio salvato come artifact PRIMA dell'upload; retry con
  `retry-upload-ios-native.yml` (input: run_number) per l'errore 90382.
- Workflow: `check-ios-native.yml` (push su `native-ios/**`: swift test su
  Linux + build simulatore senza firma), `release-ios-native.yml` (TestFlight),
  `retry-upload-ios-native.yml`.

## Verifiche prima di ogni merge

1. `cd native-ios && swift test` (toolchain Linux ok) — deve passare al 100%,
   parità inclusa.
2. I file di `Sources/App` devono usare solo API iOS 17 (niente iOS 18+ senza
   fallback); sintassi verificabile con `swiftc -parse`.
3. YAML dei workflow e `project.yml` validi (`python3 -c "import yaml, ..."`).
4. Microcopy: confrontare con NEURO_SPEC §2 (testi esatti, plurali normativi).
