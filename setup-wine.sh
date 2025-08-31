#!/bin/bash

function setup_wine() (
    echo "Installing Wine $1..."
    cd /opt
    wget https://github.com/Kron4ek/Wine-Builds/releases/download/$1/wine-$1-x86.tar.xz -q
    tar -xf wine-$1-x86.tar.xz
    rm wine-$1-x86.tar.xz
    mv wine-$1-x86 wine$1
    cd /opt/wine$1/bin/
    mv wineserver wineserver.real
    curl -fsSL https://raw.githubusercontent.com/stakeval0/wine-droid/refs/heads/main/wineserver.c | gcc -x c - -o wineserver
)

setup_wine 9.0
setup_wine 10.0
