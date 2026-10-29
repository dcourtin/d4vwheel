# Roue d'odysseus — spécification

Lanceur circulaire qui s'ouvre **autour du pointeur** : huit raccourcis en cercle, à portée de geste, sans aller jusqu'au Dock. Une place peut être un **dossier**, qui ouvre un **second anneau** autour du premier. Programme `odysseus-roue`, contenu choisi dans Réglages > Roue.

Cette note décrit le comportement indépendamment de Linux, pour juger d'un portage (macOS : voir la dernière section).

## Ouvrir et fermer
- **Ouvrir** : raccourci clavier (Super+R), clic du milieu sur le bureau, ou modificateur + clic du milieu n'importe où (le clic n'est alors pas transmis à la fenêtre dessous).
- **Bascule** : redemander la roue alors qu'elle est ouverte la ferme (une seule instance à la fois).
- **Fermer** : Échap, clic au centre, clic à côté de la roue, ou après tout choix.
- La roue s'ouvre **centrée sur le pointeur**, puis est écartée des bords pour tenir entière à l'écran (marge 16 pt, et de la place sous elle pour l'étiquette). S'il existe au moins un dossier, la marge compte le second anneau.

## Les places
Huit places, numérotées **1 à 8 depuis le haut, dans le sens des aiguilles d'une montre** (place 1 à midi, place 3 à 3 h…). Une place peut tenir :

| Contenu | Effet au choix | Repère visuel |
|---|---|---|
| **Application** | la lance ; si elle est déjà ouverte, ramène sa fenêtre (la suivante si sa fenêtre est déjà devant ; une fenêtre réduite revient) | petit point gris sous l'icône si l'appli est ouverte |
| **Action d'application** (ex. « Nouvelle note » de Notes) | lance l'action | pastille d'accent en bas à droite de l'icône |
| **Entrée proposée par une appli** | lance sa commande | pastille d'accent en bas à droite |
| **Dossier** (jusqu'à 8 places à lui) | ouvre le second anneau | tuile d'accent avec ses 4 premières icônes en mini |
| **Vide** | ouvre Réglages > Roue pour la remplir | « + » discret |

Pas de dossier dans un dossier. Un élément n'occupe qu'une place dans toute la roue (le mettre ailleurs le retire de l'ancienne).

## Dossiers : le second anneau
- **S'ouvre** au survol du dossier, à son chiffre, ou à son clic. **Se referme** quand on survole une autre place de la roue, ou avec Échap / Retour arrière (Échap une deuxième fois ferme la roue).
- Ses places remplies (seulement elles) s'alignent sur un arc **centré sur l'angle du dossier**, à 45° d'écart, dans un anneau plus large derrière la roue. Un dossier vide montre une seule place vide (→ Réglages).
- Geste continu : clic du milieu maintenu sur le bureau → glisser sur le dossier (l'anneau s'ouvre) → glisser vers l'appli → relâcher. Relâcher sur le dossier lui-même le laisse ouvert.

## Clavier
- **1–8** (rangée du haut, par touche physique : marche en AZERTY) ou pavé numérique : choisit la place ; dans un dossier ouvert, choisit sa place.
- **Flèches / Tab, Maj+Tab** : parcourent les places (ou celles du dossier) ; **Entrée / Espace** : choisit ; sans rien de survolé, referme le dossier ouvert, sinon la roue.
- **Échap** : referme le dossier, sinon la roue. **Retour arrière** : referme le dossier.

## Souris
- Survol : halo d'accent sous la place, et son nom dans une étiquette sous la roue (« Nom · Appli » pour une action, « Nom · dossier » pour un dossier, « Choisir dans Réglages » pour une place vide, « Fermer » au centre).
- Clic gauche sur une place : la choisit. Clic au centre ou dehors : ferme.
- Clic du milieu maintenu, glissé puis relâché sur une place : la choisit (seulement si le pointeur a quitté le centre depuis l'ouverture).

## Apparence (valeurs en points logiques)
- Voile de 10 % de noir sur tout l'écran ; disque de rayon **148**, couleur des panneaux du thème (97 % opaque), liseré, ombre portée.
- Icônes de **40**, centres à **100** du centre ; halo de survol rayon **34** (accent à 22 %) ; centre « fermer » rayon **36** avec une croix.
- Second anneau : icônes à **196** du centre, bord extérieur à **242** ; le dossier ouvert garde son halo.
- Dossier : tuile arrondie (rayon 12) teintée d'accent à 20 %, grille de mini-icônes de 15 (écart 3), centrée.
- Appli sans icône : son initiale sur une pastille de couleur tirée de son nom.
- Étiquette : pilule sous la roue, 13,5 pt, tronquée à 360.

## Animations
Toutes pilotées par le temps et cadencées par l'écran (une image par rafraîchissement, rien entre deux animations) :
- **Ouverture** (≈ 220 ms) : le voile s'installe et le disque passe de 90 % à 100 % en 180 ms (ease-out cubique) ; les icônes sortent du centre l'une après l'autre dans le sens horaire (décalage 10 ms, 150 ms chacune), de 45 % à 100 % du rayon avec un léger rebond (ease-out-back), en fondu.
- **Survol** : le halo grandit de 75 % à 100 % et s'allume, l'icône s'avance de 5 pt vers l'extérieur (pas d'agrandissement : elle reste nette) ; suivi exponentiel, constante de temps 50 ms. Le centre s'éclaircit de même.
- **Dossier** : l'anneau se déploie du bord du disque à son rayon final (constante 65 ms) ; les icônes du dossier glissent de la place du dossier à la leur sur l'arc, celles du milieu d'abord (éventail), en fondu. Au repli, le mouvement s'inverse ; passer d'un dossier à un autre replie le premier avant de déployer le second.
- **Étiquette** : fondu de 90 ms quand elle change, en glissant de 4 pt.
- **Choix ou fermeture** : l'appli est lancée aussitôt, puis la roue se resserre de 6 % et s'efface en 140 ms ; pendant ce temps, plus aucune entrée n'est prise.
- Les icônes sont chargées à leur taille exacte et calées sur les pixels (nettes même à des positions fractionnaires).

## Contenu et configuration
Fichier texte `~/.config/odysseus/roue`, une place par ligne, depuis le haut, sens horaire ; lignes vides et `#` ignorées :

```
app:odysseus-notes
action:odysseus-notes:nouvelle
-
dossier:Artcraft
  app:photocraft
  app:vectorcraft
entree:com.exemple.capture
-
-
-
```

- `app:ID` (identifiant de l'appli, son fichier .desktop), `action:ID:CLÉ` (une `[Desktop Action CLÉ]` de l'appli), `entree:ID` (proposition d'une appli), `dossier:NOM`, `-` (vide).
- Les places d'un dossier suivent sa ligne, **en retrait** (espace ou tabulation), jusqu'à 8 ; seules les dernières vides sont omises à l'écriture.
- Sans fichier : les **favoris du Dock**, sinon une sélection d'applis présentes (Fichiers, navigateur, terminal, Notes, Assistant, Réglages).
- Le fichier est relu à chaque ouverture : aucun service à relancer.

## Interface pour les applis (propositions)
Une appli peut **proposer** une entrée ; elle n'entre jamais seule dans la roue, l'utilisateur la place dans Réglages.
- Déposer un fichier `.desktop` (Name, Exec, Icon, Comment) dans `odysseus/roue` d'un dossier de données (`~/.local/share`, `/usr/share`…) ; l'identifiant est le nom du fichier.
- Ou en ligne de commande : `odysseus-roue proposer --id ID --nom NOM --commande CMD [--icone I] [--description D]` (notification à l'utilisateur), `odysseus-roue retirer ID`, `odysseus-roue liste` (contenu de la roue, dossiers compris, et propositions).
- Identifiant : lettres, chiffres, `.`, `-`, `_` (100 caractères au plus).

## Réglages > Roue
- La roue dessinée telle qu'elle s'ouvre ; un clic choisit une place (accent autour).
- Fiche de la place choisie : nom, nature (« Application », « Action de … », « Proposée par une appli », « Dossier · n places »), flèches ← → pour la déplacer autour de la roue, « Retirer ».
- « En faire un dossier » : la place devient un dossier (ce qu'elle tenait y entre), nommé aussitôt au clavier (Entrée valide, Échap annule ; vide → « Dossier », « Dossier 2 »…).
- Dossier choisi : « Ouvrir » (ou second clic) montre ses huit places, dossier au centre, à remplir de la même façon ; « Retour à la roue » ; « Renommer ».
- En dessous, ce qu'on peut y mettre, par groupes : propositions des applis, actions des applis, applications ; un clic met l'élément à la place choisie et passe à la suivante libre ; chaque élément déjà placé porte une étiquette « Place 3 » ou « Artcraft · 2 ».
- « Reprendre les favoris du Dock ». Chaque changement est enregistré aussitôt.

## Pour un portage sur macOS (pistes, à vérifier)
- **Ouvrir** : raccourci global (bibliothèque type HotKey / `RegisterEventHotKey`) ; le clic du milieu et modificateur + clic demandent d'écouter la souris partout (`CGEventTap`, autorisation Accessibilité ; un tap peut aussi avaler le clic). « Sur le bureau » = aucune fenêtre sous le pointeur, ou Finder au premier plan sur le bureau.
- **Fenêtre** : `NSPanel` sans bordure, non activante, transparente, plein écran sur l'écran du pointeur, niveau au-dessus des fenêtres (`.popUpMenu` ou `.screenSaver`), `canJoinAllSpaces` ; dessin SwiftUI ou Core Animation. Position du pointeur : `NSEvent.mouseLocation` (origine en bas à gauche).
- **Applications** : `NSWorkspace` / Launch Services pour la liste et les icônes (`NSWorkspace.shared.icon(forFile:)`, à charger à la taille exacte pour la netteté) ; « déjà ouverte » : `NSRunningApplication`, ramener par `activate()` ; passer d'une fenêtre à l'autre demande l'API d'accessibilité (`AXUIElement`).
- **Actions d'applications** : pas d'équivalent direct des `[Desktop Action]` ; candidats : raccourcis Shortcuts (`shortcuts run`), schémas d'URL, AppleScript, éléments du menu du Dock.
- **Propositions des applis** : un dossier `~/Library/Application Support/d4vWheel/propositions/` (fichiers JSON), ou un schéma d'URL `d4vwheel://proposer?…`, ou un outil en ligne de commande.
- **Configuration** : le même format texte se garde tel quel (`~/Library/Application Support/d4vWheel/wheel` ou `~/.config/d4vwheel/wheel`) ; la fiche Réglages devient une fenêtre de préférences.
- **Clavier** : la rangée des chiffres par code physique (`kVK_ANSI_1`…) pour rester juste en AZERTY.
