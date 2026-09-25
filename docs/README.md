# Documentation du projet

Ce dossier décrit **ce qu'est le jeu et comment on travaille dessus**, sans
entrer dans le code. Il s'adresse à quelqu'un — humain ou assistant — qui
arrive sur le projet et doit pouvoir ajouter une fonctionnalité sans défaire
ce qui existe.

## Par où commencer

| Fichier | Ce qu'on y trouve |
| --- | --- |
| [`le-jeu.md`](le-jeu.md) | Les règles du jeu tel qu'il est aujourd'hui, avec les chiffres |
| [`methode-de-travail.md`](methode-de-travail.md) | La boucle obligatoire : construire, lancer, vérifier, commiter |
| [`decisions.md`](decisions.md) | Les choix déjà faits et pourquoi — à ne pas défaire sans raison |

Le `README.md` à la racine du dépôt décrit l'arborescence des fichiers et les
touches. Il reste la référence pour « où se trouve quoi ».

## Le jeu en trois phrases

Un serpent se déplace sans jamais s'arrêter sur un grand terrain sombre, et
on ne le dirige qu'en le faisant tourner à gauche ou à droite. Il ramasse de
la matière lumineuse éparpillée au sol : **plus il en avale, plus il est long,
large, lent et difficile à manœuvrer**. Au bout de cinq minutes, le plus gros
serpent gagne — mourir ne met personne dehors, cela coûte seulement tout ce
qu'on avait avalé, qui retombe par terre pour les autres. En solo, jusqu'à
quatre rivaux pilotés par la machine disputent le terrain.

Le jeu s'appelle « Snake 3D » mais il a beaucoup dérivé du Snake d'origine :
il n'y a plus de grille, plus de mort définitive, et le score n'est plus un
compteur de points mais la longueur même du serpent.

## Ce qu'il faut savoir avant de toucher à quoi que ce soit

1. **Le jeu se joue, il ne se compile pas seulement.** Une fonctionnalité
   n'est pas terminée parce que le code s'importe sans erreur. Voir
   [`methode-de-travail.md`](methode-de-travail.md).
2. **Il existe un auto-test qui joue une partie entière tout seul.** Il est le
   filet de sécurité principal : toute règle nouvelle doit y être ajoutée.
3. **Une fonctionnalité par commit.** Jamais deux.
4. **L'interface et le code sont en anglais**, la conversation avec le
   propriétaire du projet est en français. Cette documentation est en
   français ; les libellés cités (`LENGTH`, `GRAPHICS`, `GHOST`…) sont ceux
   qui s'affichent réellement à l'écran.
