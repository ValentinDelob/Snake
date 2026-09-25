# Méthode de travail

Ce projet a une règle non négociable, posée par son propriétaire : **une
fonctionnalité n'est jamais terminée tant qu'elle n'a pas été jouée**. Le
code qui s'importe sans erreur ne prouve rien.

## La boucle obligatoire

Pour chaque fonctionnalité, dans cet ordre :

1. **Analyser** l'existant avant d'écrire quoi que ce soit.
2. **Choisir une seule fonctionnalité.**
3. **Implémenter.**
4. **Construire** l'exécutable.
5. **Lancer réellement le `.exe`** et exercer la fonctionnalité.
6. **Lire les journaux** et vérifier qu'aucune erreur n'y figure.
7. **Faire tourner les auto-tests** (solo et réseau).
8. **Commiter sur `main`** — et seulement si tout ce qui précède est vert.
9. **Faire un compte-rendu court** : fonctionnalité, résultat de la
   construction, confirmation que l'exécutable a tourné, résultat des tests,
   vérification des journaux, empreinte du commit.
10. **Demander quelle fonctionnalité ajouter ensuite**, puis attendre.

Si quelque chose échoue à n'importe quelle étape : **ne pas commiter**.
Corriger, reconstruire, relancer, revérifier.

**Une fonctionnalité par commit.** Si une correction indépendante s'avère
nécessaire en cours de route, elle fait l'objet de son propre commit.

## Construire et lancer

Tout part de la racine du dépôt.

| But | Commande |
| --- | --- |
| Construire `dist\snake.exe` | `powershell -ExecutionPolicy Bypass -File build.ps1` |
| Jouer | lancer `dist\snake.exe` |
| Démonstration pilotée par un bot | `dist\snake.exe --demo` |
| Auto-test complet | `dist\snake.exe --selftest` |

Le jeu écrit un journal complet dans
`%APPDATA%\Godot\app_userdata\Snake 3D\logs\snake.log`. **C'est la seule
trace qui reste quand la fenêtre est fermée** : toute vérification passe par
là. Attention, un processus tué de force ne vide pas son journal ; il faut
fermer la fenêtre proprement.

### Options utiles

| Option | Effet |
| --- | --- |
| `--selftest` | joue une partie scriptée puis rend un verdict `SELFTEST PASS/FAIL` |
| `--demo` | un bot conduit le serpent |
| `--host` / `--join <ip>` | ouvre ou rejoint une session au démarrage |
| `--round-seconds <n>` | raccourcit la manche (pratique pour les tests) |
| `--start-score <n>` | démarre avec de la matière déjà avalée |
| `--rivals <n>` | impose le nombre de rivaux en solo, quel que soit le menu |
| `--profile` | mesure les images, sans synchronisation verticale |
| `--profile-capped` | même mesure, dans les conditions réelles du joueur |

En mode `--demo`, quatre touches posent un objet : **B** un éclair, **N** une
caisse (tour à tour bonus et malus), **K** des ciseaux et **J** un aimant, juste
devant vous.

## L'auto-test

C'est le filet de sécurité principal. Il **joue vraiment** : il injecte de
vraies touches, traverse tous les écrans, toutes les caméras, déclenche
chaque objet, meurt, revient, et attend la fin de l'horloge. Il lit ensuite
le journal pour s'assurer qu'aucune erreur moteur n'y est apparue, puis
affiche une ligne de verdict qui résume tout ce qu'il a observé.

Depuis l'arrivée des rivaux, il fait défiler le bouton `RIVALS` sur toutes
ses valeurs avant de jouer, puis joue **contre trois rivaux** (le réglage
par défaut) : un rival peut donc tuer le serpent de test ou lui voler un
objet en pleine phase, et les phases savent recommencer pour cette raison.
Les règles propres aux rivaux (tirer un éclair, régurgiter un dixième) sont
vérifiées une fois les phases scriptées finies, pour ne pas les perturber.

L'auto-test ne peut pas juger si c'est beau. Pour l'apparence, il vérifie
seulement que :
- le décor est bien sous un ciel ;
- le réglage `EFFECTS` éteint et rallume le pollen ;
- au moins dix gerbes d'effets partent pendant une manche ;
- une mort secoue la caméra.

**Le jugement visuel se fait sur des captures de l'exécutable réel**, dans
chaque caméra. C'est ce qui a montré que le premier essai de la charte était
surexposé et que les halos formaient des carrés vus de loin.

**Toute règle nouvelle doit être ajoutée à l'auto-test.** C'est ce qui a
permis d'attraper, entre autres : un serpent qui réapparaissait face à un
rocher, un bouton de menu qui répondait encore aux touches en pleine partie,
et une dispersion de matière qui sortait d'un tableau et faisait tomber le
jeu de 60 à 7 images par seconde.

Deux principes se sont dégagés à l'usage :

- **Ne jamais mesurer un effet sur un serpent mort.** Une mort interrompt
  tout ; la phase doit recommencer au lieu d'écrire une demi-mesure.
- **Une touche injectée n'est lue qu'à l'image suivante.** Déclencher et
  vérifier doivent être deux étapes séparées, sinon on déclenche deux fois.

Quand une règle est trop dépendante du hasard pour être pilotée (par exemple
faire passer une tête dans sa propre queue en une seconde), on la vérifie
**directement sur les règles** plutôt qu'en conduisant le serpent : on met en
place la situation et on regarde ce que la simulation en dit.

## Les outils

Dans `game/tools/`, lancés avec Godot en mode sans affichage :

| Outil | Ce qu'il vérifie |
| --- | --- |
| `check_arena.gd` | pose deux mille terrains et vérifie les promesses de placement des rochers |
| `bench_mesh.gd` | mesure le coût du maillage du serpent selon sa longueur et le mode graphique |

Le harnais qui pilote la fenêtre (captures d'écran, injection de touches,
lancement de plusieurs instances en réseau) vit hors du dépôt, dans le
dossier de travail temporaire de la session.

## Conventions

- **Le code et l'interface sont en anglais**, les échanges avec le
  propriétaire sont en français.
- Les commentaires expliquent **pourquoi**, pas quoi. On écrit dans le style
  du fichier voisin.
- Les messages de commit décrivent le problème, la décision et la preuve
  (ce qui a été observé sur l'exécutable réel).
- Les réglages numériques vivent tous dans un fichier de constantes partagé :
  on ne sème pas de nombres magiques dans les règles.
