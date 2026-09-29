# Consommer dawn-packer depuis Kotlin

`dawn-packer` publie des bibliothèques natives [Dawn](https://dawn.googlesource.com/dawn)
(WebGPU) précompilées, une archive par cible Kotlin/Native et par liaison
(`static` ou `shared`). Cette page décrit le téléchargement, la vérification, la
déclaration du cinterop et les dépendances système à lier côté consommateur.

Le pin Dawn de référence est `chromium/8077` (voir `dawn-pin.env`) ; le slug
utilisé dans les noms de fichiers remplace `/` par `-`, soit `chromium-8077`.

## 1. Télécharger et vérifier une archive

Les archives sont attachées aux GitHub Releases. Motif d'URL :

```
https://github.com/Graphiks-org/dawn-packer/releases/download/<release>/dawn-<dawnTagSlug>-<kotlinTarget>-<linkage>.tar.gz
```

Exemples concrets pour la release `v0.1.0` :

```
https://github.com/Graphiks-org/dawn-packer/releases/download/v0.1.0/dawn-chromium-8077-linuxX64-static.tar.gz
https://github.com/Graphiks-org/dawn-packer/releases/download/v0.1.0/dawn-chromium-8077-macosArm64-shared.tar.gz
```

Chaque release contient aussi :

- `SHA256SUMS` — une ligne `<sha256>  <fichier>` par archive ;
- `index.json` — agrégat des `manifest.json` de toutes les archives.

Vérifier l'archive téléchargée (`SHA256SUMS` liste toutes les archives, d'où le
filtrage sur le fichier voulu) :

```bash
# macOS
grep 'dawn-chromium-8077-linuxX64-static.tar.gz' SHA256SUMS | shasum -a 256 -c -

# Linux
grep 'dawn-chromium-8077-macosArm64-static.tar.gz' SHA256SUMS | sha256sum -c -
```

Puis extraire dans un répertoire local, par exemple
`third_party/dawn/<kotlinTarget>/<linkage>` :

```bash
mkdir -p third_party/dawn/linuxX64/static
tar xzf dawn-chromium-8077-linuxX64-static.tar.gz -C third_party/dawn/linuxX64/static
```

### Contenu d'une archive

```text
include/webgpu/webgpu.h                    # shim : #include "dawn/webgpu.h"
include/webgpu/webgpu_cpp.h                # shim C++ (non utilisé en cinterop C)
include/dawn/webgpu.h                      # API C WebGPU (le vrai en-tête)
include/dawn/...                           # en-têtes Dawn supplémentaires
lib/libwebgpu_dawn.a                       # variante static
lib/libwebgpu_dawn.so | .dylib             # variante shared (à la place du .a)
manifest.json
```

`manifest.json` décrit précisément l'archive : tag et **révision** Dawn
(`dawn.tag`, `dawn.revision`), cible (`target.kotlinTarget`, `triple`, `os`,
`arch`), `linkage`, `backends` et le `sha256`/`size` de chaque fichier. C'est la
source de vérité pour vérifier ce qui a réellement été construit.

## 2. Déclarer le cinterop

`src/nativeInterop/cinterop/webgpu.def`, variante **static** (exemple Apple) :

```def
headers = dawn/webgpu.h
headerFilter = dawn/webgpu.h
compilerOpts = -Ithird_party/dawn/macosArm64/static/include
staticLibraries = libwebgpu_dawn.a
libraryPaths = third_party/dawn/macosArm64/static/lib
```

Points d'attention :

- **L'API C vit dans `dawn/webgpu.h`**, pas dans `webgpu/webgpu.h` : ce dernier
  n'est qu'un shim qui fait `#include "dawn/webgpu.h"`. `headers` et
  `headerFilter` doivent donc viser `dawn/webgpu.h`. Si vous préférez pointer
  `headers = webgpu/webgpu.h`, le filtre doit malgré tout autoriser le vrai
  en-tête (`headerFilter = webgpu/** dawn/**` ou simplement `dawn/webgpu.h`),
  sinon cinterop exclut toutes les déclarations et le klib est vide.
- Un fichier `.def` par plateforme : les `staticLibraries` et `libraryPaths`
  diffèrent selon la cible et la liaison.

Variante **shared** (le `.a` n'existe pas, on lie la bibliothèque dynamique) :

```def
headers = dawn/webgpu.h
headerFilter = dawn/webgpu.h
compilerOpts = -Ithird_party/dawn/macosArm64/shared/include
linkerOpts = -Lthird_party/dawn/macosArm64/shared/lib -lwebgpu_dawn
```

## 3. Brancher la cible Gradle

```kotlin
kotlin {
    macosArm64 {
        compilations.getByName("main").cinterops.create("webgpu") {
            defFile(project.file("src/nativeInterop/cinterop/webgpu.def"))
        }

        // Variante static Apple : le consommateur doit lier les frameworks.
        binaries.all {
            linkerOpts(
                "-framework", "Metal",
                "-framework", "Foundation",
                "-framework", "CoreGraphics",
                "-framework", "QuartzCore",
                "-framework", "IOKit",
                "-framework", "IOSurface",
            )
        }
    }
}
```

Sur Linux, même structure avec `linuxX64 { ... }` et les options de lien de la
section suivante. La même déclaration cinterop s'applique à `iosArm64`,
`iosSimulatorArm64`, `iosX64`, `tvosArm64` et `tvosSimulatorArm64` (frameworks et
toolchain identiques à la variante Apple ci-dessus).

## 4. Dépendances système à lier (variante static)

La bibliothèque monolithique Dawn **n'embarque pas** les dépendances système :
le consommateur les fournit au lien final. Ces listes sont exactement celles
utilisées par `scripts/run-smoke-test.sh`, qui lie chaque archive réelle :

- **Apple** (macOS / iOS / tvOS) :

  ```
  -framework Metal -framework Foundation -framework CoreGraphics \
  -framework QuartzCore -framework IOKit -framework IOSurface
  ```

  `IOKit` et `IOSurface` sont réellement requis au lien (Dawn compile
  `IOSurfaceUtils.cpp` pour toutes les plateformes Apple), même si un programme
  minimal n'appelle que l'API `wgpu*`.

- **Linux** : `-lpthread -ldl -lm`. Ajouter au besoin les bibliothèques
  X11/Wayland si votre application en dépend.

- **Android** : les `.so` système (`liblog`, `libandroid`, `libatomic`) sont
  fournis par le runtime Kotlin/Native. Voir la contrainte NDK en §6.

La bibliothèque Dawn est écrite en C++ même si son API est en C. Le lien final
est donc un lien C++ : `scripts/run-smoke-test.sh` utilise un pilote C++
(`c++`) et n'ajoute **pas** `-lc++` lui-même. En cinterop Kotlin/Native, la
toolchain C++ de la cible est fournie par Kotlin/Native.

## 5. Variante shared : déployer la bibliothèque avec l'application

L'archive `-shared` contient `lib/libwebgpu_dawn.so` (Linux/Android) ou
`lib/libwebgpu_dawn.dylib` (Apple) ; elle doit être livrée **à côté** de
l'application, pas seulement liée au build :

- **Android** : placer le `.so` de la bonne ABI dans
  `src/androidMain/jniLibs/<abi>/libwebgpu_dawn.so` (ABIs : `arm64-v8a`,
  `armeabi-v7a`, `x86_64`, `x86`).
- **Apple** : embarquer et signer le `.dylib` (par exemple dans
  `Contents/Frameworks/`), et référencer son chemin via `@rpath`/`@loader_path`.
  La bibliothèque partagée porte déjà ses dépendances Apple dans ses *load
  commands* (`otool -L` liste Metal, Foundation, CoreGraphics, QuartzCore,
  IOKit, IOSurface) ; le consommateur n'a donc pas à les relier à nouveau.
- **Linux/desktop** : installer le `.so` avec l'application et le rendre
  trouvable (`RPATH`, `LD_LIBRARY_PATH`, ou à côté de l'exécutable).

`scripts/run-smoke-test.sh` illustre le lien dynamique :
`-L<lib> -lwebgpu_dawn -Wl,-rpath,<lib>`.

## 6. Contraintes et cibles non disponibles

- **Android** : les archives `androidNative*` sont construites avec le NDK
  **27.3.13750724** (API 26, STL `c++_static`). La consumabilité Kotlin/Native
  n'est **pas** établie : Kotlin/Native 2.4.20 lie sa propre libc++ statique
  d'ère r19c, qui ne définit pas tous les symboles `std::__ndk1` référencés par
  les objets compilés avec NDK 27. Le risque est décrit en détail dans
  `docs/spikes/android.md` (« Open risk: consumer C++ runtime ») et n'est levé
  ni par l'une ni par l'autre des remédiations candidates tant qu'un lien
  cinterop KMP **et** une exécution sur appareil n'ont pas réussi. Ne pas
  considérer ces cibles comme prouvées consommables.
- **watchOS** (`watchosArm64`, `watchosDeviceArm64`, `watchosSimulatorArm64`) :
  pas d'archive. Les SDK watchOS ne fournissent ni `Metal.framework` ni
  `IOSurface.framework`, et `arm64_32` (ILP32) échoue l'assertion
  `sizeof(size_t) == 8` de Dawn.
- **`mingwX64`** : pas d'archive. Le backend D3D12 exige des bibliothèques du
  Windows SDK et une étape de copie de DLL que MinGW-w64 n'a pas.
- Les en-têtes / le manifeste sont communs aux deux liaisons ; seule la
  bibliothèque change. Vérifier la révision Dawn réellement construite dans
  `manifest.json` avant de déboguer un comportement inattendu.

Voir aussi :

- `README.md` — état des cibles et build local ;
- `docs/superpowers/specs/2026-09-28-dawn-packer-design.md` — contrat de livraison ;
- `docs/spikes/` — verdicts par plateforme.
