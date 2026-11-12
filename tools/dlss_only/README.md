# MW3 (2011) — DLSS uniquement, compatibilité 4K

**Branche expérimentale : feature/dlss-only-4k-mode-compat.**
Concerne uniquement la campagne Steam x64 et une sortie 3840 × 2160.
Le correctif 4K doit encore être testé en jeu : l'installation actuelle
ne constitue pas une version finale du mod.

## Problème confirmé par l'utilisateur

Sans MW32011NCP : le jeu fonctionne en 3840×2160. Avec MW32011NCP
v0.0.3-x64 : la 4K disparaît des options, maximum 2560×1440,
et une tentative de forcer 3840×2160 est réécrite à 640×480.
Le journal d'une session montrait GraphicsApi=Vulkan et le
backbuffer=640x480, avec StreamlineEnabled=0.
Le retrait du fichier d3d9.dll redonne l'accès à la 4K.

Il ne faut pas confondre résolution de sortie Windows (3840×2160)
et résolution interne avant DLSS (par défaut 67 %).

## Cause probable à vérifier : modes vidéo DXVK

Dans dxvk/src/d3d9/d3d9_adapter.cpp, les modes retournés par
CacheModes sont triés par résolution croissante. Les écrans récents
annoncent souvent de très nombreux modes et taux de rafraîchissement.
Une limite interne au jeu sur le nombre d'entrées pourrait cacher
les derniers modes 4K. C'est une hypothèse technique, pas encore une
cause prouvée par les journaux.

DXVK propose d3d9.modeCountCompatibility=True ; cette option réduit
les modes annoncés tout en conservant le mode courant/registré du
bureau Windows et quelques résolutions de repli.

Dans proxy_d3d9/src/dllmain.cpp, cette branche définit
DXVK_CONFIG="dxvk.enableNvCudaInteropNative=True;
d3d9.modeCountCompatibility=True" lorsque StreamlineEnabled=1.
Elle ne force jamais artificiellement 4K sur un écran non compatible.

Dans proxy_d3d9/src/d3d9_hook.cpp, un diagnostic en lecture seule
se déclenche avant que le jeu commence à initialiser son périphérique :
[dlss-only-mode-diag] signale le nombre de modes, nativeMatches,
fourKMatches et largestMode pour deux formats D3D9.
Cela permet de vérifier si DXVK annonce réellement 3840×2160.

## Installation du profil depuis le jeu de base

Ce script installe une configuration Vulkan + DLSS avec texture IA,
SSGI, HDR expérimental, FSR et motion blur désactivés. Ce n'est
PAS encore une compilation minimaliste débarrassée de tous les
hooks contrôleur du dépôt ; les ressources de DLSS dépendent du
pipeline graphique existant.

1. Garder Windows en résolution native 3840×2160.
2. Récupérer le ZIP x64 officiel de la version v0.0.3-x64 :
   https://github.com/k8se10/MW32011NCP/releases/tag/v0.0.3-x64
3. Vérifier l'origine et analyser le ZIP avec Microsoft Defender.
4. Depuis PowerShell Windows, à la racine du clone de cette branche :

    powershell -NoProfile -File .\tools\dlss_only\install_dlss_only.ps1 -GameDir "D:\SteamLibrary\steamapps\common\Call of Duty Modern Warfare 3" -ReleaseZip "$env:USERPROFILE\Downloads\MW32011NCP-v0.0.3-x64.zip" -DryRun

5. Si les chemins sont exacts, retirer -DryRun et ajouter
   -FourKCheckOnly pour installer en **Vulkan sans DLSS**. Le test vérifie
   d'abord si le menu propose à nouveau 3840×2160 ; conserver la
   résolution et quitter le jeu.
6. Ensuite relancer le même script **sans -FourKCheckOnly** :
   StreamlineEnabled passe à 1 et DLSS Qualité est demandé. Le script
   sauvegarde les fichiers préexistants et n'écrit jamais dans iw5sp.exe,
   dans le registre ni dans config.cfg.
7. Relancer la campagne et mesurer réellement le résultat 4K + DLSS.
   Ne pas utiliser vid_restart ; quitter et relancer entièrement.

Paramètres : GraphicsApi=Vulkan, StreamlineEnabled=1,
InternalRenderScalePercent=67, DLSSModeX64=3,
TextureRenderRes=1x, DlssNeuralRenderingEnabled=0,
et d3d9.modeCountCompatibility=True dans dxvk.conf.

Le patch officiel v0.0.3-x64 n'inclut PAS le nouveau diagnostic C++
ajouté à cette branche. Le fichier dxvk.conf est chargé par DXVK
lorsque le répertoire de travail du jeu est le bon ; en revanche la
version compilée de la branche transmet l'option par variable
d'environnement avant le chargement DXVK, sans dépendre du dossier
de travail. Les deux solutions n'ont pas encore été validées sur
la machine de l'utilisateur.

## Sélecteur DLSS intégré au menu du jeu

La branche ajoute une **vraie ligne DLSS Super Resolution** dans le
menu personnalisé existant du jeu : **Options > Advanced Video**,
campagne x64 uniquement. Le menu existe déjà dans le mod ; pour y
accéder, la configuration active [Options] UseCustomOptionsScreen=1
(installateur sans -FourKCheckOnly).

Modes accessibles avec gauche/droite ou souris :

| Dans le menu | sl::DLSSMode | Échelle interne (%) | Sortie écran |
|---|---:|---:|---|
| Off | 0, Streamline arrêté | 100 | native |
| Quality | 3 | 67 | résolution du jeu (4K) |
| Balanced | 2 | 58 | résolution du jeu (4K) |
| Performance | 1 | 50 | résolution du jeu (4K) |
| Ultra Performance | 4 | 33 | résolution du jeu (4K) |
| DLAA | 6 | 100 | native, anti-aliasing |

Tous les changements sont sauvegardés dans mw3ncp_config.ini,
et affichent « (restart) » sur la ligne. **Quitter MW3 puis le
relancer complètement** : ni un vid_restart ni un simple changement
de carte ne rechargent l'interposeur Streamline et les render targets.
Le choix du mode n'altère pas le paramètre r_mode de MW3 et ne modifie
jamais le mode du bureau Windows.

**La DLL v0.0.3-x64 publique n'a PAS cette nouvelle ligne.**
Pour tester le menu, compiler la DLL depuis cette branche en
conservant les dépendances DXVK/Streamline compatibles et installer
la DLL compilée à la place du proxy officiel. Le script peut appliquer
les paramètres avec l'ancien proxy mais **ne peut pas ajouter une
ligne de menu à un binaire non recompilé**. Le site Actions signale
les tests de compilation/syntaxe ; leur succès n'est pas une
validation du fonctionnement du menu sur une vraie carte RTX.

**DLSS 5 Neural Rendering ne figure pas dans ce menu** : aucune
évaluation DLSS NR n'est intégrée et le SDK privé correspondant
n'est pas distribué.

## Remplacer les runtimes NVIDIA par une version plus recente (sans recompiler)

Le fichier `tools/dlss_only/update_streamline_runtime.ps1` met a jour les
quatre ressources NVIDIA contenues dans le **d3d9.dll DEJA INSTALLE**
(IDs 111, 112, 113, 114). Il n'efface pas la ressource DXVK (ID 110),
ne modifie ni le mode video natif de MW3 ni les fichiers de campagne.
Le mod extrait de nouveau ces quatre DLL a chaque lancement ; une copie
manuelle dans AppData serait donc immediatement ecrasee.

Conditions : jeu ferme ; dossier contenant les quatre DLL signees NVIDIA
`sl.interposer.dll`, `sl.common.dll`, `sl.dlss.dll`, `nvngx_dlss.dll`
(versions du meme SDK Streamline pour les trois fichiers sl.*).
Ne PAS integrer `nvngx_dlssnr.dll` ni `sl.dlss_nr.dll` : DLSS 5 NR
n'a pas de chemin d'evaluation dans MW3.

Depuis PowerShell, commencer par un test sans ecriture :

    .\tools\dlss_only\update_streamline_runtime.ps1 -GameDir 'C:\Program Files (x86)\Steam\steamapps\common\Call of Duty Modern Warfare 3' -StreamlineRuntimeDir 'C:\Users\Grg\Desktop\mw3\streamline-runtime new' -DryRun

Le test controle les signatures Authenticode NVIDIA et les architectures PE
x64, liste les versions et verifie la presence des 4 ressources dans le
proxy. Si tout est conforme, relancer sans `-DryRun` (jeu ferme) :

    .\tools\dlss_only\update_streamline_runtime.ps1 -GameDir 'C:\Program Files (x86)\Steam\steamapps\common\Call of Duty Modern Warfare 3' -StreamlineRuntimeDir 'C:\Users\Grg\Desktop\mw3\streamline-runtime new'

Le script cree `d3d9.dll.before-streamline-*.bak`, recompresse les
quatre ressources RCDATA avec leur langue d'origine, verifie leurs
empreintes SHA-256, puis remplace le proxy. En cas d'echec, restauration
automatique au mieux. Pour revenir en arriere en cas d'echec dans le jeu,
fermer MW3 et restaurer manuellement la sauvegarde vers `d3d9.dll`.

**Important** : cette operation ne peut pas injecter la nouvelle interface
du menu DLSS dans le binaire officiel v0.0.3-x64. Le menu requiert
une DLL du fork recompilee et assemblee avec les ressources NVIDIA
(voir `install_menu_from_ci.ps1`).
## Si 4K est encore absente

- Windows doit être réellement en 3840×2160.
- fourKMatches=0 dans un futur build de branche : DXVK ne fournit pas
  la résolution ; examiner l'énumération Windows/format affichage.
- fourKMatches>0 mais MW3 ne l'affiche pas : examiner le traitement
  des modes r_mode dans le moteur IW5.
- Si l'écran affiche 640×480 : conserver le journal
  [d3d9-hook] [res-diag] et revenir à la version sans mod.
- La DLL peut nécessiter un runtime Streamline/NVIDIA absent d'un
  build sans composants propriétaires. Ne pas copier des DLL
  provenant de mods Nexus ou modifier la signature des pilotes.

## Annuler

Jeu fermé : restaurer les fichiers *.before-dlss-*.bak créés
par le script en leur redonnant leur nom d'origine.
Si aucun d3d9.dll n'existait auparavant, retirer le fichier
installé pour retrouver le jeu vanilla. Ne pas toucher aux
sauvegardes de campagne.

## Tests automatisés et limites

- tools/dlss_only/test_install.ps1 teste le mode simulation,
  l'archive x64, les sauvegardes et la préservation des paramètres.
- .github/workflows/dlss-only-4k.yml vérifie le PowerShell et
  la syntaxe C++ sur Windows.
- Aucune CI distante ne peut démontrer que 4K et DLSS fonctionnent
  sur l'écran 4K/RTX 5060 Ti de l'utilisateur.
- DLSS 5 Neural Rendering est une fonctionnalité distincte,
  non implémentée ; copier ses DLL ne l'active pas.
