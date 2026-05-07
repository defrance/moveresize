# Moveresize


<table style='border:0px'>
    <tr>
        <td style="vertical-align:middle; text-align:center; width: 50%; min-width: 400px;">
            <img src="sample.png" alt="Aperçu de l'application" width="420"/>
        </td>
        <td style="vertical-align:top;">
            <p>
                <img src="https://img.shields.io/badge/platform-macOS-blue"/>
                <img src="https://img.shields.io/badge/language-swift-orange"/>
                <img src="https://img.shields.io/badge/status-MVP-green"/>
            </p>
            <p>               
Utilitaire macOS en Swift pour déplacer et redimensionner une fenêtre avec la souris et un modificateur clavier.
            </p>
            <!-- Table des matières -->
            <ul>
                <li><a href="#fonctionnalités">Fonctionnalités</a></li>
                <li><a href="#installation--lancement">Installation & Lancement</a></li>
                <li><a href="#utilisation">Utilisation</a></li>
                <li><a href="#license-et-soutien">Licence et Soutien</a></li>
            </ul>
        </td>
    </tr>
</table>

## Fonctionnalités

- `Option` + clic gauche + glisser : déplace la fenêtre sous le curseur.
- `Command` + clic gauche + glisser : redimensionne la fenêtre sous le curseur.
- Menu pour choisir le modificateur utilisé pour `Move` et `Resize` (`Option`, `Command`, `Fn`).
- Maintenir `Shift` pendant le glisser pour contraindre le déplacement/redimensionnement à l'horizontale.
- Maintenir `Control` pendant le glisser pour contraindre le déplacement/redimensionnement à la verticale.
- Choix de l’ancre de redimensionnement : `Top Left`, `Top Right`, `Bottom Left`, `Bottom Right`.
- Interface localisée (anglais, français, espagnol, repli sur anglais).
- La langue est détectée automatiquement depuis les langues préférées de macOS.
- Paramètre de lancement pour forcer la langue : `--lang` / `--language` (`en`, `fr`, `es`).


## Installation & Lancement

```bash
swift run
```
Pour forcer une langue au lancement :
```bash
swift run moveresize --lang fr
# ou
swift run moveresize --language en
```

Au premier lancement :
1. Autoriser l’application dans `Réglages Système > Confidentialité et sécurité > Accessibilité`.
2. Si macOS bloque la capture souris, autoriser aussi `Input Monitoring`.
3. Relancer l’application si nécessaire.

## Utilisation

- Utilisez les raccourcis clavier + souris pour déplacer ou redimensionner les fenêtres.
- Pendant le glisser, utilisez `Shift` pour bloquer l'axe horizontal et `Control` pour bloquer l'axe vertical.
- Accédez aux préférences via l’icône de barre de menus.
- Si besoin, lancez l'app avec `--lang en|fr|es` pour surcharger la détection automatique.


## Licence et Soutien

Il s'agit d'un Projet open-source sous licence MIT.

Vous pouvez soutenir mon travail ici : [https://www.patas-monkey.com/boutique/](https://www.patas-monkey.com/boutique/)

Vous abonnez à ma chaine Youtube là : [https://www.youtube.com/@charlene-patasmonkey ](https://www.youtube.com/@charlene-patasmonkey )

Et m'envoyer un petit message d'encouragement par là https://www.patas-monkey.com/formulaire-de-contact/
