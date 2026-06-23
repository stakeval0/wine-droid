# wine-droid 使い方

この文書は、Termux + proot Ubuntu 上で Wine/box64/box86/Turnip を使って Windows ゲームを起動するための運用手順です。

Box64Droid の rootfs は使いません。Termux X11、PulseAudio、proot の bind、Wine 起動時の環境変数だけをこのリポジトリのスクリプトで再構成します。

## 前提

- Android 側に Termux と Termux X11 が入っていること。
- コマンドは基本的に Termux で実行すること。
- ゲームは Termux 側の `~/apps` に置くこと。Ubuntu 内では同じ場所が `/apps` として見えます。
- 既定の proot-distro rootfs 名は `wine-droid` です。既存の `ubuntu` rootfs を使っているユーザー環境を壊さないよう、このプロジェクト専用の rootfs として作ります。
- Ubuntu version は固定していません。`proot-distro install ubuntu` で入る、その時点の proot-distro 側の Ubuntu image を使います。

`~/apps` はゲーム置き場です。例えば Termux 側の `~/apps/Frontwing/GINKA/GINKA.exe` は、Ubuntu 側では `/apps/Frontwing/GINKA/GINKA.exe` になります。

## 初回インストール

Termux 側で実行します。

```sh
cd ~/wine-droid
./setup-termux.sh
```

このスクリプトは Termux 側に `termux-x11-nightly`, `proot-distro`, `pulseaudio`, Mesa/Vulkan loader などを入れ、専用の Ubuntu rootfs `wine-droid` を作ります。ゲーム置き場は Termux のホームディレクトリ配下にある `~/apps` なので、Android 共有ストレージ権限は要求しません。

Ubuntu rootfs は proot-distro の `ubuntu` image をそのまま使います。このリポジトリでは Ubuntu release を固定せず、Termux/proot-distro 側の現行 image に追従します。

既に `wine-droid` rootfs がある場合は、作り直すか確認します。非対話実行では既存 rootfs を保持します。明示的に作り直す場合は次のようにします。

```sh
WINE_DROID_REINSTALL_DISTRO=1 ./setup-termux.sh
```

Termux のパッケージ操作は `pkg update` と必要パッケージの導入だけを行います。`pkg upgrade` は実行しません。

次に、Termux X11 と PulseAudio を起動した状態で Ubuntu shell に入ります。

```sh
./start-wine-droid.sh --shell
```

以降は Ubuntu 内で実行します。

```sh
cd /wine-droid
./setup-ubuntu.sh
```

専用 rootfs 内で閉じるため、Ubuntu 側のセットアップと Wine prefix 作成は root のまま実行します。

`setup-ubuntu.sh` は box64/box86、Wine、Turnip を構築します。Turnip は Mesa 公式ソースからビルドします。Box64Droid などの既存環境からバイナリをコピーする方針ではありません。

完了後、少なくとも Wine の symlink ができていることを確認します。

```sh
ls -l /opt/wine
ls -l /opt/wine/bin/wine64
box64 /opt/wine/bin/wine64 --version
```

ここで `/opt/wine/bin/wine64` が存在しない場合は、Wine 導入前に `setup-ubuntu.sh` が失敗しています。まず `cd /wine-droid && ./setup-wine.sh` を実行して Wine を入れ直してください。

Wine prefix を作ります。

```sh
cd /wine-droid
./setup-winetricks.sh
```

既定は 64-bit/WOW64 prefix です。64-bit prefix の方がメモリ管理に余裕があり、32-bit prefix では BGI 系などでアドレス空間不足由来の落ち方をしやすいためです。

ほとんどのゲームでは既定のまま使います。32-bit prefix は必要な場合だけ明示的に使います。

```sh
./setup-winetricks.sh --arch32
```

## 普段の起動

Termux 側で、Ubuntu 環境ごとゲームを起動できます。

```sh
cd ~/wine-droid
./start-wine-droid.sh run-game.sh /apps/Frontwing/GINKA/GINKA.exe
```

Ubuntu shell に入ってから起動する場合は次の形です。

```sh
cd /wine-droid
./run-game.sh /apps/Frontwing/GINKA/GINKA.exe
```

`run-game.sh` は exe のあるディレクトリに移動してから Wine を起動します。Kirikiri 系ゲームはカレントディレクトリ前提でリソースを探すことがあるためです。

既定の起動方式は `wine64 start /wait /unix <exe>` です。`start` は Wine の Windows 側 launcher で、`/unix` は Unix path の exe を渡す指定、`/wait` は起動した Windows process の終了を待つ指定です。この経路は素直に起動できるタイトルでは扱いやすい一方で、Wine explorer で包まないため、一部のゲームではウィンドウ生成、フォーカス、描画領域が壊れることがあります。

その場合は `--desktop` を指定し、Wine explorer の仮想デスクトップ経由に切り替えます。

```sh
./start-wine-droid.sh run-game.sh --desktop --resolution 1280x720 \
  /apps/Frontwing/GINKA/GINKA.exe
```

GINKA など一部のタイトルでは、端末や Wine の組み合わせによって通常のウィンドウ表示が壊れるため、この `desktop` mode が必要になる場合があります。

ログを取りたい場合は `--debug` を付けます。ログは既定で `/apps/wine-droid.log` に出ます。

```sh
./start-wine-droid.sh run-game.sh --debug /apps/Frontwing/GINKA/GINKA.exe
```

## GINKA の確認済み構成

確認環境では次の構成で GINKA のタイトル画面と動画再生を確認しています。

- Wine 9.0
- 64-bit/WOW64 prefix
- Mesa Turnip/Zink 自前ビルド
- `wmp9` 導入済み
- `quartz` は未導入

`quartz` は GINKA の動画が上下反転するため既定では入れません。

`wmp9` 導入時、win64 prefix では winetricks が `wm9codecs is not supported in win64 prefixes` と警告します。これは想定内です。GINKA では `wmp/wmvcore/l3codeca` の native override が入った状態で動画再生できています。

## Wine version を変える

Wine は固定ではありません。既定は 9.0 ですが、ゲームごとに変えられます。

Ubuntu 内で実行します。

```sh
cd /wine-droid
WINE_DROID_WINE_VERSION=10.0 ./setup-wine.sh
```

`/opt/wine` は最後に導入した Wine への symlink になります。

既存 prefix を別 Wine version で開くと Mono/Gecko prompt が出ることがあります。prefix を更新する場合は `setup-winetricks.sh` を通すと、`xvfb-run` と `WINEDLLOVERRIDES=mscoree,mshtml=` で非対話に寄せます。

GINKA は Wine 10 だと動画が動かないことがあるため、GINKA 用には Wine 9.0 を使うのが現在の確認済みルートです。

## Turnip を更新する

Turnip は Mesa tag を指定してビルドできます。

Ubuntu 内で実行します。

```sh
cd /wine-droid
WINE_DROID_MESA_TAG=mesa-26.1.3 ./setup-turnip.sh
```

インストール先は `/opt/wine-droid/mesa-turnip/<tag>` です。`current` symlink が最後に入れた tag を指します。

ビルド時は `kgsl,msm`, `zink`, `glx`, `gbm` を有効にします。目的は、Android の `/dev/kgsl-3d0` を使う Turnip と、Box64Droid と同じような OpenGL to Vulkan/Zink 経路を両方成立させることです。

## 診断

端末差分や描画不良を見る時は、まず同じ指標を取ります。

Termux 側で実行します。

```sh
cd ~/wine-droid
./start-wine-droid.sh ./diagnose-graphics.sh
```

見る場所は主に次の通りです。

- `X11`: `/tmp/.X11-unix` と X11 extension が見えているか。
- `GLX`: 通常の `glxinfo` がどこで失敗するか。
- `Native GLX via Zink`: aarch64 の Zink/Turnip 経路で `OpenGL renderer string: zink Vulkan ... Turnip` になるか。
- `Vulkan`: Turnip ICD が見えているか。
- `KGSL`: `/dev/kgsl-3d0` と `/sys/class/kgsl` が見えているか。
- `Wine Prefix`: DirectX ランタイムや動画関連 DLL override が prefix に入っているか。

通常起動環境は 32-bit Wine/Zink のため armv7 ICD を既定にします。そのため、通常の `glxinfo` だけを見ると失敗に見えることがあります。ネイティブ側の GLX/Zink 判定は `Native GLX via Zink` を見ます。

## よく使う確認コマンド

Ubuntu shell 内で実行します。

```sh
box64 --version
box86 --version
ls -l /opt/wine
box64 /opt/wine/bin/wine64 --version
wine-box86 --version
```

Turnip の native 側確認は次のようにします。

```sh
VK_ICD_FILENAMES=/opt/wine-droid/mesa-turnip/current/share/vulkan/icd.d/freedreno_icd.aarch64.json \
  vulkaninfo --summary
```

ただし `vulkaninfo` は Android/KGSL 経路で失敗することがあります。GINKA の実動と `diagnose-graphics.sh` の `Native GLX via Zink` も合わせて見ます。

## X11 や音声が変になった時

通常は `./start-wine-droid.sh` を再実行すれば、既存の Termux X11 と PulseAudio を使って Ubuntu 環境に入れます。

それでも X11 転送先や PulseAudio が古い状態を掴んでいる時だけ、Termux 側の X11/PulseAudio process を落としてから起動し直します。

```sh
killall /system/bin/app_process pulseaudio
cd ~/wine-droid
./start-wine-droid.sh --shell
```

これは強めの復旧手段です。Termux X11 アプリ側も、必要なら開き直します。

## 主な設定

普段は変更不要です。

- `WINE_DROID_APPS_DIR`: Termux 側で `/apps` に bind する場所。既定は `~/apps`。
- `WINE_DROID_DISTRO`: proot-distro rootfs 名。既定は `wine-droid`。
- `WINE_DROID_WINE_VERSION`: `setup-wine.sh` で導入する Wine version。既定は `9.0`。
- `WINE_DROID_MESA_TAG`: `setup-turnip.sh` でビルドする Mesa tag。
- `WINE_DROID_LAUNCH_MODE`: `start` または `desktop`。既定は `start`。`run-game.sh --desktop` でも切り替えられます。
- `WINE_DROID_RESOLUTION`: desktop mode の解像度。既定は `1920x1080`。
- `WINE_DROID_CPUSET`: `taskset` の CPU 指定。既定は `4-7`。
- `WINE_DROID_LOG_FILE`: debug ログ出力先。既定は `/apps/wine-droid.log`。
- `WINEPREFIX`: 使う Wine prefix。
- `WINEARCH`: prefix 作成時の architecture。既定は `win64`。32-bit prefix が必要な場合だけ `setup-winetricks.sh --arch32` を使います。

## 方針

- ゲーム置き場の既定は `~/apps` にします。
- Turnip は公式 Mesa ソースからビルドします。
- Wine version はゲームごとに変えられるようにします。
- 既定 prefix は 64-bit/WOW64 にします。
- GINKA では `quartz` を入れません。
- 頻繁な文書同期より、動いた構成と原因が分かった変更をまとめて反映します。
