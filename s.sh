#!/bin/bash
export LANG=en_US.UTF-8

#定义全局变量

#安装目录
installdir=$HOME/s
#日期时间
datevar=$(date +"%Y-%m-%d %H:%M:%S")
#默认主页
menuname='主页'

# 颜色定义
_red() {
    printf '\033[0;31;31m%b\033[0m' "$1"
    echo
}
_green() {
    printf '\033[0;31;32m%b\033[0m' "$1"
    echo
}
_yellow() {
    printf '\033[0;31;33m%b\033[0m' "$1"
    echo
}
_blue() {
    printf '\033[0;31;36m%b\033[0m' "$1"
    echo
}

#logo
slogo() {
    echo
    _green '   ________       '
    _green '  |\   ____\      '
    _green '  \ \  \___|_     '
    _green '   \ \_____  \    '
    _green '    \|____|\  \   '
    _green '      ____\_\  \  '
    _green '     |\_________\ '
    _green '     \|_________| '
    echo
}

#字符跳动 (参数：字符串 间隔时间s，默认为0.1秒)
jumpfun() {
    my_string=$1
    delay=${2:-0.1}
    # 循环输出每个字符
    for ((i = 0; i < ${#my_string}; i++)); do
        printf '\033[0;31;36m%b\033[0m' "${my_string:$i:1}"
        sleep "$delay"
    done
    echo
}

# 检查文件是否存在
filecheck() {
    if [ ! -f "$installdir/$1" ]; then
        wget -N http://raw.githubusercontent.com/sshpc/s/main/$1 -O "$installdir/$1"
    fi
    # 检查上一条命令的退出状态码
    if [ $? -eq 0 ]; then
        source "$installdir/$1"
    else
        echo "下载文件失败,请重试"
    fi
}

# 检查目录是否存在(全新安装)
if [ ! -d "$installdir" ]; then
    slogo
    jumpfun "welcome to use" 0.06

    mkdir -p "$installdir" "$installdir/core" "$installdir/log" "$installdir/config" "$installdir/module"

    wget -N http://raw.githubusercontent.com/sshpc/s/main/version -O "$installdir/version"

    cp -f "$(pwd)/s.sh" "$installdir/s.sh"
    ln -s "$installdir/s.sh" /bin/s

fi

#加载版本
selfversion=$(cat $installdir/version)

#加载内核
filecheck /core/common.sh
filecheck /core/menu.sh

#载入模块
filecheck /module/status.sh
filecheck /module/software.sh
filecheck /module/network.sh
filecheck /module/system.sh
filecheck /module/docker.sh
filecheck /module/ordertools.sh

#主函数
main() {

    menuname='首页'
    #echo "main" >$installdir/config/lastfun
    options=("状态" statusfun "soft软件管理" softwarefun "network网络管理" networkfun "system系统管理" systemfun "docker" dockerfun "其他工具" ordertoolsfun "升级脚本" updateself "卸载脚本" removeself)
    menu "${options[@]}"
}

#判断配置文件是否存在或是否是真实函数

if [ -z "$(cat $installdir/config/lastfun)" || ! _exists "$(cat $installdir/config/lastfun)" ]; then
    main
else
    $(cat $installdir/config/lastfun)
fi
