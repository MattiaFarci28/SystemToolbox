@{
    # Regole escluse di proposito: riguardano lo stile, non la
    # correttezza, e in questo progetto sono scelte consapevoli.
    ExcludeRules = @(
        # Write-Host e' l'interfaccia: la finestra grafica lo
        # intercetta per disegnare lo stesso testo della console.
        'PSAvoidUsingWriteHost',
        # I catch vuoti stanno dove un tentativo fallito non e' un
        # problema (file in uso, servizio assente): l'esito lo
        # decide il controllo successivo.
        'PSAvoidUsingEmptyCatchBlock',
        # -WhatIf/-Confirm non servono: la conferma la chiede
        # l'interfaccia prima di iniziare, e la simulazione e'
        # gestita dal motore.
        'PSUseShouldProcessForStateChangingFunctions',
        # Format-Bytes e Measure-FolderBytes: nomi chiari cosi'.
        'PSUseSingularNouns',
        # I gestori di eventi WPF ricevono parametri che non usano.
        'PSReviewUnusedParameter',
        # 1.1.1.1 e' il bersaglio voluto del test di connettivita'.
        'PSAvoidUsingComputerNameHardcoded'
    )
}
