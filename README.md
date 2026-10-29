# d4vWheel — lanceur circulaire pour macOS

Huit raccourcis en cercle autour du pointeur, à portée de geste, sans aller jusqu'au Dock.
Une place peut être un dossier, qui ouvre un second anneau ; un dossier peut en contenir un autre,
qui ouvre un troisième anneau. Fond flouté comme le Dock. Appli de barre des menus (sans Dock),
macOS 14 ou plus. Portage macOS de la « Roue d'odysseus » ([spécification](docs/specification.md)).

<p align="center">
  <img src="docs/images/roue.png" width="440" alt="La roue, un dossier survolé ouvre son anneau">
  <img src="docs/images/roue-dossier.png" width="440" alt="Un dossier dans un dossier : trois anneaux">
</p>
<p align="center">
  <img src="docs/images/reglages.png" width="640" alt="La fenêtre Réglages : la roue, la place choisie, le fond, les déclencheurs">
</p>

## Installer

Télécharger `d4vWheel-<version>.dmg`, glisser d4vWheel dans Applications, l'ouvrir. Elle vit dans la barre des menus.

Autorisations, demandées à la première utilisation :

- **Accessibilité** (Réglages Système > Confidentialité et sécurité) : pour ouvrir la roue au clic du milieu,
  et pour passer d'une fenêtre à l'autre d'une appli déjà devant. Sans elle, le raccourci clavier et le
  lancement des applis marchent quand même.
- **Automation** : la première fois qu'une action pilote une appli Apple (« Nouvelle note »…).

## Ouvrir et fermer

- **⌃⌥Espace** (configurable dans Réglages), **clic du milieu sur le bureau**, ou **⌥ + clic du milieu**
  n'importe où (modificateur configurable). Redemander la roue la ferme.
- Geste continu : clic du milieu maintenu → glisser sur un dossier (l'anneau s'ouvre) → glisser sur l'appli → relâcher.
- Fermer : Échap, clic au centre, clic à côté, clic droit, ou après tout choix.

## Clavier et souris

- 1–8 (touches physiques, juste en AZERTY) ou pavé numérique : choisit la place ; dans un anneau ouvert, sa place.
- Molette ou défilement (vers le bas : sens horaire) : parcourt les places sans bouger la souris ;
  relâcher le clic du milieu resté au centre choisit la place ainsi atteinte.
- Flèches, Tab / Maj+Tab : parcourent ; Entrée / Espace : choisit ; Échap et Retour arrière : replient l'anneau
  le plus profond, sinon Échap ferme la roue.
- Survol d'un dossier : ouvre son anneau ; survol d'une autre place : le referme.
- Une appli déjà ouverte revient devant ; déjà devant, c'est sa fenêtre suivante (une réduite d'abord).

## Réglages

Menu de la barre des menus > « Réglages… » (ou une place vide de la roue, ou `d4vwheel://reglages`).

- **La roue** telle qu'elle s'ouvre, avec le vrai flou : un clic choisit une place.
- **La fiche** : déplacer, retirer, en faire un dossier (nommé aussitôt au clavier), ouvrir ou renommer un dossier.
  Quand la place choisie est un dossier, un clic dans la liste ajoute l'élément au dossier.
- **Fond** : matériau du flou et opacité de la teinte (0 % flou pur, 100 % opaque).
- **Ouvrir la roue** : raccourci clavier (cliquer puis appuyer sur les touches), clic du milieu sur le bureau,
  modificateur pour le clic du milieu partout. **Système** : ouverture à l'ouverture de session.
- **Ce qu'on peut y mettre**, par groupes : propositions des applis, actions des applis, raccourcis de l'app
  Raccourcis, applications ; plus un champ pour un lien ou une commande. Un clic met l'élément à la place
  choisie et passe à la suivante libre ; un élément déjà placé porte « Place 3 » ou « Bureau · Outils · 2 ».
- « Reprendre les favoris du Dock ». Chaque changement est enregistré aussitôt ; le fichier modifié ailleurs est relu.

Le réglage d'accessibilité « Réduire les animations » du système est respecté.

## Fichier de configuration

`~/Library/Application Support/d4vWheel/wheel` (ou `~/.config/d4vwheel/wheel`), relu à chaque ouverture.
Les emplacements d'avant le renommage (`Application Support/Roue/roue`, `~/.config/roue/roue`) restent lus.
Sans fichier : les favoris du Dock.

```
app:com.apple.Safari              # identifiant de bundle, nom (Safari) ou chemin (/Applications/X.app)
action:com.apple.Notes:nouvelle   # une action du catalogue (voir Réglages)
entree:com.exemple.capture        # une proposition d'appli (voir plus bas)
dossier:Bureau
  app:com.apple.mail
  dossier:Outils                  # un dossier dans un dossier : troisième anneau
    app:com.apple.Terminal
  app:com.apple.iCal
url:https://example.org           # lien ou schéma d'URL
sh:open -a Terminal               # commande zsh
raccourci:Mon raccourci           # app Raccourcis
-
```

Une place par ligne, depuis le haut, dans le sens horaire ; les places d'un dossier suivent sa ligne, en retrait
(deux niveaux de dossiers au plus). `-` est une place vide. Les lignes vides et `#` sont ignorées.

## Interface pour les applis (propositions)

Une appli peut **proposer** une entrée ; elle n'entre jamais seule dans la roue, l'utilisateur la place dans Réglages.

- Déposer un fichier `ID.json` dans `~/Library/Application Support/d4vWheel/propositions/` :
  `{"nom": "…", "commande": "…", "icone": "chemin ou symbole SF", "description": "…"}`.
- Ou par le schéma d'URL : `d4vwheel://proposer?id=ID&nom=NOM&commande=CMD[&icone=I&description=D]`
  (d4vWheel demande confirmation), `d4vwheel://retirer?id=ID`, `d4vwheel://ouvrir`, `d4vwheel://reglages`.
- Ou en ligne de commande (`/Applications/d4vWheel.app/Contents/MacOS/d4vWheel`) :
  `d4vWheel proposer --id ID --nom NOM --commande CMD [--icone I] [--description D]`, `d4vWheel retirer ID`,
  `d4vWheel liste`, `d4vWheel ouvrir`, `d4vWheel reglages`.
- Identifiant : lettres, chiffres, `.`, `-`, `_` (100 caractères au plus).

## Construire

Les Command Line Tools suffisent, sans Xcode.

```bash
swift run d4vWheel            # lancement rapide, sans bundle
scripts/build-app.sh      # build/d4vWheel.app (signature ad hoc)
scripts/test.sh           # tests
```

Aides : `swift run d4vWheel --rendu /tmp/d4vwheel.png --dossier` dessine la roue dans une image ;
`swift run d4vWheel --rendu-reglages /tmp/reglages.png` la fenêtre Réglages ; `kill -USR1 <pid>` bascule la roue.

## Distribuer

Il faut un certificat **Developer ID Application** (compte développeur Apple) et un profil de notarisation :

```bash
xcrun notarytool store-credentials d4vwheel --apple-id vous@exemple.fr --team-id ÉQUIPE --password mot-de-passe-d-app
```

```bash
CODESIGN_IDENTITY="Developer ID Application: Votre Nom (ÉQUIPE)" NOTARY_PROFILE=d4vwheel scripts/release.sh
```

Le script construit, signe avec le runtime durci et les entitlements, notarise, agrafe, puis écrit
`dist/d4vWheel-<version>.zip` et `dist/d4vWheel-<version>.dmg`. La version se change dans `Packaging/Info.plist`.
Une signature stable est nécessaire pour que l'autorisation Accessibilité survive aux mises à jour ; une
signature ad hoc change à chaque build et la fait perdre.
