# dawn-packer

Bibliothèques natives [Dawn](https://dawn.googlesource.com/dawn) (WebGPU) précompilées,
publiées en GitHub Releases pour les cibles Kotlin/Native non-web.

Ce dépôt ne produit que les bibliothèques (en-têtes `webgpu.h` + `libwebgpu_dawn`) ;
tout binding Kotlin/Native, JNI, Swift, etc. vit dans le projet consommateur.

Le pin Dawn (`chromium/8077`) est déclaré dans `dawn-pin.env` (`DAWN_TAG`), résolu
en un commit figé par le sous-module `dawn/` et enregistré dans
`build/dawn-revision.txt`.

## État des cibles

`targets/matrix.json` est la source de vérité (triple, runner, toolchain,
backends, statut). Les cibles avec `status != "dropped"` sont construites par la
CI et publiées ; les autres sont abandonnées après spike.

Cibles qui produisent une archive (les deux liaisons en CI) :

| Cible | Backends | Validation locale |
|---|---|---|
| `macosArm64` | metal, null | archives static + shared dans `dist/` (smoke test exécuté) |
| `iosArm64` | metal, null | archive static dans `dist/` (device : contrôle structurel) |
| `iosSimulatorArm64` | metal, null | archive static dans `dist/` (cross) |
| `iosX64` | metal, null | archive static dans `dist/` (cross) |
| `tvosArm64` | metal, null | archive static dans `dist/` (cross) |
| `tvosSimulatorArm64` | metal, null | archive static dans `dist/` (cross) |
| `linuxX64` | vulkan, gles, null | construit en CI (runner `ubuntu-24.04`) |
| `linuxArm64` | vulkan, gles, null | construit en CI (runner `ubuntu-24.04-arm`) |
| `androidNativeArm64` | vulkan, gles, null | archive static dans `dist/` ; NDK épinglé ; risque consommateur non levé |
| `androidNativeArm32` | vulkan, gles, null | archive static dans `dist/` ; NDK épinglé ; risque consommateur non levé |
| `androidNativeX64` | vulkan, gles, null | archive static dans `dist/` ; NDK épinglé ; risque consommateur non levé |
| `androidNativeX86` | vulkan, gles, null | archive static dans `dist/` ; NDK épinglé ; risque consommateur non levé |

Cibles abandonnées (`dropped`, aucune archive) :

| Cible | Raison |
|---|---|
| `watchosArm64` | SDK watchOS sans `Metal.framework`/`IOSurface.framework` ; `arm64_32` (ILP32) échoue l'assertion `sizeof(size_t) == 8` de Dawn |
| `watchosDeviceArm64` | SDK watchOS sans `Metal.framework` ni `IOSurface.framework` (configure `find_library(Metal) REQUIRED` échoue) |
| `watchosSimulatorArm64` | idem : SDK watchOS sans Metal/IOSurface |
| `mingwX64` | D3D12 dépend de bibliothèques du Windows SDK et d'une copie de DLL que MinGW-w64 ne fournit pas |

Voir `docs/spikes/android.md`, `docs/spikes/apple-watchos-tvos.md` et
`docs/spikes/mingw-x64.md` pour les verdicts détaillés.

## Build local

```bash
bash scripts/sync.sh                       # sous-module Dawn + patches + build/dawn-revision.txt
bash scripts/build-target.sh linuxX64 static
bash scripts/package.sh linuxX64 static    # -> dist/linuxX64/dawn-chromium-8077-linuxX64-static.tar.gz
```

Les cibles cross (iOS, tvOS, Android) ont besoin d'un `protoc` hôte, construit
automatiquement par `scripts/build-target.sh` via `scripts/build-host-protoc.sh`.
Les cibles Android exigent en plus `ANDROID_NDK_HOME` pointant sur le NDK
**27.3.13750724**.

## Tests

```bash
for t in tests/test-*.sh; do bash "$t"; done
```

Un agrégateur `scripts/run-tests.sh` exécute toute la suite. Les tests qui
lancent un vrai build Dawn sont volontairement exclus de la CI rapide (voir
`.github/workflows/build.yml`).

## Consommation depuis Kotlin

Voir `docs/consumption.md` : motif d'URL des archives, vérification
`SHA256SUMS`, fichier `.def` cinterop, extrait Gradle et dépendances système à
lier par plateforme.

## Écarts connus

Les actions GitHub sont référencées en `@v4`. L'épinglage par SHA prévu par la
spec est un durcissement post-v1.

La consumabilité des cibles `androidNative*` n'est pas prouvée : le risque
libc++ Kotlin/Native/NDK 27 est documenté dans `docs/spikes/android.md`.
