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

## La charte : un lagon solaire, lumineux et sucré

Le propriétaire a demandé un jeu **lumineux, joli, plein d'effets**, qui
donne envie d'y revenir, et qui reste jouable. La charte sombre (sol
bleu nuit, motes blanches) a été remplacée par un après-midi ensoleillé :
ciel azur et pêche, île de sable dans un lagon turquoise, cristaux pastel,
remparts corail, gemmes colorées. Tout le détail est dans
[`le-jeu.md`](le-jeu.md#lapparence--un-lagon-solaire).

Ce qui a été décidé en chemin, et pourquoi :

- **La valeur d'une gemme se lit à sa couleur** (turquoise → rose → or),
  plus seulement à sa taille. Sur un sol clair, le blanc ne se distingue
  plus ; une teinte, si.
- **Tout ce qui compte pour jouer est saturé**, le décor est pâle. Le
  premier essai était surexposé : sol presque blanc, gemmes brûlées en
  blanc. On a baissé la lumière ambiante et l'exposition, foncé le sable, et
  réduit l'émission des gemmes plutôt que de l'augmenter. Règle retenue :
  sur fond clair, **plus d'émission veut dire plus blanc, pas plus
  coloré**.
- **Les surfaces additives ignorent le brouillard** (halos, étincelles, ondes
  de choc). Sinon le brouillard s'ajoute à chaque pixel du quad et une
  étincelle ronde devient un carré pâle vue de loin — c'était visible sur
  toute l'arène en vue d'ensemble.
- **L'interface est claire** (verre blanc, encre bleu nuit) pour aller avec
  le décor. Les couleurs d'interface sont donc distinctes des couleurs des
  serpents : `GOOD_COLOR` remplace le vert pâle de la tête du joueur partout
  où il servait de texte.
- **Les effets passent par l'état du jeu, pas par les événements**, là où
  c'est possible : une mort, une réapparition ou une gemme avalée sont
  détectées en comparant l'état d'une image à l'autre. Ainsi les clients
  réseau les voient aussi, sans rien changer au protocole.
- **Pas de compteur de série au centre de l'écran.** Un `x6 STREAK` qui
  comptait les gemmes avalées à la suite a été essayé puis retiré à la
  demande du propriétaire : il ne rapportait rien et encombrait l'image.
  Règle retenue : **un affichage qui ne sert pas le jeu n'a pas sa place au
  milieu de l'écran**. Les effets vivent dans le monde (gerbes, ondes), pas
  en surimpression.
- **Un réglage `EFFECTS`** (`FULL` / `LIGHT`) plutôt qu'un choix imposé, dans
  l'esprit du réglage de finesse du corps. `LIGHT` retire seulement le
  décoratif.
- Les ombres du soleil portent désormais jusqu'à **150 unités**, assez pour
  la plus grande arène vue en vue d'ensemble (c'était un point ouvert).
- La géométrie reste low poly : une gemme compte 8 triangles, contre 56
  pour l'ancienne bille ; les cristaux ont 4 faces.

## Le rendu est en Forward+ (Vulkan)

Choisi à la suite d'un plantage du pilote graphique en mode compatibilité. Le
mode compatibilité reste disponible en repli. Le plantage était intermittent
et n'a jamais pu être reproduit à la demande : c'est une atténuation, pas une
correction prouvée.

## Les rivaux sont des joueurs, pas des obstacles

Le solo manquait d'adversaire alors que le jeu savait faire tourner
plusieurs serpents. Les rivaux sont donc de **vrais serpents du match** :
mêmes règles, même gloutonnerie, même mort, même décomposition, et ils
comptent pour la taille du terrain. Rejeté : des ennemis d'un autre genre
avec leurs propres règles, qui auraient doublé le code des collisions et
cassé l'économie de la matière.

Leur conduite réutilise le pilote automatique de l'auto-test ; ce qui leur
est propre (usage des objets, régurgitation) vit à part, dans le cerveau du
rival, pour que le pilote reste le même pour les tests. Conséquence à
connaître : **toute amélioration du pilote rend les rivaux plus forts**, et
l'auto-test joue désormais contre eux.

Ils sont limités à quatre, parce qu'il n'y a que quatre couleurs de
serpent en plus de celle du joueur. Ils restent hors du multijoueur : une
partie en réseau reste entre humains, et l'hôte n'aurait pas à simuler des
joueurs que personne ne voit arriver.

## Points laissés ouverts

- Les rivaux ont tous le même niveau et presque le même caractère. Des
  personnalités (chasseur, prudent, glouton) ou une difficulté réglable sont
  la suite naturelle.

- Le jeu est **entièrement muet**. C'est, de loin, le plus gros manque
  identifié pour le plaisir de jeu.
- Rien ne monte en tension à l'intérieur d'une manche : la minute 4 ressemble
  à la minute 1.
- Il reste de rares à-coups d'affichage, une image sur cinq mille environ,
  dont le temps ne passe pas dans le code du jeu ; ils n'ont pas été
  expliqués.
- La première image d'une manche coûte jusqu'à 70 ms environ depuis la
  nouvelle charte (nouveaux shaders et particules compilés au premier
  affichage). Le reste de la manche tourne autour de 2,5 ms par image. Un
  préchauffage des shaders au menu est la piste.
- Les gemmes restent un peu pastel en vue rapprochée : le ciel s'y reflète et
  le tone mapping ACES désature ce qui est très clair. Pousser leur émission
  les blanchit ; la piste serait un autre tone mapper (AgX) ou une teinte
  plus sombre.
