# Le jeu

Tout ce qui suit décrit le comportement observable du jeu. Les valeurs
chiffrées sont celles réglées aujourd'hui ; elles se règlent toutes au même
endroit et sont faites pour être ajustées.

## La manche

- Une manche dure **cinq minutes**. Une horloge est affichée au centre du
  bandeau et passe au rouge dans les trente dernières secondes.
- Le but est d'avoir **le plus long serpent** quand l'horloge s'arrête. Ce
  n'est pas une question de survie : personne n'est éliminé.
- **Mourir ne termine rien.** Le serpent disparaît deux secondes, puis
  revient à sa taille de départ, quelque part où il y a de la place, tourné
  vers la direction la plus dégagée — pour ne pas repartir dans un rocher.
- Ce qu'il avait avalé n'est pas perdu pour tout le monde : il se répand par
  terre (voir « La matière »).

## Le déplacement

- Le serpent **avance toujours**, à environ 5,2 unités par seconde. On ne
  peut ni s'arrêter ni reculer.
- Les touches gauche/droite (ou A/D, Q/D) se **maintiennent** : elles font
  tourner la tête, à environ 3,1 radians par seconde. Il y a donc un rayon de
  braquage, et c'est la contrainte principale du jeu.
- Il n'y a pas de grille : les positions sont continues, le corps est une
  courbe lisse.

## Le terrain

- Le terrain fait **84 × 56 unités** pour un joueur, et grandit avec le
  monde : chaque joueur supplémentaire ajoute **la moitié de la surface
  standard** (103 × 69 à deux, 119 × 79 à trois…). La forme est conservée.
- Des **rochers** de tailles variées (rayon 0,85 à 2,6) sont dispersés :
  une poignée de base plus un pour 210 unités², soit une trentaine sur le
  terrain solo. Ils sont mortels.
- Le placement des rochers respecte quatre promesses : rien sur un point
  d'apparition, rien dans le couloir droit devant un serpent qui démarre, un
  écart d'au moins 3 unités entre deux rochers, et un couloir le long des
  remparts. Un terrain encombré raccourcit le couloir protégé et rapetisse
  les rochers plutôt que d'en poser moins.
- Les remparts sont mortels eux aussi.

## La matière

C'est le cœur du mode.

- Le sol est semé de **particules lumineuses**, une pour 46 unités² environ.
- Chaque particule vaut entre **0,2 et 3 unités** de longueur, et elle est
  aussi grosse et aussi brillante qu'elle vaut. Les petites sont de loin les
  plus nombreuses : environ quatre sur cinq valent moins d'une unité, une sur
  six dépasse deux.
- Manger une particule ajoute **exactement sa valeur** à la longueur du
  serpent. Le nombre affiché sous `LENGTH` est donc la longueur elle-même,
  au dixième près, et non un compteur de points.
- Quand une particule est mangée, une autre est semée ailleurs, de sorte que
  le champ ne s'épuise ni ne déborde.

## La gloutonnerie

Ce qu'on avale se voit et se paie. Tout suit la même courbe, qui s'aplatit :

| Ce qui change | Au départ | À satiété |
| --- | --- | --- |
| Largeur du corps | référence | **× 2,4** |
| Vitesse | référence | **55 %** |
| Vivacité du virage | référence | **60 %** |

La largeur n'est pas décorative : c'est le rayon de collision. Un géant
attrape des particules qu'il n'aurait pas touchées étant fin, bouche des
passages entre les rochers, et ne peut plus esquiver au dernier moment.
**Mener est un handicap** — c'est voulu, cela resserre les scores.

## Régurgiter

- Touche **E**. L'indice ne s'affiche que quand il y a de quoi.
- Chaque appui ramène **un dixième** de ce qui a été avalé, et seulement à
  partir de **10 unités** avalées.
- Ce qui ressort tombe par terre derrière le serpent, sous forme de
  particules, à bonne distance de son corps. N'importe qui peut les manger,
  y compris celui qui vient de les recracher.
- C'est la porte de sortie du géant : maigrir d'un coup pour redevenir vif,
  au prix de ce qu'il abandonne sous les yeux de tout le monde.

## Mourir

- Un serpent qui touche un rempart, un rocher ou le corps d'un autre meurt.
- Il **se décompose** : exactement autant de matière qu'il avait avalée
  retombe par terre, répartie le long du corps qu'il n'a plus.
- Le plus gros serpent du terrain est donc aussi le plus gros butin, et une
  mort au milieu d'une mêlée est un festin.
- Deux secondes plus tard, il réapparaît à sa taille de départ.

## Les objets

Trois objets apparaissent au sol, en plus de la matière.

### L'éclair de vitesse

Fréquent. Se range dans l'emplacement d'objet et se déclenche avec
**ESPACE** : vitesse doublée pendant 7 secondes, avec une montée et une
descente progressives. Le serpent devient électrique et lumineux.

### La caisse mystère

Fréquente. Elle s'ouvre au contact et a **quatre faces**, tirées au sort :

| Face | Effet |
| --- | --- |
| Éclair | un boost de vitesse, rangé dans l'emplacement |
| Ralentissement | vitesse de moitié pendant 5 s, **imposé sur-le-champ** |
| +3 | trois unités de longueur, prises immédiatement |
| −3 | trois unités perdues, immédiatement |

Le malus est toujours subi, jamais choisi : c'est la règle de la caisse. Un
score poussé sous zéro s'arrête à zéro, et le serpent revient à sa taille de
départ.

### L'anneau fantôme

**Le plus rare** : le premier apparaît entre 35 et 60 secondes de manche, les
suivants entre 55 et 95. Il ressemble à un petit fantôme doré, debout sur le
sol, qui tourne sur lui-même, entouré d'étincelles — c'est cette mise en
scène qui annonce sa rareté.

Il se range dans l'emplacement et se déclenche avec **ESPACE**. Pendant
**une seconde**, le serpent devient doré et translucide et **traverse
n'importe quel corps**, le sien comme celui des autres. Les murs et les
rochers restent solides, et son propre corps reste solide pour les autres :
l'anneau ouvre un passage, il ne rend pas inoffensif.

## Le multijoueur

- Un joueur **héberge**, les autres **rejoignent** en saisissant son adresse
  IP. Port 27015, jusqu'à 8 joueurs.
- Une tentative de connexion abandonne au bout de **5 secondes** et revient
  au menu en disant pourquoi.
- L'hébergeur fait autorité : il simule la partie et envoie vingt fois par
  seconde l'état des serpents, le champ de matière et les objets. Les autres
  affichent et envoient leur direction.
- Le terrain, les rochers et la taille de l'arène sont envoyés au début de la
  manche, pour que tout le monde joue sur le même plateau.

## Les caméras et l'affichage

- Quatre caméras (**C** pour changer) : suivi, vue d'ensemble, poursuite
  rapprochée, et dessus. **V** bascule en vue plate, vue de dessus du terrain
  entier.
- Le bandeau montre la longueur, l'horloge, la caméra courante, le meilleur
  record, l'emplacement d'objet et, en multijoueur, la liste des joueurs avec
  leur longueur.
- Un gain de longueur s'annonce en vert à côté du nombre, une perte en rouge.

## Le menu

- **PLAY SOLO**, **MULTIPLAYER** (héberger / rejoindre avec saisie d'IP),
  **GRAPHICS**, **QUIT**. Il se parcourt à la souris comme au clavier.
- La page **GRAPHICS** règle :
  - la finesse du maillage du serpent : `SIMPLE`, `SMOOTH` (défaut), `FINE` ;
  - la **synchronisation verticale**, activée ou non ;
  - la **limite d'images par seconde** : illimité, 30, 60, 120, 144, 240 ;
  - le **mode debug**, qui affiche un compteur d'images en bas à gauche.
- Tous ces réglages, le record et la dernière adresse IP utilisée sont
  conservés d'une session à l'autre.
