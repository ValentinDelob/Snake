# Décisions prises, et pourquoi

Ce fichier existe pour qu'on ne défasse pas par ignorance ce qui a été décidé
en connaissance de cause. Chaque entrée dit **ce qui a été choisi**, **contre
quoi**, et **pourquoi**.

## Le jeu a le droit de dériver

Le propriétaire a explicitement donné carte blanche : le jeu peut s'éloigner
autant qu'il le faut du Snake d'origine. Il n'y a donc **aucune obligation de
fidélité** au jeu classique. Ce qui a déjà été abandonné : la grille, la mort
définitive, le score en points, le terrain fixe.

## Pas de grille, un rayon de braquage

Le serpent se déplace en continu et ne tourne que progressivement. C'est la
contrainte qui fait tout le jeu : on s'engage dans une courbe, on ne se
téléporte pas d'une case à l'autre. Toute proposition qui ramènerait un
déplacement par cases va contre ce choix.

## Le score **est** la longueur

Il n'y a plus de compteur de points. La matière avalée se convertit un pour
un en longueur, et c'est ce nombre qui s'affiche. Conséquence : tout ce qui
donne ou retire « des points » (les cartes de la caisse, la régurgitation,
la décomposition) se raisonne en unités de longueur.

## Mener doit être un handicap

La gloutonnerie — plus large, plus lent, moins maniable — n'est pas une
punition arbitraire : c'est l'équilibrage du mode. Elle resserre les scores
sans règle artificielle, et elle rend le meneur visible et vulnérable. Si un
jour on trouve la progression trop molle ou trop dure, on règle la courbe,
on ne supprime pas le principe.

## La matière n'est jamais détruite

Ce qui entre dans un serpent ressort toujours : par la touche de
régurgitation, ou par sa mort. C'est ce qui donne au terrain son économie —
tuer quelqu'un ou le voir mourir crée une opportunité pour tout le monde. Une
règle qui ferait simplement disparaître de la matière casserait cette boucle.

## Personne n'est éliminé

La mort coûte la longueur et deux secondes, rien d'autre. C'était la réponse
au constat que le duel n'était pas amusant : une manche se résumait à
quatre-vingt-dix secondes prudentes et une seule erreur. On ne revient pas à
l'élimination sans remplacer ce qu'elle apporte.

## Le terrain grandit avec le nombre de joueurs

Chaque joueur ajoute la moitié de la surface standard. Attention : c'est une
décision **en tension** avec le fait de vouloir que les joueurs se croisent.
Si un jour le duel paraît trop dispersé, la piste retenue était une arène qui
se resserre au fil de la manche, pas un retour à un terrain fixe.

## Les objets restent debout

Tout ce qui est posé au sol se tient droit et ne fait que tourner sur
lui-même. Aucun objet ne s'incline vers la caméra.

## La géométrie doit rester simple

Quand le jeu doit tourner plus vite, la première réponse est de **simplifier
la géométrie**, pas d'optimiser le code qui fabrique un maillage dense. Le
jeu est volontairement low poly. C'est aussi pour cela que la finesse du
corps est un réglage offert au joueur (`SIMPLE` / `SMOOTH` / `FINE`) plutôt
qu'un point choisi en silence.

Une mesure a été faite : le corps est passé d'environ 2 800 triangles à 714
en mode `SMOOTH`, sans différence visible côte à côte.

## Les libellés de l'interface sont en majuscules et en anglais

`PLAY SOLO`, `GRAPHICS`, `LENGTH`, `GHOST`… Le propriétaire a été informé et
a laissé ainsi. Une traduction complète de l'interface en français reste une
option ouverte, mais elle se ferait d'un bloc, pas au cas par cas.

## Le rendu est en Forward+ (Vulkan)

Choisi à la suite d'un plantage du pilote graphique en mode compatibilité. Le
mode compatibilité reste disponible en repli. Le plantage était intermittent
et n'a jamais pu être reproduit à la demande : c'est une atténuation, pas une
correction prouvée.

## Points laissés ouverts

- Le jeu est **entièrement muet**. C'est, de loin, le plus gros manque
  identifié pour le plaisir de jeu.
- Rien ne monte en tension à l'intérieur d'une manche : la minute 4 ressemble
  à la minute 1.
- Il n'y a **aucun adversaire en solo**, alors que le jeu sait faire tourner
  plusieurs serpents et qu'un pilote automatique existe déjà (il ne sert
  qu'aux tests et à la démonstration).
- Il reste de rares à-coups d'affichage, une image sur cinq mille environ,
  dont le temps ne passe pas dans le code du jeu ; ils n'ont pas été
  expliqués.
- Les ombres du soleil sont calculées jusqu'à 70 unités, alors que le terrain
  en fait désormais 84 de large et davantage à plusieurs.
