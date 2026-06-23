# wine-droid

wine-droid は、Android 上の Termux + proot-distro Ubuntu 環境で Windows ゲームを動かすためのスクリプト集です。Wine、box64/box86、Termux X11、PulseAudio、Mesa Turnip を組み合わせて、Android 端末上に Windows ゲーム実行環境を作ります。

これは Android アプリではありません。Termux 上で構築・起動する、実験的な Windows ゲーム実行環境です。

## なぜ作ったか

Box64Droid は、Android 上で Wine、x86 変換、グラフィック変換、Termux X11 連携をまとめて扱える便利な環境でした。一方で、Box64Droid は現在活発には開発されておらず、Box64Droid の rootfs や `box64droid --start` に依存したままだと、Wine、box64/box86、Mesa Turnip、起動時の環境変数をゲームや端末に合わせて更新しにくくなります。

wine-droid は、そのワークフローをなるべく見通しのよい形で再構成するために作りました。Box64Droid の rootfs を使うのではなく、Termux と Ubuntu rootfs の上で必要な部品をセットアップし、このリポジトリのスクリプトで起動します。

## 何をするものか

Termux 側では、Android と接続するための部品を用意します。

- Termux X11: Windows アプリの画面を表示するために使います。
- PulseAudio: 音声を出すために使います。
- proot-distro: Android 上で Ubuntu ユーザーランドを動かします。
- アプリ/ゲーム置き場: Termux 側の `~/apps` を Ubuntu 側の `/apps` として見せます。

Ubuntu 側では、Windows ゲームを動かすための部品を用意します。

- Wine: Windows API を Linux 上で実装する互換レイヤーです。
- box64/box86: ARM Android 端末上で x86-64/x86 Linux バイナリを動かすための変換レイヤーです。
- Mesa Turnip: Adreno GPU 向けの Vulkan ドライバーです。
- winetricks: ゲームが必要とする Windows ランタイムを導入するために使います。

Wine は CPU エミュレーターではありません。そのため、ARM の Android 端末で x86 向け Windows ゲームを動かすには、Wine だけでなく box64/box86 のような x86 変換レイヤーも必要になります。

## 現在の状態

このリポジトリは、汎用のワンクリックインストーラーではありません。端末差やゲーム差を見ながら調整するための、スクリプト化された作業環境です。

現時点では、ビジュアルノベル系ゲームを主な確認対象にしています。GINKA では、タイトル画面への到達と動画再生まで確認しています。

Wine、Mesa、Android の GPU ドライバー、ゲーム側の実装によって結果は変わります。動かない場合はログを取り、バージョンや設定を調整する前提です。

## 前提

- Android 端末に Termux が入っていること。
- Termux X11 が入っていること。
- 端末上でビルドするための十分なストレージと時間があること。
- 主な対象は Adreno GPU 搭載端末です。GPU 加速には Turnip を使います。
- Termux でシェルコマンドを実行できること。

proot-distro の rootfs 名は既定で `wine-droid` です。既存の `ubuntu` rootfs を使っているユーザー環境を壊さないよう、このプロジェクト専用の rootfs として作ります。

Ubuntu rootfs は `proot-distro install ubuntu` で入る、その時点の proot-distro 側の Ubuntu image を使います。特定の Ubuntu version には固定していません。Ubuntu 側の細かい version 固定をこのリポジトリで管理し続けるより、Termux/proot-distro の現行 image に追従する方針です。

ゲーム置き場の既定は Termux 側の `~/apps` です。例えば:

```sh
~/apps/GINKA/Game.exe
```

に置いたゲームは、Ubuntu 側では次のように見えます。

```sh
/apps/GINKA/Game.exe
```

## クイックスタート

Termux 側で、このリポジトリに移動してセットアップします。

```sh
cd ~/wine-droid
./setup-termux.sh
```

既に `wine-droid` rootfs がある場合は、作り直すか確認します。通常の Termux 更新は `pkg update` と必要パッケージの導入だけを行い、`pkg upgrade` は実行しません。

`wine-droid` rootfs の Ubuntu version は、実行時点の proot-distro の `ubuntu` image に従います。

Termux X11 と PulseAudio を起動し、Ubuntu shell に入ります。

```sh
./start-wine-droid.sh --shell
```

以降は Ubuntu shell 内で実行します。

```sh
cd /wine-droid
./setup-ubuntu.sh
```

専用 rootfs 内で閉じるため、Ubuntu 側のセットアップと Wine prefix 作成は root のまま実行します。

Wine prefix と基本ランタイムを作ります。既定は 64-bit/WOW64 prefix です。

```sh
cd /wine-droid
./setup-winetricks.sh
```

Termux 側からゲームを起動します。

```sh
cd ~/wine-droid
./start-wine-droid.sh run-game.sh /apps/GINKA/Game.exe
```

Ubuntu shell に入った状態なら、次のようにも起動できます。

```sh
cd /wine-droid
./run-game.sh /apps/GINKA/Game.exe
```

詳しい導入、起動、診断手順は [docs/usage.md](docs/usage.md) を読んでください。

以前の技術メモ寄り README は [docs/README-technical.md](docs/README-technical.md) に退避しています。

## よく使うコマンド

起動時と同じ X11、PulseAudio、Wine、Turnip 環境で Ubuntu shell に入る:

```sh
./start-wine-droid.sh --shell
```

グラフィック周りを診断する:

```sh
./start-wine-droid.sh ./diagnose-graphics.sh
```

ログを出しながらゲームを起動する:

```sh
./start-wine-droid.sh run-game.sh --debug /apps/GINKA/Game.exe
```

debug ログは既定で `/apps/wine-droid.log` に出ます。

一部のゲームは、Wine の `start /wait /unix` 経路だけではウィンドウ生成やフォーカスが崩れることがあります。その場合は Wine explorer の仮想デスクトップで包む `desktop` mode を使います。

```sh
./start-wine-droid.sh run-game.sh --desktop /apps/GINKA/Game.exe
```

GINKA など一部のタイトルでは、端末や Wine の組み合わせによって通常のウィンドウ表示が壊れるため、この切り替えが必要になる場合があります。

## 主な設定

通常は既定値のままで始められます。

- `WINE_DROID_APPS_DIR`: Termux 側で `/apps` に bind する場所。既定は `~/apps`。
- `WINE_DROID_DISTRO`: proot-distro の rootfs 名。既定は `wine-droid`。
- `WINE_DROID_WINE_VERSION`: `setup-wine.sh` で導入する Wine version。既定は `9.0`。
- `WINE_DROID_MESA_TAG`: `setup-turnip.sh` でビルドする Mesa tag。
- `WINE_DROID_LAUNCH_MODE`: `start` または `desktop`。既定は `start`。`run-game.sh --desktop` でも切り替えられます。
- `WINE_DROID_RESOLUTION`: Wine virtual desktop の解像度。既定は `1920x1080`。
- `WINE_DROID_CPUSET`: `taskset` に渡す CPU 指定。既定は `4-7`。
- `WINE_DROID_LOG_FILE`: debug ログ出力先。既定は `/apps/wine-droid.log`。
- `WINEPREFIX`: 使う Wine prefix。未指定時は rootfs 内の `$HOME/.wine`。
- `WINEARCH`: prefix 作成時の architecture。既定は `win64`。

## 補足: 関連技術の役割

Wine は Windows API を Linux 上で動かすための互換レイヤーです。Windows プログラムの「Windows への呼び出し」を Linux 側の仕組みに変換します。

box64/box86 は、x86-64/x86 向け Linux バイナリを ARM 上で動かすための変換レイヤーです。Android 端末の多くは ARM CPU なので、Wine の x86/x86-64 バイナリを動かすために必要になります。

Turnip は Mesa の Adreno 向け Vulkan ドライバーです。Zink は OpenGL を Vulkan に変換する Mesa の仕組みです。Android は通常のデスクトップ Linux とグラフィック環境が違うため、これらの組み合わせが必要になります。

proot-distro は、root 化なしで Termux 上に Ubuntu のような Linux ユーザーランドを作るために使います。ただし本物の Linux インストールとは違うため、一部のプログラムやドライバーは期待通りに動かないことがあります。

## 制限

- ワンクリックの互換レイヤーではありません。
- ゲームごとに動作可否が変わります。
- 主な確認対象は Android + Termux + proot Ubuntu + Adreno/Turnip です。
- 非 Adreno GPU は主対象ではありません。
- Wine のバージョンはゲームごとに変える必要がある場合があります。
- 端末上でのビルドには時間がかかります。

## ドキュメント

- [docs/usage.md](docs/usage.md): 導入、起動、診断の実用手順。
- [docs/turnip-investigation.md](docs/turnip-investigation.md): Turnip とグラフィック周りの調査メモ。
- [docs/README-technical.md](docs/README-technical.md): 以前の README。

## License

GPL-3.0 license です。詳細は [LICENSE](LICENSE) を参照してください。
