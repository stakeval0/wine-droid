#!/bin/bash
apt-get update && apt-get upgrade -y
ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
apt-get install -y\
    apt-utils curl wget\
    x11-apps locales fonts-migmix

bash -c "apt-get install -y \
    gstreamer1.0-{plugins-{bad,base,good,ugly},libav,pulseaudio}:armhf \
    pulseaudio ffmpeg \
    fonts-{takao,mona,monapo} \
    xvfb winbind \
    "


# install box64: https://github.com/ptitSeb/box64
git clone https://github.com/ptitSeb/box64
cd box64
cmake -S . -B build/ -D ARM_DYNAREC=ON -D CMAKE_BUILD_TYPE=RelWithDebInfo
cmake --build build/ -j 6
cd build && make install
cd /root
# rm -rf box64 # 不具合でスクリプトが途中で止まったりするので削除は手動

# install box86
dpkg --add-architecture armhf && apt-get update
apt-get install -y gcc-arm-linux-gnueabihf
git clone https://github.com/ptitSeb/box86
cd box86
cmake -S . -B build/ -D CMAKE_C_COMPILER=arm-linux-gnueabihf-gcc -D ARM_DYNAREC=ON -D CMAKE_BUILD_TYPE=RelWithDebInfo
cmake --build build/ -j 6
cd build && make install
cd /root
# rm -rf box86 # 不具合でスクリプトが途中で止まったりするので削除は手動


localedef -f UTF-8 -i ja_JP ja_JP.UTF-8
cat << EOF >> $HOME/.bashrc
export LANG="ja_JP.UTF-8"
export LANGUAGE="ja_JP:ja"
export LC_ALL="ja_JP.UTF-8"
export DXVK_HUD=0
export GALLIUM_HUD=""
EOF

rm -rf $HOME/.wine
export WINEARCH=win32
box64 winetricks --self-update

echo 'export PATH=$PATH:$HOME/bin' >> $HOME/.bashrc
mkdir -p $HOME/bin
cat << "EOF" > $HOME/bin/start-app
#!/bin/bash
if [ $# != 1 ] ; then
  echo "usage: $0 [windows binary]"
  exit 0
fi
taskset -c 4-7 box64 wine explorer /desktop=shell,1920x1080 $1
EOF
chmod 755 $HOME/bin/start-app
