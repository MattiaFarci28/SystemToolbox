# System Toolbox per Linux

Analisi, pulizia e manutenzione di Linux, dal terminale o con finestre grafiche.
Pensato per Ubuntu, funziona anche su altre distribuzioni, in WSL e nei container.

## Requisiti

- bash 4 o successivo (presente su ogni distribuzione recente).
- Supporto completo su Ubuntu, Debian e derivate (Kubuntu, Lubuntu, Mint…).
- Supporto base su Fedora, Arch e openSUSE (vedi [Distribuzioni](#distribuzioni)).
- Per le finestre grafiche: `zenity` (`sudo apt install zenity`).

## Avvio

```bash
cd ~/Desktop/SystemToolbox/"Linux Ubuntu"
chmod +x *.sh
./toolbox.sh --dry-run
```

Se il Desktop si chiama `~/Scrivania`, usa quel percorso. Il `chmod` serve una volta sola.

**Non usare `sudo`**: la password viene chiesta da sola, una volta, solo se serve.

### Finestre grafiche

```bash
./toolbox-gui.sh
```

Aprila **da un terminale**: è lì che `sudo` chiede la password.
Aperta dal menu applicazioni, le operazioni che richiedono la password non vengono eseguite.

### Voce nel menu applicazioni

```bash
./installa-scorciatoie.sh
```

Aggiunge la voce **System Toolbox** con il logo, il comando `system-toolbox` e il completamento dei parametri.
Lavora solo nella tua cartella personale. Si toglie con `./installa-scorciatoie.sh --rimuovi`.

## Parametri

| Comando | Effetto |
|---|---|
| `./toolbox.sh --dry-run` | simulazione: non modifica nulla |
| `./toolbox.sh --auto` | analisi rapida + manutenzione consigliata, senza domande |
| `./toolbox.sh --report r.html` | esporta il report (`.html` o `.md`) |
| `./toolbox.sh --json` | riepilogo JSON |
| `./toolbox.sh --config file` | usa un altro file di configurazione |
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
| 5 | Manutenzione rete |
| 6 | Riavvia gestione di rete (la connessione cade per qualche secondo) |
| 7 | Aggiornamenti del sistema |
| 8 | Riparazione e disco |
| 9 | Manutenzione consigliata (3 + DNS) |
| P | Selezione personalizzata |
| L | Percorso della cartella dei log |
| S | Simulazione sì/no |
| 0 | Esci |

## Operazioni

### Pulizia

| Livello | Operazione | Tempo | Note |
|---|---|---|---|
| sicuro | Cache del gestore pacchetti | 20 s | |
| sicuro | Riduci il registro di sistema | 20 s | tiene gli ultimi 14 giorni |
| sicuro | Cache utente | 40 s | `~/.cache` |
| sicuro | Miniature | 15 s | |
| sicuro | Cestino | 15 s | |
| avanzato | Pacchetti non più necessari | 1 min | mostra l'elenco prima |
| avanzato | Revisioni snap superate | 1,5 min | spesso diversi GB |
| avanzato | Kernel vecchi | 1,5 min | non tocca mai quello in uso né il più recente |
| avanzato | Runtime Flatpak inutilizzati | 1 min | |
| avanzato | Spazio di Docker | 1,5 min | solo se sai cosa hai in Docker |
| avanzato | Cache degli strumenti di sviluppo | 1 min | npm, pip, Yarn, Gradle |

### Rete

| Livello | Operazione | Tempo |
|---|---|---|
| sicuro | Svuota la cache DNS | 10 s |
| sicuro | Rinnova indirizzo IP | 30 s |
| avanzato | Riavvia la gestione di rete | 30 s |

### Manutenzione

| Livello | Operazione | Tempo | Note |
|---|---|---|---|
| avanzato | Aggiorna i pacchetti | 10 min | mostra l'elenco prima |
| avanzato | Aggiornamento completo | 15 min | **può rimuovere pacchetti**: le rimozioni sono mostrate a parte |
| avanzato | Aggiorna gli snap | 5 min | |
| avanzato | Aggiorna le app Flatpak | 5 min | |
| avanzato | Ripara i pacchetti danneggiati | 2 min | |
| sicuro | TRIM del disco | 1 min | solo SSD, non è una deframmentazione |
| avanzato | Correggi `pam_lastlog` obsoleto | 10 s | controlla prima e fa una copia di sicurezza |

Durante gli aggiornamenti compare una barra di avanzamento.

### Insiemi predefiniti

| Insieme | Contenuto | Tempo |
|---|---|---|
| Consigliata | pulizia sicura + DNS | ~2 min |
| Pulizia sicura | le 5 voci `[sicuro]` di pulizia | ~2 min |
| Pulizia avanzata | orfani, snap, kernel, Flatpak, cache di sviluppo | ~6 min |
| Manutenzione rete | DNS + rinnovo IP | ~40 s |
| Aggiornamenti | pacchetti, aggiornamento completo, snap, Flatpak | 21–49 min |
| Riparazione e disco | TRIM, riparazione pacchetti, PAM | ~3 min |

Docker si sceglie solo dalla selezione personalizzata (`P`).

## Cosa controlla l'analisi

| Sezione | Rapida | Completa |
|---|:---:|:---:|
| Supporto della distribuzione | ✓ | ✓ |
| Sistema, disco, memoria e swap, processi | ✓ | ✓ |
| Servizi systemd falliti, rete | ✓ | ✓ |
| Tempo di avvio e servizi più lenti | | ✓ |
| Aggiornamenti disponibili e di sicurezza | | ✓ |
| Kernel installati, registro di sistema, snap | | ✓ |
| Salute del disco (SMART), temperature, firewall | | ✓ |
| Servizi da riavviare dopo un aggiornamento (needrestart) | | ✓ |
| Spazio recuperabile | | ✓ |

## Distribuzioni

| | APT | DNF | pacman | zypper |
|---|:---:|:---:|:---:|:---:|
| Pulizia cache pacchetti | ✓ | ✓ | ✓ | ✓ |
| Aggiornamenti | ✓ | ✓ | ✓ | ✓ |
| Rimozione pacchetti orfani | ✓ | ✓ | ✓ | |
| Riparazione pacchetti | ✓ | ✓ | ✓ | ✓ |
| Conteggio aggiornamenti di sicurezza | ✓ | ✓ | | ✓ |
| Rimozione kernel vecchi | ✓ | | | |

Solo APT è stato provato. DNF, pacman e zypper sono scritti ma mai eseguiti.

## Configurazione

Copia `toolbox.conf.esempio` in `toolbox.conf`.

| Chiave | Predefinito | A cosa serve |
|---|---|---|
| `disco_avviso` / `disco_critico` | 80 / 90 | % di disco pieno per avviso e allarme |
| `ram_critica` | 90 | % di RAM in uso per l'allarme |
| `swap_avviso_mb` | 1024 | MB di swap in uso per l'avviso |
| `uptime_avviso_giorni` | 7 | giorni di accensione oltre cui suggerire il riavvio |
| `log_da_conservare` | 15 | quanti log tenere |
| `colori` | auto | `auto`, `si`, `no`, `daltonici` |
| `cornici` | ascii | `utf8` per linee e barre continue |
| `simboli` | ascii | `emoji` per i simboli di stato |
| `avanzamento` | si | barra durante gli aggiornamenti |
| `analisi_aggiornamenti` | si | `no` salta la ricerca degli aggiornamenti |
| `cache_aggiornamenti_ore` | 6 | per quante ore riusare quella ricerca |
| `misura_max_secondi` | 12 | tempo massimo per misurare una cartella |
| `conferme_grafiche` | no | `si` chiede conferma con una finestra |
| `notifica_fine` | si | notifica quando finisce |

Non usate su Linux: `avvii_avviso` (conta il tempo di avvio), `ridimensiona_terminale`, `lingua`.

## Da sapere

- **WSL e container**: kernel, dischi e rete appartengono al sistema che li ospita.
  Le parti che non hanno senso vengono saltate e dichiarate.
- L'aggiornamento completo può rimuovere pacchetti: leggi sempre l'elenco prima di confermare.
- La correzione `pam_lastlog` interviene solo se il modulo manca davvero (Ubuntu 24.04 e successive).

## Collaudo

```bash
bash test/collaudo.sh
```

125 controlli, non toccano il sistema.
Mai eseguiti su una macchina reale: finestre grafiche, voce di menu, needrestart, DNF, pacman, zypper.

## File

```
toolbox.sh               avvio e menu
toolbox-gui.sh           finestre grafiche
installa-scorciatoie.sh  voce nel menu e comando system-toolbox
toolbox.conf.esempio     configurazione d'esempio
icona.png                logo per la voce di menu
lib/                     motore, operazioni, analisi, interfaccia
test/collaudo.sh         suite di collaudo
logs/                    log delle sessioni
```
