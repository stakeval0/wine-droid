#!/bin/bash
USE_DXVK=true
export WINEARCH=win32

while [[ $# -gt 0 ]]; do
    case "$1" in
        --use-gl)
            USE_DXVK=false
            shift
            ;;
        *)
            shift
            ;;
    esac
done

if [ "$USE_DXVK" = false ]; then
    box64 winetricks -q cjkfonts fakejapanese_ipamona d3dx9 d3dx10 d3dx11_43
else
    box64 winetricks -q cjkfonts fakejapanese_ipamona # デフォルトでインストールされるdxvkを使う
fi
xvfb-run box64 winetricks -q wmp9
box64 winetricks settings sound=pulse
before=$(stat -c '%Y' ${HOME}/.wine/user.reg) &&\
    box64 wine reg add "HKCU\Software\Wine\X11 Driver" /v UseXRandR /t REG_SZ /d N /f && \
    box64 wine reg add "HKCU\Software\Wine\X11 Driver" /v UseXVidMode /t REG_SZ /d N /f && \
    while [ $(stat -c '%Y' ${HOME}/.wine/user.reg) = $before ]; do sleep 1; done
