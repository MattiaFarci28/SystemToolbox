# System Toolbox per Windows

Analisi, pulizia e manutenzione di Windows, con finestra grafica o menu testuale.

## Requisiti

- Windows 10 o 11. PowerShell 5.1 è già incluso.
- Un account amministratore: all'avvio compare la richiesta UAC.

## Avvio

| File | Cosa apre |
|---|---|
| `Toolbox.bat` | la finestra grafica (doppio clic) |
| `Toolbox-Console.bat` | il menu testuale, con le stesse funzioni |

Se rifiuti la richiesta UAC lo strumento lo dice e si ferma.

## Parametri

| Comando | Effetto |
|---|---|
| `Toolbox.bat -DryRun` | simulazione: non modifica nulla |
| `Toolbox.bat -Console` | menu testuale |
| `Toolbox.bat -Auto` | analisi rapida + pulizia sicura + rete leggera, senza domande |
| `Toolbox.bat -Report r.html` | esporta il report (`.html` o `.md`) |
| `Toolbox.bat -Json` | riepilogo JSON |
| `Toolbox.bat -Config file.conf` | usa un altro file di configurazione |
| `Toolbox.bat -Daltonici` / `-NoColor` | colori per daltonici / senza colori |
| `Toolbox.bat -Versione` | mostra la versione |

I parametri si possono combinare, per esempio `-Auto -DryRun`.

## La finestra grafica

- **A sinistra** le operazioni da spuntare, con livello di rischio e tempo stimato.
  In alto la casella di ricerca e i pulsanti di selezione rapida.
- **A destra** la descrizione della selezione e, durante il lavoro, l'output con il tempo rimanente.
- **Doppio clic** su un'operazione: la esegue da sola, dopo conferma.
- **Interrompi** si ferma alla fine dell'operazione in corso, mai a metà.
- **Esporta report** salva il contenuto del pannello.

La finestra ricorda dimensione e ultima selezione, e segue il tema chiaro o scuro di Windows.

### Punto di ripristino

| Selezione | Consiglio |
|---|---|
| solo voci `[sicuro]` | non serve |
| con voci `[avanzato]` o `[riavvio]` | consigliato |

## Menu testuale

| Tasto | Voce |
|---|---|
| 1 | Analisi completa |
| 2 | Analisi rapida |
| 3 | Pulizia sicura |
| 4 | Pulizia avanzata |
| 5 | Rete: refresh leggero (nessun riavvio) |
| 6 | Rete: reset completo (**richiede riavvio**) |
| 7 | Integrità del sistema: punto di ripristino, TRIM, SFC, DISM |
| 8 | Manutenzione consigliata (3 + 5) |
| 9 | Selezione personalizzata |
| L | Apri la cartella dei log |
| S | Simulazione sì/no |
| 0 | Esci |

## Operazioni

### Pulizia

| Livello | Operazione | Tempo | Note |
|---|---|---|---|
| sicuro | Temp utente corrente | 20 s | |
| sicuro | Temp di sistema | 15 s | `C:\Windows\Temp` |
| sicuro | Temp e cache di tutti i profili | 30 s | esclusi i profili di servizio |
| sicuro | Cestino (tutti i dischi) | 15 s | |
| sicuro | Segnalazioni errori (WER) | 5 s | |
| sicuro | Dump di crash e minidump | 5 s | |
| sicuro | Cache Delivery Optimization | 10 s | |
| avanzato | Cache dei font | 20 s | ferma per pochi secondi il servizio FontCache |
| avanzato | Cache dei browser | 45 s | solo cache: non cronologia, password o preferiti |
| avanzato | Cache delle applicazioni | 1 min | Teams, Discord, Spotify, app dello Store |
| avanzato | Cache degli strumenti di sviluppo | 1,5 min | npm, pip, Yarn, NuGet, Gradle |
| avanzato | Cache miniature e icone | 25 s | riavvia Esplora risorse |
| avanzato | Cache di Windows Update | 1 min | |
| avanzato | Installazione precedente (Windows.old) | 6–14 min | toglie la possibilità di tornare alla versione precedente |
| avanzato | Compattazione componenti (DISM) | 9–21 min | non interrompibile |
| SCONSIG. | Prefetch | 5 s | **rallenta** i primi avvii |

### Rete

| Livello | Operazione | Tempo |
|---|---|---|
| sicuro | Svuota cache DNS | immediato |
| sicuro | Svuota cache ARP | immediato |
| sicuro | Rinnova indirizzo IP | 25 s |
| sicuro | Registrazione DNS | 5 s |
| riavvio | Reset Winsock | immediato |
| riavvio | Reset TCP/IP (azzera IP statici) | 10 s |
| riavvio | Reset IPv6 | 10 s |

### Manutenzione

| Livello | Operazione | Tempo | Note |
|---|---|---|---|
| sicuro | Crea punto di ripristino | 50 s | |
| sicuro | Ottimizzazione unità (TRIM) | 1,5 min | solo SSD, non è una deframmentazione |
| avanzato | Verifica file di sistema (SFC) | 9–21 min | |
| avanzato | Riparazione immagine (DISM) | 12–28 min | serve Internet |

### Insiemi predefiniti

| Insieme | Contenuto | Tempo |
|---|---|---|
| Consigliata | pulizia sicura + rete leggera | ~2 min |
| Pulizia sicura | le 7 voci `[sicuro]` di pulizia | ~2 min |
| Pulizia avanzata | le 8 voci `[avanzato]` di pulizia | 18–42 min |
| Rete leggera | DNS, ARP, IP, registrazione DNS | ~40 s |
| Rete reset | Winsock, TCP/IP, IPv6 | ~25 s + riavvio |
| Manutenzione | punto di ripristino, TRIM, SFC, DISM | 22–52 min |

Usa **Rete leggera** di routine. **Rete reset** serve solo quando la connessione non funziona.

## Cosa controlla l'analisi

| Sezione | Rapida | Completa |
|---|:---:|:---:|
| Supporto di Windows (aggiornamenti di sicurezza ancora attivi) | ✓ | ✓ |
| Sistema, disco, memoria, processi, servizi | ✓ | ✓ |
| Sicurezza: Defender, firewall, crittografia, UAC | ✓ | ✓ |
| Batteria, rete, riavvio in sospeso | ✓ | ✓ |
| Alimentazione, salute dei dischi (SMART), connettività | | ✓ |
| Aggiornamenti di Windows, programmi all'avvio | | ✓ |
| Punti di ripristino, driver con errori, manutenzione automatica | | ✓ |
| Spazio recuperabile, errori di sistema, eventi del disco | | ✓ |

Alla fine, **Cosa merita attenzione** elenca solo ciò che richiede una scelta.

## Configurazione

Copia `Toolbox.conf.esempio` in `Toolbox.conf`.

| Chiave | Predefinito | A cosa serve |
|---|---|---|
| `disco_avviso` / `disco_critico` | 80 / 90 | % di disco pieno per avviso e allarme |
| `ram_critica` | 90 | % di RAM in uso per l'allarme |
| `swap_avviso_mb` | 1024 | MB di file di paging in uso per l'avviso |
| `avvii_avviso` | 12 | programmi all'avvio oltre cui avvisare |
| `uptime_avviso_giorni` | 7 | giorni di accensione oltre cui suggerire il riavvio |
| `log_da_conservare` | 15 | quanti log tenere |
| `analisi_aggiornamenti` | si | `no` salta la ricerca degli aggiornamenti (la parte più lenta) |
| `colori` | auto | `auto`, `si`, `no`, `daltonici` |
| `tema` | auto | `auto`, `chiaro`, `scuro` |
| `lingua` | it | non usata: per ora esiste solo l'italiano |

## Da sapere

- Se parte in un PowerShell a 32 bit si riavvia da solo a 64 bit, mantenendo tutti i parametri.
- I servizi fermati da un'operazione vengono riportati allo stato di prima.
- Le conferme arrivano sempre prima di iniziare, mai a metà lavoro.

## Collaudo

```bash
powershell -ExecutionPolicy Bypass -File "test\Collaudo.ps1"
```

57 controlli, non toccano il sistema.
Mai eseguiti dal vero, solo in simulazione: reset di rete, SFC, DISM, punto di ripristino, Windows.old.

## File

```
Toolbox.bat            avvio grafico
Toolbox-Console.bat    avvio con menu testuale
Toolbox.ps1            menu e orchestrazione
Toolbox.conf.esempio   configurazione d'esempio
icona.ico              icona della finestra
lib\                   motore, operazioni, analisi, interfacce
test\Collaudo.ps1      suite di collaudo
logs\                  log delle sessioni
```
