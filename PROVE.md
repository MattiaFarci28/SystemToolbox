# Prove su computer veri

Una sezione per sistema. Ogni prova dice **cosa fare** e **cosa deve succedere**.
Spunta la colonna ✓ se va come scritto.

**Se qualcosa va diversamente**, annota:

1. il numero della prova;
2. il messaggio esatto, o una foto dello schermo;
3. il file di log più recente nella cartella `logs/` della versione che stai provando.

Fai sempre prima le prove in **simulazione**: non modificano nulla.

---

## Windows

Apri `Windows\Toolbox.bat` con doppio clic e accetta la richiesta UAC.

| # | Cosa fai | Cosa deve succedere | ✓ |
|---|---|---|:---:|
| W1 | Spunta **Simulazione** in basso | resta spuntata durante tutte le prove W2–W5 | |
| W2 | **Analisi rapida** | in meno di un minuto compare l'esito; nessun errore rosso inatteso | |
| W3 | **Analisi completa** | la percentuale del disco è quella di Esplora risorse (clic destro su C: → Proprietà); in fondo "Novità dall'ultima analisi" | |
| W4 | Seleziona **Pulizia sicura** → **Esegui** | ogni voce dice "eliminabili (simulazione)"; nessun file cancellato | |
| W5 | **Esporta report**, salvalo come `.html` e aprilo | la pagina si legge bene; nessun pezzo di codice visibile | |
| W6 | Togli **Simulazione**, seleziona **Pulizia sicura** → **Esegui** | esito OK o PARZIALE; i file in uso compaiono come "saltati", non come errori | |
| W7 | Seleziona **Crea punto di ripristino** → **Esegui**, poi rifallo subito | la prima volta "creato"; la seconda dice che ne esiste già uno nelle ultime 24 ore (non "creato") | |
| W8 | Seleziona 3-4 operazioni sicure → **Esegui** → subito **Interrompi** | finisce l'operazione in corso, poi si ferma: "le operazioni rimanenti non sono state eseguite" | |
| W9 | Rilancia la stessa selezione e, durante il lavoro, chiudi la finestra con la X | chiede conferma; la finestra **non** si blocca; si chiude da sola appena finisce l'operazione in corso | |
| W10 | Durante un'**analisi** guarda il pulsante **Interrompi** | è grigio (non cliccabile) | |
| W11 | **Programmi all'avvio**: spegni un programma poco importante, poi riaccendilo | in Gestione attività → Avvio lo stato cambia di conseguenza | |
| W12 | Seleziona **Aggiorna le applicazioni (winget)** con Simulazione attiva | compare l'elenco delle applicazioni da aggiornare, senza installare niente | |
| W13 | In PowerShell: `.\Toolbox.bat -Auto -DryRun -Report prova.html` dalla cartella `Windows` | finisce da solo, senza domande; crea `prova.html` | |

---

## macOS

Nel Terminale, dentro la cartella `macOS`.

| # | Cosa fai | Cosa deve succedere | ✓ |
|---|---|---|:---:|
| M1 | `./toolbox.command --dry-run` → **2** (analisi rapida) | esito senza errori inattesi | |
| M2 | **1** (analisi completa) | la percentuale del disco è vicina a quella di Impostazioni di Sistema → Generali → Archiviazione (non un valore bassissimo tipo 2%) | |
| M3 | **3** (pulizia sicura), sempre in simulazione | ogni voce dice "eliminabili (simulazione)" | |
| M4 | **B** (backup di iPhone e iPad) | elenca i backup con nome, data e dimensione; premi INVIO senza scegliere niente | |
| M5 | **V** (programmi all'avvio) | elenca agenti e servizi di terze parti; premi INVIO senza scegliere niente | |
| M6 | Esci, poi `./toolbox.command` (senza simulazione) → **3** | chiede la password una volta sola; esito OK o PARZIALE; le cartelle protette risultano "saltate" | |
| M7 | **5** (manutenzione rete) | DNS svuotato; il rinnovo IP funziona in Wi-Fi o Ethernet normale. Con indirizzo impostato a mano deve dire "non usa DHCP: non toccato" | |
| M8 | `./toolbox.command --auto --dry-run --report prova.html` | finisce da solo; crea `prova.html`, che si apre bene nel browser | |
| M9 | `./crea-app.command`, poi apri **System Toolbox.app** | l'app compare con il logo e apre il Terminale con il menu | |
| M10 | Esporta i manuali dei comandi Apple con il comando che ti ho dato in chat, e copia la cartella `man-macos` nel progetto sul PC | ci sono circa 30 file `.txt` | |

---

## Ubuntu e Lubuntu

Da un terminale, nella cartella `Linux Ubuntu`. Ripeti la sezione su entrambi.

| # | Cosa fai | Cosa deve succedere | ✓ |
|---|---|---|:---:|
| L1 | `./toolbox.sh --dry-run` → **2** (analisi rapida) | esito senza errori inattesi | |
| L2 | **1** (analisi completa) | percentuale del disco uguale a quella di `df -h /`; in fondo "Novità dall'ultima analisi" | |
| L3 | **3** (pulizia sicura), in simulazione | ogni voce dice "eliminabili (simulazione)" | |
| L4 | **4** (pulizia avanzata), in simulazione | "Pacchetti non più necessari" mostra un elenco, o dice che non ce ne sono, e corrisponde a `apt autoremove --dry-run`; i kernel elencati non includono quello in uso (`uname -r`) | |
| L5 | Esci, poi `./toolbox.sh` (senza simulazione) → **3** | chiede la password una volta sola; esito OK o PARZIALE | |
| L6 | **8** (riparazione e disco) | "Ripara i pacchetti" dice "Nessuna dipendenza rotta rimasta"; non rimuove niente. "pam_lastlog" interviene solo se il modulo manca davvero, e in quel caso indica dove ha salvato la copia | |
| L7 | **5** (manutenzione rete) | la rete cade per un paio di secondi e torna; compare "Indirizzo attivo" | |
| L8 | **7** (aggiornamenti) | mostra l'elenco prima di installare; alla fine esito OK | |
| L9 | `./toolbox-gui.sh` → analisi rapida | la finestra mostra il risultato; il nome del sistema in alto si legge bene | |
| L10 | Dalla finestra grafica avvia 3-4 operazioni sicure e chiudi la finestra di avanzamento con la X | il lavoro si ferma dopo l'operazione in corso; il riepilogo mostra quelle eseguite | |
| L11 | `./toolbox.sh --auto --dry-run --report prova.html` | finisce da solo; crea `prova.html`, che si apre bene nel browser | |

---

## Fedora e Arch

Non serve un computer: su GitHub ogni modifica viene provata in container Fedora e Arch, con il
vero `dnf` e il vero `pacman` (indice, elenchi, pulizia, riparazione, aggiornamento).
