# QA_REPORT_REPO.md — Audit finale del monorepo FILO

> QA/Auditor di repo (contesto pulito, verifiche eseguibili — nessuna fiducia
> nelle dichiarazioni dei developer). Data: 2026-07-31.
> Toolchain: Swift 6.0.3 Linux, Node + Playwright (da `/home/claude/gioco`), Python 3.

---

## 1. Matrice verifica → esito

### 1.1 Dottrina fabbrica-app (repo)

| Verifica | Metodo | Esito |
|---|---|---|
| Nessun `.xcodeproj` versionato | `find` su tutto il repo | ✅ assente |
| Nessun segreto/chiave nel repo | grep `BEGIN PRIVATE KEY`, `AuthKey`, `.p8/.p12`, api key hardcoded | ✅ nessuno (i due match in release/retry yml sono la **costruzione a runtime** del PEM dal secret `ASC_API_KEY_P8`, non chiavi) |
| `.gitignore` copre build/chiavi | lettura | ✅ `AuthKey*`, `*.ipa`, `**/build/`, `**/DerivedData/`, `*.xcodeproj/`, `.build/`, `.env*` |
| `check-ios-native.yml` | `yaml.safe_load` + lettura | ✅ path filter `native-ios/**` + self, `concurrency: cancel-in-progress: true`, `timeout-minutes` 10/15, job Linux `swift test` (container swift:6.0) + build simulatore `CODE_SIGNING_ALLOWED=NO`, exit code preservato via `PIPESTATUS` |
| `release-ios-native.yml` | idem | ✅ solo `workflow_dispatch`, timeout 40, archive senza firma, `CURRENT_PROJECT_VERSION=${{ github.run_number }}`, **artifact xcarchive-N salvato PRIMA dell'export/upload** (retention 7gg), ExportOptions `app-store-connect` + `signingStyle: automatic`, secrets `ASC_API_KEY_P8`/`ASC_KEY_ID`/`ASC_ISSUER_ID`/`APPLE_TEAM_ID` referenziati via env |
| `retry-upload-ios-native.yml` | idem | ✅ `workflow_dispatch` con input `run_number` (required), scarica `xcarchive-<n>` via `gh run download` (con guard se il run non esiste), **nessuna ricompilazione**: solo export+upload, timeout 20 |
| Placeholder `<APP>` residui | grep | ✅ nessuno |
| `project.yml` coerente | `yaml.safe_load` + verifica path | ✅ `Sources/FiloCore`, `Sources/App`, `Resources`, `Tests/FiloCoreTests` esistono; bundle id `com.grecolatinovivo.filo` (core: `.filo.core`, test: `.filo.coretests`); iOS 17.0; target `FiloCoreTests` (bundle.unit-test) nello scheme `FILO` |

### 1.2 Core Swift (FiloCore)

| Verifica | Metodo | Esito |
|---|---|---|
| `swift test` su Linux | Swift 6.0.3 | ✅ **32/32 test passati, 0 failure** (dopo fix, era 31/31 prima) |
| `reference.json` ≥ 300 seed | Python | ✅ **310 vettori** (309 seed unici; il seed 20300101 compare due volte — una col `numero` calcolato, una con `numero:null` — le due entry generano identico: innocuo) |
| Vettori congelati | Python su reference.json + `testVettoriCongelati` | ✅ 20260801→T=97/L=17 · 20260802→T=84/L=17 · 20261225→T=85/L=19 |
| **Parità JS↔Swift su 30 seed NUOVI** (verifica indipendente) | Playwright su `file:///home/claude/filo/index.html#debug` → `window.__filoDebug.generateForSeed` per 30 seed 202702xx–202703xx **assenti da reference.json**; eseguibile Swift temporaneo (swiftc sui sorgenti FiloCore, poi rimosso) sugli stessi seed; confronto Python campo per campo | ✅ **30/30 identici** su `valori` (25), `T`, `percorsoSarto` completo, `L_sarto`, `seedUsato` |

### 1.3 SwiftUI (Sources/App)

| Verifica | Esito |
|---|---|
| `swiftc -parse` su tutti gli 8 file | ✅ zero errori |
| API iOS 17-only (no iOS 18+) | ✅ `sensoryFeedback` (17), `onChange` a 2 parametri (17), `AccessibilityNotification` (17), `ShareLink` (16), `TimelineView` (15), `confirmationDialog` (15) — nessuna API 18+ |
| `@Published`/`@StateObject`/`@EnvironmentObject` | ✅ `GameEngine` è **struct**: le mutazioni tramite `@Published var engine` pubblicano correttamente; un solo `@StateObject` alla radice |
| Force unwrap pericolosi | ✅ nessuno (`punti[0]` protetto da guard sul conteggio; nessun `try!`/`!` su Optional a rischio) |
| Caricamento reference.json nei test | ✅ doppio binario `#if SWIFT_PACKAGE` (Bundle.module) / `Bundle(for:)` (XcodeGen) |
| Microcopy vs NEURO_SPEC (campionato) | ✅ onboarding (5 righe regole + "Un nuovo FILO ogni giorno…" + CTA `Gioca il FILO #{n}`), toast esiti §2.3 (Crack!/Vicolo cieco/Strappo netto + plurale normativo), dialog strappo §2.3 (3 varianti `{n}`≥2/=1/=0, bottoni Strappa/Continua), etichette+sotto-righe vittoria §2.1 (4 livelli, testi esatti), sconfitta §2.2 (`Oggi il Sarto la spunta` + riga dati + sotto-riga), milestone streak §2.4 (2/3/7/30), caption invito §2.5, countdown `Il prossimo FILO si cuce tra`, banner `🧵 C'è un nuovo FILO!`, annunci VoiceOver = testi aria-live UX_SPEC §9.5 |
| Difetto trovato | ⚠️→✅ **URL mancante nella condivisione iOS** (fix sotto) |

### 1.4 Web repo

| Verifica | Esito |
|---|---|
| `node qa_test.js` | ✅ 194/194 |
| `node smoke.js` | ✅ tutto passato (49 PASS) |
| `node share_url_test.js` | ✅ SHARE_URL presente, testo termina con la riga URL, una sola volta |
| sha256 `gioco/index.html` = `filo/index.html` | ✅ identici (`fd5b18f9…b732b6ba`) |
| `vercel.json` | ✅ `json.load` ok; chiavi: `$schema`, `cleanUrls`, `trailingSlash`, `headers` — **nessuna `functions`** |
| Meta tag senza richieste di rete | ✅ `og:url` testuale (nessun fetch), **nessuna `og:image`**, favicon = data-URI SVG inline |

---

## 2. Fix applicati

1. **`native-ios/Sources/FiloCore/ShareText.swift`** — il web ha `CONFIG.SHARE_URL = 'https://filo-game.vercel.app'` e il testo condiviso termina con la riga URL; l'iOS non la includeva mai (l'amico che riceve non aveva destinazione — rischio "Alto" in NEURO_SPEC §6). Aggiunto parametro `url: String? = nil` con la **stessa condizione del JS** (`if (CONFIG.SHARE_URL)`) e costante `ShareText.shareURL` allineata al web. Default `nil` ⇒ gli esempi congelati §9.2 restano intatti.
2. **`native-ios/Sources/App/GameViewModel.swift`** — `shareText` ora passa `url: ShareText.shareURL`: anteprima nel modal e testo di `ShareLink` coincidono carattere per carattere col web (regola anti-dark-pattern §4.4: mai contenuto aggiunto di nascosto).
3. **`native-ios/Tests/FiloCoreTests/ShareTextTests.swift`** — `testNessunURLMai` → `testNessunaRigaURLSenzaConfig` (url nil/vuoto ⇒ nessuna riga, mai inventare domini) + nuovo `testRigaURLQuandoConfigurata` (il testo TERMINA con l'URL, una sola volta — parità con `share_url_test.js`).

Dopo i fix, **tutte** le verifiche 1.1–1.4 sono state rieseguite da capo: tutto verde (32/32 Swift, 194/194 QA web, smoke, share_url, parità 30 seed, hash identici, YAML/JSON validi, parse puliti).

Non-difetti valutati e lasciati intatti: annuncio VoiceOver vittoria "…hai battuto il Sarto!." (costruzione letterale normativa UX_SPEC §9.5); doppione seed 20300101 in reference.json (entry coerenti fra loro; il riferimento è congelato e non si tocca).

---

## 3. Tabella di parità piattaforme

| Aspetto | Web (`index.html`) | iOS (`native-ios/`) | Backend |
|---|---|---|---|
| Generatore (mulberry32, ordine rng, guardia T≥20) | riferimento normativo | ✅ parità bit-esatta: 310 vettori congelati + 30 seed nuovi indipendenti | — (non esiste **by design**: gioco 100% client-side deterministico, `vercel.json` senza functions) |
| Regole (adiacenza, no-undo, 3 esiti, strappo) | §6 | ✅ `GameEngine` (struct pura, testata) | — |
| Punteggio stelle / 🥇 / streak | §8 | ✅ `Punteggio`/`Statistiche` (test) | — |
| Testo condiviso (incl. riga URL finale) | `buildShareText()` | ✅ `ShareText.build(url:)` — carattere per carattere (dopo fix) | — |
| Persistenza | localStorage `filo.onboarded/stats/today` | ✅ UserDefaults, stesso schema §11.2 | — |
| Microcopy NEURO_SPEC | ✅ (qa_test) | ✅ (campionatura §1.3) | — |
| Data/numero puzzle (EPOCH 2026-08-01) | mezzanotte locale | ✅ `FiloDate` (days_from_civil) | — |

---

## 4. Verificabile solo in CI / su device (con istruzioni)

| Cosa | Perché non qui | Come verificarlo |
|---|---|---|
| Build SwiftUI completa (typecheck di `Sources/App`) | `swiftc -parse` non typechecka; serve SDK iOS (solo macOS) | push su `native-ios/**` → `check-ios-native.yml` esegue XcodeGen + `xcodebuild build` su simulatore. Verde = typecheck ok |
| Inclusione di `reference.json` nel bundle test XcodeGen | comportamento resources di XcodeGen verificabile solo generando il progetto | lo stesso check CI (lo scheme FILO builda `FiloCoreTests`); in caso di failure aggiungere `resources: [Tests/FiloCoreTests/reference.json]` esplicito al target |
| Upload TestFlight (firma cloud, ASC) | richiede secrets e runner macOS | Actions → "Release iOS nativa (TestFlight)" → Run workflow. Se errore 90382: "Retry upload iOS" con `run_number` del run fallito |
| Haptics (`sensoryFeedback`, UINotification/ImpactFeedbackGenerator) | no-op su simulatore | su device: mossa non valida → error haptic; vittoria → success; spezzato/annodato → error; strappo → impact light |
| VoiceOver reale | annunci `AccessibilityNotification` non simulabili qui | su device con VoiceOver: verificare annunci §9.5 (inizio/estensione filo, esiti, vittoria/sconfitta), etichette caselle (riga/colonna/valore/posizione), focus del dialog strappo su [Continua] |
| ShareLink / share sheet | UI di sistema | su device: anteprima nel modal = testo effettivamente incollato in chat, riga URL inclusa una sola volta |
| Cambio giorno a mezzanotte (RF10) | richiede clock reale/scene lifecycle | su device: app aperta oltre mezzanotte (o cambio data nelle Impostazioni) → banner `🧵 C'è un nuovo FILO!` entro 30 s o al ritorno in foreground |
