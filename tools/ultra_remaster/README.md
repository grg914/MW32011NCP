# MW3 Ultra Remaster: campagne x64, SSGI, HDR10 natif et FPS

Statut : cette branche contient deux profils INI réversibles et des tests.
Les fonctions HDR10 natif et SSGI ne sont PAS encore implémentées.
Le DLSS 5 Neural Rendering est encore expérimental et non fonctionnel
dans le fork à cette date. Les binaires NVIDIA sont hors du dépôt.

## Exigences du remaster Ultra

Le jeu ciblé est Call of Duty: MW3 (2011), mode Campagne uniquement,
exécutable iw5sp.exe x64, RTX 5060 Ti 16 Go.
Le projet NE prévoit PAS de ray tracing matériel : on utilise SSGI,
Screen-Space Global Illumination, pour le rebond lumineux approximatif.
Objectifs visuels, tous activables indépendamment :
1. Textures HD 2K/4K, amélioration IA hors rendu en temps réel,
   remplacement des textures IW5, matériaux PBR lorsque leurs shaders et
   données additionnelles seront effectivement compatibles (une texture
   augmentée ne crée pas un matériau PBR à elle seule).
2. SSGI pour éclairage indirect + ombres et occlusion ambiante améliorées,
   en conservant des options de repli de qualité plus légère.
3. Reflets en espace écran (SSR si réalisable), brouillard et effets
   atmosphériques mesurés au GPU ; pas de ray tracing matériel.
4. Géométrie et modèles 3D revisités au niveau des assets IW5.
   Ce chantier est indépendant du SSGI et demande un pipeline d'assets.

## Profils FPS disponibles maintenant

La configuration mw3ncp_config.ini doit d'abord être créée en démarrant
la campagne avec MW32011NCP installé. Depuis Windows PowerShell dans le
répertoire d'un clone de ce fork, effectuer un essai sans écriture :

    powershell -NoProfile -File .\tools\ultra_remaster\apply_campaign_profile.ps1 -ConfigPath "C:\SteamLibrary\steamapps\common\Call of Duty Modern Warfare 3\mw3ncp_config.ini" -Profile FpsFirst -DryRun

Retirer -DryRun seulement après inspection. L'outil ne modifie que des
clés de configuration reconnues, en conservant les autres paramètres,
et sauvegarde l'original dans un fichier .bak horodaté avant toute
écriture. Il n'installe PAS de DLL ni de mod ReShade.

FpsFirst, priorité à la fluidité :
- Vulkan + StreamlineEnabled=1 (si le DLSS classique est déjà fonctionnel).
- InternalRenderScalePercent=67 et DLSSModeX64=3 (mode eMaxQuality).
- TextureRenderRes=1x ; pas de génération IA de textures dans le benchmark.
- Filtrage anisotrope 16x et optimisations moteur existantes activés.
- Ombres haute qualité et recalcul d'éclairage coûteux désactivés.
- DlssNeuralRenderingEnabled=0 : ne pas tenter de DLSS 5 non implémenté.

UltraPreview, pour comparaison après stabilisation du premier profil :
- InternalRenderScalePercent=75 ; DLSSModeX64=3.
- TextureRenderRes=2x, avec pré-cache massif désactivé.
- ForceHighQualityShadows=1.
- Les autres optimisations restent actives.

Précision : la résolution de rendu est contrôlée par
InternalRenderScalePercent, pas par DLSSModeX64. Au-dessus de 100 % le
patch bascule automatiquement vers DLAA et le coût augmente.
Le jeu d'origine pouvant déjà calculer son image à une résolution interne
inférieure à 67 % de l'écran, on NE promet aucun gain FPS avant mesure.

Pour tester une autre échelle sans dépasser 100 % :

    powershell -NoProfile -File .\tools\ultra_remaster\apply_campaign_profile.ps1 -ConfigPath "C:\chemin\mw3ncp_config.ini" -Profile FpsFirst -RenderScalePercent 60

Redémarrer le jeu : les render targets sont initialisés au lancement.

IMPORTANT : iw5sp.exe héberge à la fois la Campagne et la Survie. Les
configurations globales s'appliquent techniquement aux deux ; ne jouer
qu'en campagne pour cette phase. Le futur code de SSGI/HDR doit détecter
le mode Campagne explicitement, et pas seulement le nom de l'exécutable.
Le multijoueur iw5mp.exe et les anti-triches sont hors périmètre.

## Implémentation SSGI proposée

SSGI = illumination globale en espace écran. Réutiliser les buffers
de la scène et la profondeur déjà accessibles dans le pipeline Vulkan
(DXVK) du fork. Le projet possède une infrastructure de tagging de
profondeur/couleurs et un point de composition de scène AVANT le HUD dans
streamline_resources_x64.cpp et streamline_evaluate_x64.cpp.
Le SSGI n'est pas un filtre de couleurs sur le backbuffer final.

Prototype à ajouter comme passe Vulkan explicite :
1. Capturer la scène éclairée AVANT son tone mapping SDR, la profondeur
   et, si possible, les normales de surface. Si les normales sont absentes,
   les reconstruire depuis la profondeur, avec contrôle des discontinuités.
2. Marcher des rayons d'écran peu nombreux dans le depth buffer à partir
   de points de surface ; échantillonner la radiance de la scène aux
   intersections pour approcher le rebond diffus.
3. Calculer cette passe à la moitié de la résolution INTERNE (1/4 pixels),
   ou au quart sur matériel limité ; nombres d'échantillons adaptatifs,
   rayon d'action et résolution paramétrables.
4. Filtrer le bruit avec un débruitage bilatéral en profondeur/normales.
   Ajouter une accumulation temporelle uniquement si les vecteurs de
   mouvement sont suffisamment fiables, sinon éviter un ghosting excessif.
5. Composer l'indirect sur la scène en lumière linéaire AVANT DLSS
   Super Resolution ; effectuer l'upscaling DLSS de l'image complète
   ensuite. Respecter le pipeline HDR lorsqu'il sera disponible.
6. Préserver une voie sans SSGI, sans changer le rendu original, ainsi
   qu'un repli SSAO. Limiter l'utilisation des buffers historiques.

Limites physiques : le SSGI ne voit ni les objets hors écran ni les
surfaces occultées, peut perdre l'éclairage près des bords, n'invente
pas les volumes 3D du monde et nécessite une source de radiance utile.
Ne jamais le décrire comme un équivalent complet du ray tracing.

Budget cible de DEVELOPPEMENT (pas un résultat benchmark) :
- Résolution interne 1080p/1440p : tenter <= 2 ms GPU en mode SSGI
  Qualité et <= 1 ms GPU en mode Performance ; les valeurs sont des
  cibles de conception à vérifier sur la RTX 5060 Ti, pas des garanties.
- Dès que la marge FPS manque, réduire d'abord le nombre de pas,
  la résolution SSGI et la longueur des rayons.
- SSGI doit pouvoir être désactivé sans changer le profil DLSS.

## HDR10 natif : exigences et limites

L'utilisateur demande du vrai HDR natif, pas ReShade FakeHDR, Windows
Auto HDR ou NVIDIA RTX HDR. Pour cela il faut préserver des valeurs
de luminance non écrêtées AVANT tone mapping SDR et les présenter
sur une swapchain compatible HDR, avec métadonnées correctes.

L'architecture IW5 est D3D9 traduite via DXVK vers Vulkan :
- Localiser le buffer de scène linéaire/HDR avant toute conversion SDR.
- Conserver les valeurs hautes lumières à travers SSGI et DLSS.
- Gérer le HUD séparément avec une luminance papier calibrée.
- Convertir vers BT.2020/PQ ST 2084 et gérer tone mapping/peak nits.
- Vérifier sur la surface Vulkan les formats et espaces couleurs :
  VK_EXT_swapchain_colorspace, VK_COLOR_SPACE_HDR10_ST2084_EXT, et
  VK_EXT_hdr_metadata lorsque disponibles.
- Assurer un repli SDR sans crash et éviter le double tone mapping.

Les changements de switch HDR ne doivent pas augmenter fortement le
temps de frame. Le SSGI devra être composé en espace linéaire avant
le tone mapping HDR et les éléments d'interface.

## Méthodologie de mesure FPS

Comparer trois configurations sur les mêmes séquences :
1. MW3 de base, puis mod Vulkan sans DLSS.
2. Mod FpsFirst, puis paramètres avec render scale 60/67/75 selon
   l'image obtenue.
3. UltraPreview, puis SSGI à mi-résolution lorsqu'il existera.

Mesurer FPS moyen, 1% low, frametimes CPU/GPU, VRAM et stutters, au
moins trois parcours après initialisation des caches. Comparer une
séquence avec scène ouverte, une scène intérieure et une scène à
effets nombreux. Ne pas activer simultanément textures IA 4x,
supersampling >100%, SSGI haute qualité et HDR expérimental pendant
la recherche des régressions. Le Frame Generation ne corrige pas les
temps de simulation et n'est pas une solution de départ.

## Ordre de réalisation et critères de validation

A. Stabiliser les FPS, mesurer les régressions, tester la sortie DLSS.
B. Développer le pipeline HDR10 natif et les tests de repli SDR.
C. Implémenter SSGI dans un module Vulkan indépendant, avec passe
   débruitage et comparaison A/B par capture.
D. Déployer textures IA 2x et des matériaux ciblés PBR vérifiés.
E. Ajouter SSR, effets atmosphériques et remplacements de géométrie.
F. Examiner séparément DLSS 5 Neural Rendering : requiert le
   bon SDK/header/runtime NVIDIA, validation d'intégration et mesures.

Une étape ne sera déclarée terminée qu'après compilation Windows x64,
tests en jeu en CAMPAGNE, preuve d'activation HDR10 si concerné et
benchmark avant/après ; les scripts actuels ne remplissent pas ces
critères pour SSGI et HDR10.

## Test de la configuration (Windows, pas besoin du jeu)

    powershell -NoProfile -File .\tools\ultra_remaster\test_profiles.ps1

Références internes :
- proxy_d3d9/src/mod_config.cpp, mod_config.h
- proxy_d3d9/src/streamline_evaluate_x64.cpp
- proxy_d3d9/src/streamline_resources_x64.cpp
- re_notes/x64_migration/texture_upscale_cache_research.md


## Code GPU ajouté (prototypes compilés, pas encore chargés par MW3)

Trois vrais shaders GLSL/Vulkan Compute sont maintenant présents dans
tools/ultra_remaster/shaders/ :

- ssgi_trace.comp : passe demi-résolution, profondeur, reprojection
  caméra et ray marching en espace écran, écrit les rebonds estimés
  dans une texture RGBA16F. Cette source suppose une scène LINEAIRE et
  un depth buffer échantillonnable. Elle ne réalise pas encore
  l'accumulation temporelle ou l'upscaling bilatéral.
- ssgi_composite.comp : additionne les rebonds diffus à la radiance
  linéaire de la scène, avant reconstruction DLSS et tone mapping.
  La qualité requiert une interpolation/filtration adaptée.
- hdr10_encode.comp : transforme une image linéaire Rec.709 en
  BT.2020/PQ ST 2084 et limite l'intensité au pic HDR.
  Ne peut pas, à lui seul, transformer une swapchain SDR en HDR10.

Ces shaders ont été compilés et validés dans GitHub Actions via
glslangValidator/spirv-val, mais il n'y a pas encore de pipeline C++
dans MW32011NCP qui alloue leurs ressources, remplit leurs descripteurs
et les déclenche pendant une trame de campagne. Ne pas écrire
SSGIEnabled=1 ou HDR10Native=1 dans l'INI en supposant que ces clés
existent : elles ne sont pas encore intégrées au parseur.

Test de compilation GPU (exécuté automatiquement sur la PR) :
https://github.com/grg914/MW32011NCP/actions/workflows/ultra-remaster-shaders.yml

## Détection Windows x64 du support de surface HDR10

Le fichier tools/ultra_remaster/hdr10_probe_win32.cpp est un EXÉCUTABLE
indépendant compilé sous MSVC x64, sans injection. Il charge vulkan-1.dll
dynamiquement et recherche les formats de surface
VK_COLOR_SPACE_HDR10_ST2084_EXT + 10 bits pris en charge sur un
VkSurfaceKHR Win32 temporaire.

Pour compiler dans l'invite de commandes développeur x64 Visual Studio,
à la racine d'un clone AVEC sous-modules Vulkan-Headers :

    cl /nologo /std:c++17 /EHsc /I "dxvk\include\vulkan\include" "tools\ultra_remaster\hdr10_probe_win32.cpp" /Fe:hdr10_probe.exe /link user32.lib

Puis lancer hdr10_probe.exe sous Windows, idéalement avec l'écran HDR
ciblé comme écran principal. Le programme est en lecture seule et
n'active pas le HDR. La sortie HDR10/PQ détectée indique uniquement
les formats Vulkan exposés par le pilote, non que Windows, le moniteur
et la swapchain interne du jeu les utilisent déjà. Le rendu HDR natif
dans IW5/DXVK demeure un jalon non terminé.

Compilation MSVC x64 validée en CI (ne prouve pas le support HDR du PC) :
https://github.com/grg914/MW32011NCP/actions/workflows/ultra-remaster-hdr-probe.yml


## Nouveau : diagnostic natif branché à la vraie trame Vulkan

À partir du commit du 12 novembre 2026, la DLL du mod appelle
ProbeUltraRenderTargetsX64() depuis RunDlssEvaluateAndCompositeX64,
juste après la résolution MSAA de la scène et avant son évaluation DLSS.
Cette sonde est donc raccordée à **un véritable point du moteur**
contrairement aux shaders GLSL qui restent indépendants.

La sonde est **strictement en lecture seule** : QueryInterface sur les
surfaces D3D9/DXVK, GetVulkanImageInfo et une unique ligne de log
[ultra-renderer-preflight] après obtention des deux surfaces.
Elle n'alloue pas de VkImage, ne change pas les états, ne soumet aucune
commande Vulkan et ne modifie pas l'image affichée.

Le log rapporte :
- taille, format Vulkan, sample count et usage flags du buffer couleur ;
- les mêmes données pour le depth buffer ;
- compatibilité des dimensions, sample unique et présence du flag
  VK_IMAGE_USAGE_SAMPLED_BIT ;
- indication du **format float** du buffer couleur, **sans prétendre**
  prouver que la scène contient de vraies hautes lumières HDR.

Cela permet de trancher une question matérielle concrète : le depth buffer
du jeu est-il directement accessible à un compute shader SSGI, ou faut-il
un chemin de copie/résolution supplémentaire ? Le buffer est-il de type
float pré-tone-map, ou le hook actuel tombe-t-il sur du SDR 8 bits ?

### Tester sur le vrai PC

1. Ne pas fusionner cette PR tant que le build x64 et les tests en jeu
   ne sont pas vérifiés ; pour un essai, construire la branche à part.
2. Installer une build x64 faite depuis cette branche (et les DLL NVIDIA
   autorisées requises par le DLSS classique) dans une copie de test de
   l'installation de MW3.
3. Vérifier le fichier mw3ncp_config.ini :
   [Video] GraphicsApi=Vulkan et StreamlineEnabled=1.
4. Démarrer **une mission de la campagne**, jamais le multijoueur.
   Le mod ne possède pas encore de détecteur fiable qui distingue
   Campagne de Survie : à ce stade le diagnostic uniquement lecture
   n'impose pas de changement de rendu dans ces modes.
5. Lire le log du mod (près de l'installation du jeu selon la
   configuration) et rechercher [ultra-renderer-preflight].
   Ne fournir que la ligne contenant les formats et drapeaux Vulkan,
   sans chemins personnels, lors du diagnostic.
6. Ne pas activer d'option HDR10Native/SSGIEnabled fictive : aucun
   dispatch shader ni swapchain HDR10 n'est encore implémenté.

Après les résultats du log, la prochaine contribution pourra créer
des ressources compute compatibles avec le **format réel** (et non
supposé), et planifier la localisation d'un buffer HDR de scène avant
tone mapping. Le HDR10 côté présentation DXVK ne peut pas être confirmé
par le seul résultat de cette sonde.
