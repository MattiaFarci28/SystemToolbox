# Fonti

Ogni comando di sistema usato da System Toolbox va verificato su documentazione **ufficiale**:
quella del produttore del sistema o del progetto che sviluppa il comando. Niente blog né forum.

Qui c'è, per ogni comando, la pagina su cui è stato controllato.

| Simbolo | Significato |
|---|---|
| ✓ | verificato: il codice lo usa come dice la documentazione |
| ✎ | verificato e corretto: il codice è stato cambiato per seguire la documentazione |
| ⚠ | funziona, ma nessuna documentazione ufficiale lo descrive |
| … | ancora da verificare |

## Linux

### Pacchetti

| Comando | Uso | Stato | Fonte |
|---|---|:---:|---|
| `apt-get -s` | anteprima di cosa verrebbe installato o rimosso | ✎ | [apt-get(8)](https://manpages.ubuntu.com/manpages/noble/en/man8/apt-get.8.html) |
| `apt-get upgrade` | aggiornamento che non rimuove mai pacchetti | ✓ | [apt-get(8)](https://manpages.ubuntu.com/manpages/noble/en/man8/apt-get.8.html) |
| `apt-get full-upgrade` | aggiornamento completo, rimozioni mostrate prima | ✎ | [apt-get(8)](https://manpages.ubuntu.com/manpages/noble/en/man8/apt-get.8.html) |
| `apt-get autoremove --purge` | pacchetti non più necessari | ✎ | [apt-get(8)](https://manpages.ubuntu.com/manpages/noble/en/man8/apt-get.8.html) |
| `apt-get purge` | kernel vecchi | ✎ | [apt-get(8)](https://manpages.ubuntu.com/manpages/noble/en/man8/apt-get.8.html) |
| `apt-get --fix-broken install` | riparazione | ✎ | [apt-get(8)](https://manpages.ubuntu.com/manpages/noble/en/man8/apt-get.8.html) |
| `apt-get clean` / `autoclean` | cache dei pacchetti | ✓ | [apt-get(8)](https://manpages.ubuntu.com/manpages/noble/en/man8/apt-get.8.html) |
| `dpkg --configure -a` | completa le installazioni interrotte | ✓ | [dpkg(1)](https://manpages.ubuntu.com/manpages/noble/en/man1/dpkg.1.html) |
| `snap remove --revision` | revisioni snap superate | ✓ | [Snap: Get started](https://snapcraft.io/docs/tutorials/get-started/) |
| `snap list --all` | elenco delle revisioni | ✎ | [Snap: Get started](https://snapcraft.io/docs/tutorials/get-started/) |
| `flatpak uninstall --unused` | runtime inutilizzati | ✓ | [flatpak-uninstall(1)](https://manpages.ubuntu.com/manpages/noble/en/man1/flatpak-uninstall.1.html) |
| `flatpak update` / `remote-ls --updates` | aggiornamento delle app | ✓ | [flatpak-update(1)](https://manpages.ubuntu.com/manpages/noble/en/man1/flatpak-update.1.html), [flatpak-remote-ls(1)](https://manpages.ubuntu.com/manpages/noble/en/man1/flatpak-remote-ls.1.html) |
| `pacman -Syu` | aggiornamento su Arch | ✎ | [pacman(8)](https://man.archlinux.org/man/pacman.8.en), [ArchWiki: aggiornamenti parziali](https://wiki.archlinux.org/title/System_maintenance) |
| `pacman -Dk` | controllo delle dipendenze su Arch | ✎ | [pacman(8)](https://man.archlinux.org/man/pacman.8.en) |
| `dnf check` | controllo delle dipendenze su Fedora | ✎ | [dnf5 check](https://dnf5.readthedocs.io/en/latest/commands/check.8.html) |
| `dnf check-upgrade` | aggiornamenti disponibili su Fedora | ✎ | [dnf5 check-upgrade](https://dnf5.readthedocs.io/en/latest/commands/check-upgrade.8.html) |
| `dnf distro-sync` | aggiornamento completo su Fedora | ✓ | [dnf5 distro-sync](https://dnf5.readthedocs.io/en/latest/commands/distro-sync.8.html) |
| `dnf repoquery --unneeded` | pacchetti non più necessari | ✓ | [dnf5 repoquery](https://dnf5.readthedocs.io/en/latest/commands/repoquery.8.html) |
| `zypper verify --dry-run` | controllo delle dipendenze su openSUSE | ✎ | [zypper(8)](https://manpages.opensuse.org/Tumbleweed/zypper/zypper.8.en.html) |
| `docker system prune -f` | spazio di Docker | ✎ | [docker system prune](https://docs.docker.com/reference/cli/docker/system/prune/) |

### Sistema e rete

| Comando | Uso | Stato | Fonte |
|---|---|:---:|---|
| `journalctl --vacuum-time` | riduce il registro di sistema | ✓ | [journalctl(1)](https://manpages.ubuntu.com/manpages/noble/en/man1/journalctl.1.html) |
| `fstrim -av` | TRIM del disco | ✓ | [fstrim(8)](https://manpages.ubuntu.com/manpages/noble/en/man8/fstrim.8.html) |
| `resolvectl flush-caches` | svuota la cache DNS | ✓ | [resolvectl(1)](https://manpages.ubuntu.com/manpages/noble/en/man1/resolvectl.1.html) |
| `networkctl renew` | rinnova l'indirizzo con systemd-networkd | ✓ | [networkctl(1)](https://www.freedesktop.org/software/systemd/man/latest/networkctl.html) |
| `nmcli connection up uuid` | rinnova l'indirizzo con NetworkManager | ✎ | [nmcli(1)](https://networkmanager.dev/docs/api/latest/nmcli.html), [esempi](https://networkmanager.dev/docs/api/latest/nmcli-examples.html) |
| `dhclient -r` | rinnova l'indirizzo con dhclient | ✓ | [dhclient(8)](https://manpages.ubuntu.com/manpages/noble/en/man8/dhclient.8.html) |
| `smartctl -H -A` | salute del disco | ✓ | [smartctl(8)](https://manpages.ubuntu.com/manpages/noble/en/man8/smartctl.8.html) |
| `needrestart -b` | servizi da riavviare | ✓ | [needrestart(1)](https://manpages.ubuntu.com/manpages/noble/en/man1/needrestart.1.html) |
| `shutdown -r` | riavvio | ✓ | [shutdown(8)](https://manpages.ubuntu.com/manpages/noble/en/man8/shutdown.8.html) |
| `systemctl`, `systemd-analyze`, `ip`, `ufw`, `sensors`, `timeshift`, `gsettings`, `zenity`, `lsblk`, `findmnt` | analisi (sola lettura) e finestre | … | |

## macOS

Molti comandi di macOS non sono open source e Apple non pubblica i loro manuali online:
l'unica fonte ufficiale è il manuale presente sul Mac (`man nome-comando`).

| Comando | Uso | Stato | Fonte |
|---|---|:---:|---|
| `ipconfig getpacket` | capire se l'interfaccia usa DHCP | ✓ | [ipconfig(8), codice Apple](https://github.com/apple-oss-distributions/bootp/blob/main/ipconfig.tproj/ipconfig.8) |
| `ipconfig set … DHCP` | rinnova l'indirizzo | ⚠ | lo stesso manuale dice di usare `ipconfig` solo per prove e diagnosi. Procedura ufficiale: [Rinnovare il lease DHCP](https://support.apple.com/guide/mac-help/renew-ip-address-dhcp-server-mac-mchlp1545/mac) |
| `rm` | cancellazione | ✓ | [rm, codice Apple](https://github.com/apple-oss-distributions/file_cmds/blob/main/rm/rm.c) |
| `softwareupdate -i -a` | aggiornamenti di macOS | ✎ | [Proprietà del volume su Apple Silicon](https://support.apple.com/guide/deployment/use-secure-and-bootstrap-tokens-dep24dbdcf9e/web) |
| `brew update` / `outdated --quiet` / `upgrade` / `cleanup -s` | Homebrew | ✓ | [brew(1)](https://docs.brew.sh/Manpage) |
| `docker system prune -f` | spazio di Docker | ✎ | [docker system prune](https://docs.docker.com/reference/cli/docker/system/prune/) |
| `killall -HUP mDNSResponder` | svuota la cache DNS | ⚠ | il [manuale di mDNSResponder](https://github.com/apple-oss-distributions/mDNSResponder/blob/main/mDNSShared/mDNSResponder.8) non descrive il segnale HUP |
| `lsregister` | ricostruisce il database "Apri con" | ⚠ | strumento interno di macOS, senza manuale |
| `tmutil`, `diskutil`, `mdutil`, `atsutil`, `qlmanage`, `dscacheutil`, `launchctl`, `purge`, `pmset`, `defaults`, `sips`, `iconutil`, `fdesetup`, `spctl`, `csrutil`, `system_profiler`, `sw_vers`, `xcrun simctl` | vari | … | manuale sul Mac |

## Windows

| Comando | Uso | Stato | Fonte |
|---|---|:---:|---|
| `Clear-RecycleBin` | cestino dell'utente corrente | ✎ | [Clear-RecycleBin](https://learn.microsoft.com/powershell/module/microsoft.powershell.management/clear-recyclebin?view=powershell-5.1) |
| `Checkpoint-Computer` | punto di ripristino, al massimo uno ogni 24 ore | ✎ | [Checkpoint-Computer](https://learn.microsoft.com/powershell/module/microsoft.powershell.management/checkpoint-computer?view=powershell-5.1) |
| `Delete-DeliveryOptimizationCache` | cache Delivery Optimization | ✓ | [Delete-DeliveryOptimizationCache](https://learn.microsoft.com/powershell/module/deliveryoptimization/delete-deliveryoptimizationcache) |
| `Optimize-Volume -ReTrim` | TRIM degli SSD | ✓ | [Optimize-Volume](https://learn.microsoft.com/powershell/module/storage/optimize-volume) |
| `Clear-DnsClientCache` | svuota la cache DNS | ✓ | [Clear-DnsClientCache](https://learn.microsoft.com/powershell/module/dnsclient/clear-dnsclientcache) |
| `cleanmgr /sagerun` + `StateFlags` | rimozione di Windows.old | ✓ | [Automating Disk Cleanup tool](https://learn.microsoft.com/troubleshoot/windows-server/backup-and-storage/automating-disk-cleanup-tool) |
| `DISM /StartComponentCleanup` | compattazione dei componenti | ✎ | [Clean up the WinSxS folder](https://learn.microsoft.com/windows-hardware/manufacture/desktop/clean-up-the-winsxs-folder) |
| `DISM /AnalyzeComponentStore` | anteprima in simulazione | ✓ | [Determine the actual size of the WinSxS folder](https://learn.microsoft.com/windows-hardware/manufacture/desktop/determine-the-actual-size-of-the-winsxs-folder) |
| `DISM /RestoreHealth` | riparazione dell'immagine | ✓ | [Repair a Windows image](https://learn.microsoft.com/windows-hardware/manufacture/desktop/repair-a-windows-image) |
| `sfc /scannow` | verifica dei file di sistema | ✓ | [sfc](https://learn.microsoft.com/windows-server/administration/windows-commands/sfc) |
| `ipconfig /release /renew /flushdns /registerdns` | rete | ✓ | [ipconfig](https://learn.microsoft.com/windows-server/administration/windows-commands/ipconfig) |
| `netsh winsock reset` | reset di Winsock | ✓ | [netsh winsock](https://learn.microsoft.com/windows-server/administration/windows-commands/netsh-winsock) |
| `netsh int ip reset` | reset di TCP/IP, con file di registro | ✎ | [Reset TCP/IP by using the NetShell utility](https://learn.microsoft.com/troubleshoot/windows-server/networking/reset-tcp-ip-net-shell) |
| `netsh interface ipv4 delete arpcache` / `ipv6 reset` | cache ARP, reset IPv6 | ✎ | [netsh interface](https://learn.microsoft.com/windows-server/administration/windows-commands/netsh-interface) |
| `winget upgrade` | aggiornamento delle applicazioni | ✓ | [winget upgrade](https://learn.microsoft.com/windows/package-manager/winget/upgrade) |
| codici di uscita di winget | per esempio `0x8A15002B` | ✎ | [WinGet HRESULT codes](https://github.com/microsoft/winget-cli/blob/master/doc/windows/package-manager/winget/returnCodes.md) |
| Windows Update Agent (`IUpdateSearcher`) | aggiornamenti di Windows | ✓ | [IUpdateSearcher::Search](https://learn.microsoft.com/windows/win32/api/wuapi/nf-wuapi-iupdatesearcher-search), [OperationResultCode](https://learn.microsoft.com/windows/win32/api/wuapi/ne-wuapi-operationresultcode) |
| chiavi `StartupApproved` | programmi all'avvio | ⚠ | è il formato che scrive Gestione attività, ma Microsoft non lo documenta |
| `Get-NetIPAddress`, `Get-PhysicalDisk`, `Get-CimInstance`, `powercfg /batteryreport`, chiavi del riavvio in sospeso | analisi (sola lettura) | … | |
