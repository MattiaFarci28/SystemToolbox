# System Toolbox per macOS

Analisi, pulizia e manutenzione di macOS, dal Terminale o come app nel Dock.

## Requisiti

- macOS da 10.13 High Sierra a macOS 26, Intel o Apple Silicon.
- Nessuna installazione: usa solo strumenti già presenti in macOS.
- Un account amministratore per le operazioni che lo richiedono.

## Avvio

```bash
cd ~/percorso/SystemToolbox/macOS
chmod +x toolbox.command crea-app.command
./toolbox.command --dry-run
```

Il `chmod` serve una volta sola. Dopo, `toolbox.command` si apre anche con doppio clic dal Finder.

**Non usare `sudo`**: la password viene chiesta da sola, una volta, solo se serve.

### Come app nel Dock

```bash
./crea-app.command
```

Crea `System Toolbox.app` con il logo, da trascinare nel Dock.
Se sposti la cartella, rilancia il comando.

## Parametri

| Comando | Effetto |
|---|---|
| `./toolbox.command --dry-run` | simulazione: non modifica nulla |
| `./toolbox.command --auto` | analisi rapida + manutenzione consigliata, senza domande |
| `./toolbox.command --report r.html` | esporta il report (`.html` o `.md`) |
| `./toolbox.command --json` | riepilogo JSON |
| `./toolbox.command --config file` | usa un altro file di configurazione |
| `--daltonici` / `--no-color` | colori per daltonici / senza colori |
| `--emoji` | simboli di stato con le emoji |
| `--versione` / `--help` | versione / elenco dei parametri |

## Menu

| Tasto | Voce |
|---|---|
| 1 | Analisi completa |
| 2 | Analisi rapida |
| 3 | Pulizia sicura |
| 4 | Pulizia avanzata |
| 5 | Manutenzione rete (nessun riavvio) |
| 6 | Reset configurazione di rete (**richiede riavvio**) |
| 7 | Manutenzione sistema |
| 8 | Manutenzione consigliata (3 + DNS) |
| B | Backup di iPhone e iPad |
| P | Selezione personalizzata |
| L | Apri la cartella dei log |
| S | Simulazione sì/no |
| 0 | Esci |

## Operazioni

### Pulizia

| Livello | Operazione | Tempo | Note |
|---|---|---|---|
| sicuro | Cestini (utente e sistema) | 20 s | |
| sicuro | Crash report e diagnostica | 10 s | |
| sicuro | Log delle applicazioni | 15 s | non tocca il registro di sistema |
| sicuro | Cache dei browser | 40 s | solo cache: non cronologia, password o preferiti |
| sicuro | Cache anteprime QuickLook | 15 s | |
| sicuro | Allegati scaricati di Mail | 20 s | i messaggi restano |
| avanzato | Cache utente | 1 min | chiudi prima le applicazioni |
| avanzato | Cache di sistema | 40 s | |
| avanzato | Snapshot locali di Time Machine | 1,5 min | spesso libera molto spazio |
| avanzato | Xcode: DerivedData e simulatori | 2 min | |
| avanzato | Cache degli strumenti di sviluppo | 1,5 min | npm, pip, Yarn, CocoaPods |
| avanzato | Cache di Homebrew | 1 min | |
| avanzato | Spazio di Docker | 1,5 min | solo se sai cosa hai in Docker |
| avanzato | Cache dei font | 30 s | |

### Rete

| Livello | Operazione | Tempo | Note |
|---|---|---|---|
| sicuro | Svuota la cache DNS | 10 s | |
| sicuro | Rinnova indirizzo IP | 25 s | |
| riavvio | Reset preferenze di rete | 20 s | le reti Wi-Fi salvate vanno reinserite |

### Manutenzione

| Livello | Operazione | Tempo | Note |
|---|---|---|---|
| sicuro | Ricostruisci il database "Apri con" | 1 min | toglie i doppioni dal menu |
| sicuro | Verifica il volume di avvio | 3 min | solo controllo |
| avanzato | Reindicizza Spotlight | 1 min | il Mac rallenta per alcune ore |
| avanzato | Installa gli aggiornamenti di macOS | 20 min | può riavviare |
| SCONSIG. | Libera la memoria (purge) | 20 s | **peggiora** le prestazioni |

### Insiemi predefiniti

| Insieme | Contenuto | Tempo |
|---|---|---|
| Consigliata | pulizia sicura + DNS | ~2 min |
| Pulizia sicura | le 6 voci `[sicuro]` | ~2 min |
| Pulizia avanzata | le 7 voci `[avanzato]`, Docker escluso | ~8 min |
| Manutenzione rete | DNS + rinnovo IP | ~35 s |
| Manutenzione sistema | "Apri con", verifica disco, Spotlight, aggiornamenti | 15–35 min |

Docker e purge si scelgono solo dalla selezione personalizzata (`P`).

### Backup di iPhone e iPad (tasto B)

Elenca i backup con nome del dispositivo, data e dimensione, e cancella solo quelli che scegli.
**La cancellazione è definitiva**: non passa dal Cestino.

## Cosa controlla l'analisi

| Sezione | Rapida | Completa |
|---|:---:|:---:|
| Supporto di macOS | ✓ | ✓ |
| Sistema, disco (SSD o meccanico), memoria e swap, processi | ✓ | ✓ |
| Sicurezza: SIP, FileVault, Gatekeeper, firewall | ✓ | ✓ |
| Rete | ✓ | ✓ |
| Temperatura, avvio automatico, snapshot di Time Machine | | ✓ |
| Spotlight, connettività, aggiornamenti di macOS | | ✓ |
| Spazio recuperabile: backup iOS, Xcode, cache, Download | | ✓ |

Su un Mac contano soprattutto due cose: lo **swap in uso** (oltre 1 GB il Mac sta usando il disco
come memoria) e il **tipo di disco** (un disco meccanico rallenta più di qualsiasi altra cosa).

## Configurazione

Copia `toolbox.conf.esempio` in `toolbox.conf`.

| Chiave | Predefinito | A cosa serve |
|---|---|---|
| `disco_avviso` / `disco_critico` | 80 / 90 | % di disco pieno per avviso e allarme |
| `swap_avviso_mb` | 1024 | MB di swap in uso per l'avviso |
| `avvii_avviso` | 12 | elementi all'avvio oltre cui avvisare |
| `uptime_avviso_giorni` | 7 | giorni di accensione oltre cui suggerire il riavvio |
| `log_da_conservare` | 15 | quanti log tenere |
| `colori` | auto | `auto`, `si`, `no`, `daltonici` |
| `cornici` | ascii | `utf8` per linee e barre continue |
| `simboli` | ascii | `emoji` per i simboli di stato |
| `analisi_aggiornamenti` | si | `no` salta la ricerca degli aggiornamenti (la parte più lenta) |
| `cache_aggiornamenti_ore` | 6 | per quante ore riusare quella ricerca |
| `misura_max_secondi` | 12 | tempo massimo per misurare una cartella |
| `conferme_grafiche` | no | `si` chiede conferma con una finestra |
| `notifica_fine` | si | notifica quando finisce |
| `ridimensiona_terminale` | no | `si` ridimensiona la finestra all'avvio |

Non usate su macOS: `ram_critica` (conta lo swap), `avanzamento` (esiste solo su Linux), `lingua`.

## Da sapere

- **Perché non `sudo`**: sotto `sudo` la cartella personale diventa quella dell'amministratore,
  e la pulizia lavorerebbe sui file sbagliati.
- Le cartelle protette da SIP non si possono cancellare: vengono saltate e segnalate.
- Su APFS lo spazio liberato può comparire più tardi, quando scadono gli snapshot.
- Se macOS blocca il file perché "scaricato da Internet": clic destro, **Apri**.

## Collaudo

```bash
bash test/collaudo.sh
```

104 controlli, non toccano il sistema. Verificano la logica e la lettura di output reali di Catalina.
I comandi propri di macOS (`tmutil`, `diskutil`, `osascript`, la creazione dell'app) **non sono mai stati eseguiti**.

## File

```
toolbox.command        avvio e menu
crea-app.command       crea l'app per il Dock
toolbox.conf.esempio   configurazione d'esempio
icona.png              logo per l'app
lib/                   motore, operazioni, analisi, interfaccia
test/collaudo.sh       suite di collaudo
logs/                  log delle sessioni
```