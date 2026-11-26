# Prove su computer veri

Il collaudo automatico su GitHub esegue già davvero, su Windows, macOS e Ubuntu, le operazioni
di pulizia e manutenzione, l'analisi completa e la modalità automatica. Su Fedora e Arch prova
anche il gestore pacchetti vero.

Qui resta solo quello che GitHub non può provare: finestre e clic, password e UAC, rete,
punto di ripristino, i tuoi dispositivi e i tuoi dati.

Spunta la colonna ✓ se va come scritto. **Se qualcosa va diversamente**, annota:

1. il numero della prova;
2. il messaggio esatto, o una foto dello schermo;
3. il file di log più recente nella cartella `logs/` della versione che stai provando.

---

## Windows

Apri `Windows\Toolbox.bat` con doppio clic.

| # | Cosa fai | Cosa deve succedere | ✓ |
|---|---|---|:---:|
| W1 | Apri lo strumento | compare la richiesta UAC; se la rifiuti, lo strumento lo dice e si ferma | |
| W2 | **Analisi completa** | la percentuale del disco è quella di Esplora risorse (clic destro su C: → Proprietà) | |
| W3 | Seleziona **Crea punto di ripristino** → **Esegui**, poi rifallo subito | la prima volta "creato"; la seconda dice che ne esiste già uno nelle ultime 24 ore (non "creato") | |
| W4 | Seleziona 3-4 operazioni sicure → **Esegui** → subito **Interrompi** | finisce l'operazione in corso, poi si ferma: "le operazioni rimanenti non sono state eseguite" | |
| W5 | Rilancia la stessa selezione e, durante il lavoro, chiudi la finestra con la X | chiede conferma; la finestra **non** si blocca; si chiude da sola appena finisce l'operazione in corso | |
| W6 | Durante un'**analisi** guarda il pulsante **Interrompi** | è grigio (non cliccabile) | |
| W7 | Seleziona **Rete leggera** → **Esegui** | la rete cade per un istante e torna; esito OK | |
| W8 | **Programmi all'avvio**: spegni un programma poco importante, poi riaccendilo | in Gestione attività → Avvio lo stato cambia di conseguenza | |
| W9 | Con **Simulazione** spuntata, seleziona **Aggiorna le applicazioni (winget)** → **Esegui** | compare l'elenco delle applicazioni da aggiornare, senza installare niente | |

---

## macOS

Nel Terminale, dentro la cartella `macOS`.

| # | Cosa fai | Cosa deve succedere | ✓ |
|---|---|---|:---:|
| M1 | `./toolbox.command` → **2** (analisi rapida) | la percentuale del disco è vicina a quella di Impostazioni di Sistema → Generali → Archiviazione (non un valore bassissimo tipo 2%) | |
| M2 | **3** (pulizia sicura) | chiede la password una volta sola; esito OK o PARZIALE | |
| M3 | **5** (manutenzione rete) | il rinnovo IP funziona in Wi-Fi o Ethernet normale. Con indirizzo impostato a mano deve dire "non usa DHCP: non toccato" | |
| M4 | **B** (backup di iPhone e iPad) | elenca i backup con nome, data e dimensione; premi INVIO senza scegliere niente | |
| M5 | **V** (programmi all'avvio) | elenca agenti e servizi di terze parti; premi INVIO senza scegliere niente | |
| M6 | `./crea-app.command`, poi apri **System Toolbox.app** | l'app compare con il logo e apre il Terminale con il menu | |
| M7 | Esporta i manuali dei comandi Apple con il comando che ti ho dato in chat, e copia la cartella `man-macos` nel progetto sul PC | ci sono circa 30 file `.txt` | |

---

## Ubuntu e Lubuntu

Da un terminale, nella cartella `Linux Ubuntu`. Ripeti la sezione su entrambi.

| # | Cosa fai | Cosa deve succedere | ✓ |
|---|---|---|:---:|
| L1 | `./toolbox.sh` → **3** (pulizia sicura) | chiede la password una volta sola; esito OK o PARZIALE | |
| L2 | **5** (manutenzione rete) | la rete cade per un paio di secondi e torna; compare "Indirizzo attivo" | |
| L3 | `./toolbox-gui.sh` → analisi rapida | la finestra mostra il risultato; il nome del sistema in alto si legge bene | |
| L4 | Dalla finestra grafica avvia 3-4 operazioni sicure e chiudi la finestra di avanzamento con la X | il lavoro si ferma dopo l'operazione in corso; il riepilogo mostra quelle eseguite | |
| L5 | `./installa-scorciatoie.sh`, poi cerca **System Toolbox** nel menu applicazioni | la voce c'è, con il logo, e si apre | |
