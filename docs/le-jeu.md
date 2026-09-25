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
  Les rivaux du solo comptent comme des joueurs.
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

Cinq objets apparaissent au sol, en plus de la matière. Un seul peut être
rangé à la fois dans l'emplacement.

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

### Les ciseaux de cristal

**Rares** : les premiers apparaissent entre 25 et 45 secondes de manche, les
suivants entre 45 et 75. Deux lames de verre cyan croisées, plus grandes que
les autres objets, qui s'ouvrent et se ferment en tournant sur elles-mêmes.

Ils se rangent dans l'emplacement et se déclenchent avec **ESPACE**. Pendant
**4 secondes**, le serpent devient de verre cyan, laisse une traînée
d'étincelles, et le bandeau affiche `SHEARS` avec le temps restant.

- Toucher le corps d'un autre serpent ne tue plus : **on le tranche**. La
  victime garde sa tête et la partie avant ; tout ce qui était derrière la
  coupe retombe en gemmes le long du morceau perdu. Rien n'est détruit, la
  victime n'est pas tuée.
- Une coupe au ras de la tête laisse la victime à sa taille de départ.
- Un même passage ne coupe qu'une fois : le même couple ne peut pas se
  retrancher avant **0,6 seconde**. Traverser un corps en longeant la coupe
  entame donc la suite, morceau par morceau.
- Les murs, les rochers et son propre corps restent mortels, et le corps de
  celui qui coupe reste solide pour les autres.
- Une coupe se voit et se sent : gerbe aux couleurs de la victime, onde de
  choc cyan, secousse de caméra pour la victime (et une plus petite pour
  celui qui coupe), et la perte s'affiche en rouge à côté de `LENGTH`.
- C'est le premier objet qui **nuit à quelqu'un d'autre** : le plus gros
  serpent du terrain devient une cible qu'on peut vraiment entamer.

Les rivaux vont chercher les ciseaux quand ils en voient, les sortent dès
qu'un autre corps passe à moins de 9 unités de leur tête, puis foncent sur
le corps le plus proche au lieu de l'éviter.

### L'aimant

**Fréquent** : le premier apparaît entre 12 et 20 secondes de manche, les
suivants entre 18 et 30. Un petit fer à cheval rouge aux pointes blanches.

Il se range dans l'emplacement et se déclenche avec **ESPACE**. Pendant
**6 secondes**, les gemmes à moins de **7 unités** de la tête glissent vers la
bouche : doucement au bord du champ (4 unités/s), vite tout près (14
unités/s). Des anneaux rouges se resserrent sur le sable autour de la tête et
le bandeau affiche `MAGNET` avec le temps restant.

- Seule la matière est attirée ; les objets au sol ne bougent pas.
- Une gemme prise entre deux aimants va vers le plus proche.
- L'aimant déplace les gemmes, il ne les mange pas : c'est toujours la tête
  qui avale, un instant plus tard. Rien n'est créé ni perdu.
- C'est la simulation qui déplace les gemmes, donc en réseau tout le monde les
  voit glisser.

Les rivaux font un petit détour pour ramasser un aimant, et l'allument dès
qu'au moins **5 gemmes** sont à leur portée.

## Les rivaux

Le solo ne se joue plus seul : des serpents pilotés par la machine
partagent le terrain.

- Leur nombre se règle dans le menu, bouton **RIVALS** : `NONE`, 1, 2, 3
  (défaut) ou 4. Le choix est conservé. Avec `NONE`, on retrouve le solo
  d'avant, sur le terrain standard et avec l'écran de fin `TIME`.
- Ils s'appellent **VIPER**, **MAMBA**, **ADDER** et **KRAIT**, chacun avec
  sa couleur — jamais le vert du joueur. Le bandeau les liste par leur nom
  avec leur longueur, comme en multijoueur.
- Ce sont des joueurs à part entière : ils comptent pour la taille du
  terrain (à trois rivaux, c'est le terrain de quatre joueurs, 133 × 89),
  subissent la gloutonnerie, meurent sur les mêmes obstacles, se
  décomposent et réapparaissent. Ils peuvent tuer le joueur et se tuer
  entre eux : **un rival mort est un festin**.
- Ils conduisent comme le pilote automatique : ils visent la matière la
  plus proche, font un détour pour un objet et évitent ce qui les tuerait.
- Ils se servent de leurs objets : un éclair est déclenché après **1 à
  3,5 secondes** d'attente (on voit l'éclair partir, puis l'accélération) ;
  l'anneau fantôme est gardé pour le moment où un corps leur barre la
  route.
- Ils **régurgitent** : chacun se fixe une limite entre **45 et 85** unités
  avalées ; au-delà, il recrache un dixième pour retrouver sa vivacité, au
  plus une fois toutes les 4 secondes. Les plus gloutons deviennent les
  plus grosses cibles.
- À la fin de l'horloge, l'écran affiche **BIGGEST** si l'on est le plus
  long, **OUTGROWN** sinon, avec la place obtenue (« you finished 2nd of
  4 ») et le nom et la longueur du vainqueur. **R** relance une manche
  contre les mêmes rivaux.
- Les rivaux n'existent qu'en solo : une partie en réseau reste entre
  humains.

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

## L'apparence : un lagon solaire

Le jeu se joue en plein après-midi, pas dans une pièce sombre.

- **Le décor.** Un ciel azur qui vire à la pêche à l'horizon, un soleil bas
  qui étire de longues ombres douces, une brume chaude très légère au loin.
  L'arène est une **île de sable** posée dans un **lagon turquoise** : l'eau
  est claire près du bord et plus profonde au large, entourée d'un liseré
  d'écume qui respire, et le soleil y fait scintiller des reflets.
- **Le sol.** Un dallage de sable chaud, avec des reflets de lumière qui
  ondulent en permanence, comme au fond d'une eau peu profonde. Les bords
  rosissent vers les remparts.
- **Les remparts** sont corail, surmontés d'un liseré lumineux : le bord du
  monde se voit toujours.
- **Les rochers** sont des pierres pastel lilas ; les plus gros portent un
  cristal lumineux.
- **La matière** est faite de **gemmes** taillées à facettes, qui tournent
  sur elles-mêmes et scintillent. Leur couleur dit leur valeur :
  **turquoise** pour les miettes, **rose** pour les moyennes, **or** pour les
  grosses, qui brillent aussi davantage. Chacune pose une petite flaque de
  lumière colorée sur le sable.
- **Les serpents** ont de grands yeux blancs à pupille noire, une rangée de
  taches claires sur le dos, un reflet de lumière qui descend lentement le
  long du corps, et deux teintes de la tête à la queue.
- **L'interface** est en verre dépoli blanc, à l'encre bleu nuit, avec une
  police épaisse et arrondie. Le menu porte un logo `SNAKE 3D` multicolore
  dont les lettres ondulent.

### Les effets

Aucun effet ne touche aux règles ; ils ne font que montrer ce qui se passe.

| Moment | Effet |
| --- | --- |
| Une gemme avalée (par n'importe quel serpent) | une gerbe d'étincelles de la couleur de la gemme |
| Un serpent meurt | une grosse gerbe à ses couleurs et une onde de choc sur le sol |
| Un serpent réapparaît | une gerbe et une onde claire |
| Une caisse s'ouvre | des confettis de toutes les couleurs |
| Un serpent est boosté | une traînée d'étincelles derrière sa tête |
| En permanence | du pollen lumineux flotte dans l'air au-dessus de l'île |
| Vous mourez | la caméra est secouée ; un peu aussi si quelqu'un meurt près de vous (moins de 14 unités) |
| Vous ouvrez une caisse | une petite secousse |
| Les 10 dernières secondes | l'horloge donne un coup à chaque seconde |

En réseau, les gerbes d'avalement, de mort et de réapparition s'affichent
aussi chez les clients (elles sont déduites de l'état reçu) ; les confettis
de caisse n'apparaissent que chez l'hôte et en solo.

## Les caméras et l'affichage

- Quatre caméras (**C** pour changer) : suivi, vue d'ensemble, poursuite
  rapprochée, et dessus. **V** bascule en vue plate, vue de dessus du terrain
  entier.
- Le bandeau montre la longueur, l'horloge, la caméra courante, le meilleur
  record, l'emplacement d'objet et, en multijoueur ou contre des rivaux, la
  liste des serpents avec leur longueur.
- Un gain de longueur s'annonce en vert à côté du nombre, une perte en rouge.

## Le menu

- **PLAY SOLO**, **RIVALS** (nombre d'adversaires en solo, voir « Les
  rivaux »), **MULTIPLAYER** (héberger / rejoindre avec saisie d'IP),
  **GRAPHICS**, **QUIT**. Il se parcourt à la souris comme au clavier ; un
  réglage qui défile garde la sélection, on peut donc l'appuyer plusieurs fois
  de suite.
- La page **GRAPHICS** règle :
  - la finesse du maillage du serpent : `SIMPLE`, `SMOOTH` (défaut), `FINE` ;
  - la **synchronisation verticale**, activée ou non ;
  - la **limite d'images par seconde** : illimité, 30, 60, 120, 144, 240 ;
  - les **effets** : `FULL` (défaut) ou `LIGHT`. `LIGHT` retire ce qui
    n'est que décoratif (le pollen et les traînées de boost) et garde ce
    qui informe (gerbes, ondes de choc, secousses) ;
  - le **mode debug**, qui affiche un compteur d'images en bas à gauche.
- Tous ces réglages, le record et la dernière adresse IP utilisée sont
  conservés d'une session à l'autre.
