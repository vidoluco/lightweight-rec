# registra

Registrazione continua della giornata di lavoro, tutta locale e senza abbonamenti:
schermo + microfono → trascrizione → nota archiviata nel vault Obsidian.

Un tasto accende, lo stesso tasto spegne. Allo spegnimento parte da sola la
trascrizione, e la nota compare nel vault con titolo, tag e riassunto decisi
dal contenuto.

## Come funziona

```
Option+R ──► ffmpeg: schermo 1 fps + microfono, HEVC hardware
                 │        un file per ora in ~/Registrazioni  (~110 MB/ora)
                 │        i video oltre 14 giorni si cancellano da soli
Option+R ──► stop │
                 ▼
             whisper-cli (large-v3-turbo, locale) trascrive con i timestamp
                 ▼
             claude -p (haiku) decide titolo, tag e riassunto
                 ▼
             nota nel vault Obsidian, cartella Registrazioni/
             (solo testo: i video restano fuori da iCloud)
```

I timestamp nella trascrizione sono relativi al file video dell'ora
corrispondente: dalla nota si apre il video e si salta al minuto giusto.

## Componenti, tutti gratuiti e open source

| Cosa | Ruolo |
|---|---|
| `registra` (questo repo) | lo script che orchestra tutto |
| [ffmpeg](https://ffmpeg.org) | cattura schermo e microfono |
| [whisper.cpp](https://github.com/ggerganov/whisper.cpp) | trascrizione locale |
| [skhd](https://github.com/koekeishiya/skhd) | lega Option+R allo script |
| [Handy](https://github.com/cjpais/handy) | dettatura push-to-talk, indipendente ma avviata insieme |
| `claude` CLI | titolo, tag e riassunto della nota (unico pezzo non locale) |

## Installazione su un Mac nuovo

```bash
./installa.sh
```

Poi tre permessi, una volta sola, in Impostazioni → Privacy e Sicurezza:

1. **Accessibilità** → aggiungi `/opt/homebrew/bin/skhd`
2. **Registrazione Schermo** → skhd (macOS lo chiede alla prima pressione di Option+R)
3. **Microfono** → skhd (idem)

Dopo ogni permesso concesso il servizio riparte da solo; se non parte,
`skhd --restart-service`.

## Uso

| Gesto | Effetto |
|---|---|
| `Option+R` | accende o spegne, con notifica di conferma |
| `Option+A` (config. in Handy) | dettatura, tenendo premuto |
| `registra stato` | sta girando? quanto spazio? |
| `tail -f ~/Registrazioni/.trascrivi.log` | seguire una trascrizione in corso |

## Audio completo in call (BlackHole)

Con le cuffie, il microfono sente solo te: le voci degli altri escono nelle
cuffie e non passano mai per il mic. Per questo, se BlackHole e' installato,
a ogni avvio lo script crea al volo due dispositivi virtuali:

- **Registra-Out** = uscita attuale (AirPods, casse, quello che c'e' in quel
  momento) + BlackHole: tu senti tutto come prima, e una copia va nel "cavo"
- **Registra-In** = microfono + BlackHole: ffmpeg registra questo, cioe'
  entrambe le voci

Allo stop l'uscita torna quella di prima e i dispositivi spariscono. Senza
BlackHole tutto funziona lo stesso, ma in cuffia si registra solo la tua voce.
Unico effetto collaterale mentre registra: i tasti volume non agiscono
sull'uscita multipla, il volume si regola dall'app della call.

## Cose sapute e volute

- **Il microfono registra anche gli altri.** In call, dillo o spegni.
- Il percorso del vault e' scritto in testa allo script (`VAULT=`): su un Mac
  nuovo va controllato.
- Se dimentichi lo stop e chiudi il Mac: i file gia' chiusi (uno per ora) sono
  salvi, si perde al massimo l'ultima ora; `registra stop` la mattina dopo
  trascrive quello che c'e'.
