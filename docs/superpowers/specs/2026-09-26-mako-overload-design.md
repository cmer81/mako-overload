# MAKO OVERLOAD — design

Stage spécial pour `ze_ffvii_mako_reactor_v5_3` (CS:S), **serveur de test uniquement** dans un premier temps.

## 1. Intention

- Un mode qui ne recopie pas les autres (base EX2 + lasers à positions fixes + boss renforcé).
- La map **réagit aux joueurs** : lasers qui traquent le groupe, surtensions aléatoires, pression qui monte avec la progression.
- Critère de succès : les joueurs n'ont jamais vu ça sur Mako, le round reste jouable et gagnable.
- Tous les textes affichés en jeu sont **en anglais**.

## 2. Contraintes techniques (vérifiées)

- CS:S avec VScript (Squirrel, API type TF2) : `Entities.FindByClassname/FindByName`, `GetTeam`, `IsAlive`, `GetOrigin`, `GetVelocity`, `SetOrigin`, `EntFireByHandle`, `AddThinkToEnt`, `ScreenFade`, `ScreenShake`, `ClientPrint`, `SetGravity`, `TraceLine`, `NetProps` — toutes utilisées par les scripts NiDE existants.
- Scripts chargés par le stripper via la clé `vscripts` (`logic_script`), comme les autres maps NiDE.
- Le compte à rebours de fuite de la map est fixe : `huida_e` → `finalf` à 129,5 s, puis `boom`.
- Humains = équipe 3 (CT), zombies = équipe 2 (T).
- Entités réutilisées (déjà en production dans ZEDDYS cmer / RMZS cmer) :
  - `EX4ZeddysLaserMaker` + `EX4ZeddysLaserTemp` (laser Sephiroth, origine de template `-11206 4010.99 48`) ;
  - `EX4EndLaserTemp` (lasers de fin saut/accroupi) ;
  - `EX3RMZSCmerBridgeRot` + logique VScript de `puente_1` (OnUser2/3/4) ;
  - `seph_modelo2_ex2` (modèle Sephiroth), `espad` (son), `explosion_mako_random`, `victoria`, `Score100`.

## 3. Déroulé du round

Base : parcours Extreme II (portes, pont, core, Bahamut EX2, poursuite finale), équilibrage EX2 (items, zombies).

### 3.1 Jauge d'instabilité (0 → 100 %)

- HUD permanent (haut d'écran) : `MAKO ☢ 47% — STABLE`, couleur vert → rouge.
- Monte de **+1 % toutes les 4 s**, et par bonds :

| Évènement | Bond | Source |
|---|---|---|
| Porte du haut (bouton `boton` hammerid 1754) | +5 % | OnPressed |
| Pont traversé | +5 % | nouveau `trigger_once` `MakoOverloadBridgeTrig` (brush `*124`, `-9348 5354.39 120`, même zone que `trigger_n_d3`) |
| Arrivée au core (`CoreTrigger`, hammerid 1996) | +10 % | OnStartTouch |
| Bahamut à 50 % de vie | +10 % | le script lit `bahamut_vida` (`m_OutValue`), retient la valeur max vue et déclenche à ≤ 50 % de ce max |
| Bahamut tué (`bahamut_vida` OnHitMin) | +15 % | OnHitMin |

- Plafonnée à **95 %** avant la fuite ; **100 % = OVERLOAD** au début de la fuite (`comienza_huida`).

### 3.2 Paliers

| Jauge | Palier (HUD) | Surtension | Laser traqueur |
|---|---|---|---|
| 0–33 % | STABLE | toutes les 90 s | toutes les 20 s |
| 34–66 % | UNSTABLE | toutes les 60 s | toutes les 15 s |
| 67–95 % | CRITICAL | toutes les 40 s | toutes les 10 s |
| 100 % | OVERLOAD | effets de surcharge (§6) | toutes les 5 s |

### 3.3 Répits (ni laser ni surtension)

- 45 premières secondes du round ;
- descente de l'ascenseur vers le core : répit de 25 s à partir du départ de `ascensort` (OnStart) ;
- 10 premières secondes après `bahamut_entry`.

## 4. Lasers traqueurs

1. Collecte des humains vivants ; **cluster principal** = le plus grand groupe dans un rayon de 600 unités (centre = moyenne des positions, direction = vitesse moyenne horizontale ; si immobile, direction du regard moyen).
2. Point de tir : **derrière le groupe**, à 400–900 unités, orienté vers le groupe. Validation par `TraceLine` (espace libre ≥ 400). Sinon essai à ±90° ; sinon **pas de tir**, nouvel essai dans 3 s.
3. Télégraphe **1,5 s** : `seph_modelo2_ex2` apparaît au point de tir, son `espad`, texte centre **`⚠ JUMP!`** ou **`⚠ CROUCH!`**.
4. Tir : `EX4ZeddysLaserMaker` placé (origine + angles) puis `ForceSpawn`. Hauteur saut / accroupi calculée depuis le sol du groupe, calibrée sur les couples ZEDDYS existants.
5. Laser **mortel** pour les humains (filtre `humanos`), sans effet sur les zombies.

| Palier | Types | Particularité |
|---|---|---|
| STABLE | saut | 1 laser |
| UNSTABLE | saut / accroupi | 1 laser |
| CRITICAL | saut / accroupi | 30 % de chance d'un doublé (saut puis accroupi +1,2 s) |
| OVERLOAD | saut / accroupi alternés | toutes les 5 s |

Aucun tir si aucun humain vivant ou pendant un répit.

## 5. Surtensions

Séquence : **2 s d'alerte** (flash vert `ScreenFade`, `ScreenShake`, alarme du jeu de base, texte `⚡ MAKO SURGE: <EFFECT>`) → effet. Tirage pondéré, jamais deux fois le même effet d'affilée.

| Effet (texte) | Action | Durée | Dès |
|---|---|---|---|
| `LOW GRAVITY` | `SetGravity(0.35)` sur tous les joueurs | 10 s | STABLE |
| `BLACKOUT` | `ScreenFade` quasi noir (HUD visible) | 8 s | STABLE |
| `BRIDGE FLIP` | `puente_1` FireUser2 + rotation retour à +15 s | 15 s | UNSTABLE |
| `BARRAGE` | 3 lasers traqueurs espacés de 1,5 s | ~5 s | UNSTABLE |
| `MAKO RAGE` | zombies rouges, `m_flLaggedMovementValue` 1,3 | 6 s | CRITICAL |

Garde-fous :
- `BRIDGE FLIP` seulement si aucun humain à moins de 800 unités du pont, et jamais après le début de la fuite ; sinon retirage.
- Gravité et vitesse **toujours restaurées** : fin d'effet, mort du joueur, `Overload_Stop()`, début de round (`OnNewGame` remet déjà `gravity 1`).
- Pas de surtension pendant un répit.

## 6. OVERLOAD : fuite et fin

### 6.1 Déclenchement (début de fuite)

- Jauge 100 %, texte **`☢ REACTOR OVERLOAD ☢`**, flash blanc, grosse secousse.
- Pulsation rouge permanente légère (`ScreenFade` en boucle, faible alpha).
- Musique : `#music/zeddy/the_qemists_no_more.mp3` (déjà téléchargée par le plugin quand un stage zeddy est présent).

### 6.2 Fuite

- **150 s** : `huida_e` n'est pas activé ; un relay `MakoOverloadEscape` (copie de `huida_e` décalée, messages `** N SECONDS LEFT **`, `finalf` à 149,5 s) est déclenché par `comienza_huida` (AddOutput depuis le relay du mode). Le BOMB TIMER affiche un décompte cohérent.
- Lasers traqueurs toutes les 5 s (saut/accroupi alternés).
- `explosion_mako_random` PickRandom toutes les ~12 s (visuel/son).
- Pas de `LOW GRAVITY` ni `BLACKOUT` pendant la fuite.
- Poursuite Bahamut EX2 inchangée.

### 6.3 Fin — « Sephiroth's last stand »

- `finalf` → trigger de contrôle (zone de fin `*213`, `-10880 4410 128`, filtre `humanos`) → `TouchTest`.
- Humains présents : `BombTimer*` tués, `boom` désactivé, Sephiroth sur le pont final, **3 vagues** `EX4EndLaserTemp` en 10 s (avant/arrière, saut/accroupi), puis trigger de victoire.
- Victoire : flash blanc, `** YOU SURVIVED THE MAKO OVERLOAD! **`, `victoria`, `Score100` + bonus EX3HellzWin (rendercolor / health / speed au round suivant), `boom` réactivé + déclenché (zombies), HUD `MAKO ☢ STABILIZED`, `LevelCounter` → 6, `sm_makovote`.
- Personne : `** NO ONE HAS ESCAPED! **`, `boom` normal.

## 7. Architecture

### 7.1 Stripper — section `MODE: MAKO OVERLOAD`

- `LevelCounter` : `max` 17, `Case17` → `LevelRelayMakoOverload` + items EX2 (32 s / 47 s / ultima core 35 s).
- Bouton admin room `ButtonMakoOverload`, hammerid **100012**, `-4472 -3333 1396` (rangée du haut, après RMZS cmer), double appui comme les autres.
- `LevelRelayMakoOverload` : base EX2 (même liste que ZEDDYS cmer, sans les éléments ZEDDYS), `huida_e` non activé, AddOutputs vers le script (bonds de jauge, répits, début de fuite), `MakoOverloadScript` → `RunScriptCode Overload_Start()`.
- `logic_script` `MakoOverloadScript`, `vscripts` = `mako_overload/overload.nut` : inerte tant que `Overload_Start()` n'est pas appelé.
- `game_text` `MakoOverloadHud` (canal 1) : mis à jour par le script (`AddOutput message` + `Display`).
- Relay `MakoOverloadEscape` (150 s), trigger de fin `MakoOverloadCheck`, relay `MakoOverloadEnding`, trigger `MakoOverloadWin`.
- Les modes existants ne sont pas modifiés.

### 7.2 Script `scripts/vscripts/mako_overload/overload.nut` (serveur uniquement)

Découpage en fonctions à responsabilité unique :
- **état** : jauge, palier, timers, répits, effet en cours ; remis à zéro à chaque round (le `logic_script` est recréé) ;
- **think** (`AddThinkToEnt`, ~0,25 s) : avance du temps, montée de jauge, déclenchement lasers/surtensions, HUD 1×/s ;
- **groupe** : collecte humains vivants, cluster principal, direction ;
- **laser** : choix du point de tir + `TraceLine`, télégraphe, tir ;
- **surtensions** : un couple `start/stop` par effet, restauration garantie ;
- **overload / fin** : appelées par le stripper ;
- **debug** : fonctions publiques ci-dessous.

API appelée par le stripper : `Overload_Start()`, `Overload_Add(n)`, `Overload_Respite(seconds)`, `Overload_EscapeStart()`, `Overload_Stop()`.

### 7.3 AdminRoom

Stage `"Mako Overload"`, triggers `14`, `overload`, `makooverload`, action `#100012:FireUser1`.

### 7.4 Hors périmètre (pour l'instant)

- Pas d'entrée dans le vote MakoVote (plugin non modifié).
- Pas de déploiement sur le serveur principal ni dans les repos NiDE avant validation.

## 8. Déploiement et tests

- Serveur de test `fe4451bc` uniquement : stripper (`configs/stripper/maps/`), config AdminRoom, `scripts/vscripts/mako_overload/overload.nut` ; sauvegarde `.bak-overload` de chaque fichier existant.
- Supprimer `scripts/vscripts/cmer_probe.nut` (sonde jetable).
- Outils console :

| Commande | Effet |
|---|---|
| `script Overload_Debug()` | jauge, palier, timers, cluster visé |
| `script Overload_SetGauge(80)` | fixe la jauge |
| `script Overload_Surge("lowgrav")` | force un effet (`blackout`, `bridge`, `barrage`, `rage`) |
| `script Overload_Laser()` | force un laser traqueur |
| `script Overload_Stop()` | arrête le mode, restaure les joueurs |

- Scénarios à valider : lancement (`sm_stage overload`), HUD et paliers, lasers dans couloirs étroits (pas de tir dans un mur), chaque surtension et sa restauration, `BRIDGE FLIP` refusé près du pont, OVERLOAD et fuite 150 s, fin avec et sans humains, round suivant sans effet résiduel, autres modes intacts.
