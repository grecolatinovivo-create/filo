# FILO — il puzzle quotidiano 🧵

FILO è un daily puzzle game: ogni giorno una griglia 5×5 di numeri, un totale
del giorno da raggiungere e **tre fili** per cucire un percorso di caselle
adiacenti. Chi arriva esatto al totale vince; chi lo supera spezza il filo.
Alla fine si confronta il proprio percorso con quello del **Sarto** (la
soluzione ottima) e si condivide il risultato in emoji, stile Wordle.
Il puzzle è deterministico dalla data: tutti giocano la stessa griglia, senza
alcun backend.

- **Zero dipendenze, zero rete, zero backend**: un solo file HTML con CSS e JS inline.
- **Salvataggio locale** in `localStorage` (partita del giorno, statistiche, streak).
- **Nuovo puzzle a mezzanotte** locale, seed derivato dalla data.

## Struttura del monorepo

| Percorso | Contenuto |
| --- | --- |
| `/index.html` | Il gioco web completo (singolo file, tutto inline) |
| `/vercel.json` | Configurazione del deploy statico su Vercel (header di sicurezza, cache) |
| `/native-ios/` | App nativa SwiftUI (stessa logica di gioco, parità di puzzle via seed) |
| `/.github/workflows/` | CI: build e distribuzione TestFlight dell'app iOS |

## Giocare in locale

Nessuna build, nessun server: basta aprire il file nel browser.

```bash
open index.html        # macOS
xdg-open index.html    # Linux
```

## Deploy su Vercel

Il sito è 100% statico: **nessuna build e nessuna funzione serverless**.

**Via GitHub (consigliato)**
1. Su [vercel.com](https://vercel.com) → *Add New → Project* → importa questo repository.
2. **Root Directory**: `/` (la radice del repo).
3. **Framework Preset**: `Other`. Lascia vuoti Build Command e Output Directory.
4. Deploy: ogni push su `main` pubblica automaticamente.

**Via CLI**

```bash
npm i -g vercel
vercel --prod
```

`vercel.json` imposta `cleanUrls`, gli header di sicurezza
(CSP compatibile con il codice inline, `nosniff`, `Referrer-Policy: no-referrer`,
`Permissions-Policy` minimale) e `Cache-Control: no-cache` su `index.html`,
così ogni deploy è servito subito senza cache stantia.

> **Dominio**: se il dominio finale è diverso da `https://filo-game.vercel.app`,
> aggiorna la costante `SHARE_URL` nella sezione CONFIG di `index.html`
> (è l'URL aggiunto come ultima riga del testo condiviso) e il meta tag `og:url`.

## CI iOS

Il workflow in `.github/workflows/` compila l'app SwiftUI di `native-ios/`
(progetto generato con XcodeGen su runner macOS, firma via App Store Connect API)
e carica la build su TestFlight. Nessun Mac locale necessario.

Secrets richiesti nel repository GitHub:

| Secret | Contenuto |
| --- | --- |
| `ASC_API_KEY_P8` | Contenuto del file `.p8` della chiave API di App Store Connect |
| `ASC_KEY_ID` | Key ID della chiave API |
| `ASC_ISSUER_ID` | Issuer ID dell'account App Store Connect |
| `APPLE_TEAM_ID` | Team ID dell'account sviluppatore Apple |

## Note

- La condivisione web include l'URL come ultima riga solo se `SHARE_URL` è
  definita; su iOS l'app usa `ShareLink` e allega l'URL separatamente.
- La suite di test (Playwright: `qa_test.js`, `smoke.js`) vive nel workspace di
  sviluppo e verifica regole di gioco, determinismo, share text e accessibilità.
