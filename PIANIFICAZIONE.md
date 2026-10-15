# Esecuzione automatica

Come far partire System Toolbox **da solo** senza doverti ricordare di lanciarlo.

## Cosa fa quando parte da solo

Usa la modalità automatica (`--auto`, su Windows `-Auto`):

1. analisi rapida;
2. pulizia sicura e svuotamento della cache DNS
   (su Windows anche rinnovo dell'indirizzo IP, che fa cadere la rete per un istante);
3. salva un report e termina.

Non fa domande, quindi esegue solo operazioni `[sicuro]`.
Non installa aggiornamenti e non tocca niente di rischioso.

Per sapere com'è andata, apri il report o guarda il codice di uscita:
`0` tutto in ordine, `1` avvisi, `2` problemi.

> **Prima di pianificare**, lancia lo stesso comando a mano con `--dry-run` e controlla che funzioni.

## Windows

Apri il **Prompt dei comandi come amministratore** e incolla questa riga, sostituendo il percorso:

```bash
schtasks /create /tn "System Toolbox" /sc weekly /d SUN /st 10:00 /rl highest /f /tr "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"C:\percorso\SystemToolbox\Windows\Toolbox.ps1\" -Auto -Console -Report \"C:\percorso\SystemToolbox\Windows\logs\ultimo.html\""
```

Parte ogni domenica alle 10:00 e salva il report in `logs\ultimo.html`.

| Per | Comando |
|---|---|
| provarlo subito | `schtasks /run /tn "System Toolbox"` |
| vederne lo stato | `schtasks /query /tn "System Toolbox"` |
| toglierlo | `schtasks /delete /tn "System Toolbox" /f` |

## macOS

1. Crea il file `~/Library/LaunchAgents/local.systemtoolbox.plist` con questo contenuto
   (sostituisci `TUONOME` e il percorso):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>local.systemtoolbox</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>/Users/TUONOME/SystemToolbox/macOS/toolbox.command</string>
    <string>--auto</string>
    <string>--report</string>
    <string>/Users/TUONOME/SystemToolbox/macOS/logs/ultimo.html</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Weekday</key><integer>0</integer>
    <key>Hour</key><integer>10</integer>
    <key>Minute</key><integer>0</integer>
  </dict>
</dict>
</plist>
```

2. Attivalo:

```bash
launchctl load ~/Library/LaunchAgents/local.systemtoolbox.plist
```

| Per | Comando |
|---|---|
| vederne lo stato | `launchctl list \| grep systemtoolbox` |
| toglierlo | `launchctl unload ~/Library/LaunchAgents/local.systemtoolbox.plist` |

## Linux

Il modo più semplice è `cron`. Apri l'elenco delle attività:

```bash
crontab -e
```

e aggiungi in fondo questa riga, sostituendo il percorso:

```
0 10 * * 0 /bin/bash "/home/TUONOME/Desktop/SystemToolbox/Linux Ubuntu/toolbox.sh" --auto --report /home/TUONOME/ultimo.html
```

Parte ogni domenica alle 10:00. Le virgolette attorno al percorso servono per lo spazio in `Linux Ubuntu`.

| Per | Comando |
|---|---|
| vedere le attività | `crontab -l` |
| toglierla | `crontab -e` e cancella la riga |

## Da sapere

- Senza nessuno davanti allo schermo non si può inserire la password: su macOS e Linux
  le operazioni che la richiedono vengono saltate e il report lo dice.
  L'analisi e la pulizia dell'utente funzionano normalmente.
- Il computer deve essere acceso all'orario scelto. Se è spento, l'esecuzione salta a quella dopo.
- Lo strumento confronta ogni esecuzione con la precedente: nel report vedi quanto spazio è cambiato.
