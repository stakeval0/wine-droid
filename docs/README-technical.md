# wine-droid technical notes

この文書は、公開 README から外した実装寄りの補足です。通常の導入と起動は [usage.md](usage.md) を読んでください。

## rootfs

既定の proot-distro rootfs 名は `wine-droid` です。既存の `ubuntu` rootfs を使っているユーザー環境に触れないため、`setup-termux.sh` は次の形で専用 rootfs を作ります。

```sh
proot-distro install --override-alias wine-droid ubuntu
```

ここで使う Ubuntu は proot-distro の `ubuntu` image です。release は固定しません。固定すると Ubuntu release 更新のたびにこのリポジトリ側で管理判断が必要になるため、Termux/proot-distro 側の現行 image に追従する方針です。

既に `wine-droid` rootfs がある場合、対話実行では再インストールするか確認します。非対話実行では既存 rootfs を保持します。強制的に作り直す場合は `WINE_DROID_REINSTALL_DISTRO=1 ./setup-termux.sh` を使います。

## Wine

Wine は Kron4ek Wine Builds の amd64 build を `/opt/wine<version>` に展開します。既定 version は `9.0` です。`/opt/wine` は最後に導入した Wine への symlink です。

`/opt/wine/bin/wine64` は x86-64 launcher なので `box64` 経由で実行します。`/opt/wine/bin/wine` は i386 launcher なので、32-bit prefix 用に `/usr/local/bin/wine-box86` を用意します。

## Prefix

既定 prefix は `WINEARCH=win64` の WOW64 prefix です。64-bit prefix の方がメモリ管理に余裕があり、32-bit prefix では BGI 系などでアドレス空間不足由来の落ち方をしやすいためです。

32-bit prefix は必要な場合だけ使います。

```sh
./setup-winetricks.sh --arch32
```

`WINEPREFIX` 未指定時は rootfs 内の `$HOME/.wine` を使います。このプロジェクトは専用 rootfs 内で閉じるため、現状は root のまま運用します。

`setup-winetricks.sh` は非対話で完走することを前提にします。winetricks は `-q` と `xvfb-run` 経由で実行し、ユーザーが GUI ダイアログを承認する運用にはしません。

## Graphics

Mesa Turnip は公式 Mesa source から `kgsl,msm`, `zink`, `glx`, `gbm` を有効にして build します。目的は Android の `/dev/kgsl-3d0` を使う Turnip と、OpenGL to Vulkan/Zink 経路を同時に成立させることです。

通常の launch environment は Wine 側に合わせて armv7 ICD を既定にします。native aarch64 の GLX/Zink 確認は `diagnose-graphics.sh` の `Native GLX via Zink` を見ます。

## Launch

既定の起動方式は次の形です。

```sh
box64 /opt/wine/bin/wine64 start /wait /unix /apps/Game/Game.exe
```

`start` は Wine の Windows 側 launcher、`/unix` は Unix path の exe を渡す指定、`/wait` は起動した Windows process の終了を待つ指定です。

一部タイトルで通常ウィンドウ表示が壊れる場合は、Wine explorer の仮想デスクトップで包みます。

```sh
./run-game.sh --desktop /apps/Game/Game.exe
```
