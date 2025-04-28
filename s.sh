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

# 加载动画
loading() {
    local pids=("$@")
    local delay=0.1
    local spinstr='|/-\'
    tput civis # 隐藏光标

    while :; do
        local all_done=true
        for pid in "${pids[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                all_done=false
                local temp=${spinstr#?}
                printf "\r\033[0;31;36m[ %c ] 正在安装 ...\033[0m" "$spinstr"
                local spinstr=$temp${spinstr%"$temp"}
                sleep $delay
            fi
        done
        [[ $all_done == true ]] && break
    done

    tput cnorm        # 恢复光标
    printf "\r\033[K" # 清除行
}

# 检查文件是否存在
filecheck() {
    if [[ -f "$installdir/$1" && -s "$installdir/$1" ]]; then
        return
    fi

    # 下载链接列表#兼容国内环境

    #"https://github.com/"
    #"https://gh.ddlc.top/"
    #"https://git.886.be/"

    local proxylinks="https://github.com/"

    # 设置超时时间（秒）
    local timeout=5

    wget -q --timeout="$timeout" "${proxylink}http://raw.githubusercontent.com/sshpc/s/main/$1" -O "$installdir/$1" >/dev/null 2>&1 &

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

#加载文件

shfiles=(
    'core/common.sh'
    'core/menu.sh'
    'module/status.sh'
    'module/software.sh'
    'module/network.sh'
    'module/system.sh'
    'module/docker.sh'
    'module/ordertools.sh'
)
pids=()
for shfile in "${shfiles[@]}"; do
    filecheck $shfile
    pids+=($!) # 收集子进程 PID
done
loading "${pids[@]}" # 显示加载动画
wait                 # 等待所有子进程完成

for shfile in "${shfiles[@]}"; do
    source "$installdir/$shfile"
done

#主函数
main() {

    menuname='首页'
    #echo "main" >$installdir/config/lastfun
    options=("状态" statusfun "软件管理" softwarefun "网络管理" networkfun "system系统管理" systemfun "docker" dockerfun "其他工具" ordertoolsfun "升级脚本" updateself "卸载脚本" removeself)
    menu "${options[@]}"
}

#判断配置文件是否存在或是否是真实函数

if [ -z "$(cat $installdir/config/lastfun)" ]; then
    main
else
    $(cat $installdir/config/lastfun)
fi
