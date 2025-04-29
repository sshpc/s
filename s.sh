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

    # 隐藏光标
    tput civis

    # 定义要打印的内容
    local texts=(
        "   ________       "
        "  |\   ____\      "
        "  \ \  \___|_     "
        "   \ \_____  \    "
        "    \|____|\  \   "
        "      ____\_\  \  "
        "     |\_________\ "
        "     \|_________| "
    )

    # 获取最长行的长度
    local max_length=0
    for line in "${texts[@]}"; do
        len=${#line}
        if ((len > max_length)); then
            max_length=$len
        fi
    done

    # 初始化输出数组
    local output=()
    for ((i = 0; i < ${#texts[@]}; i++)); do
        output[$i]=""
    done

    # 逐列打印
    for ((col = 0; col < max_length; col++)); do
        for ((i = 0; i < ${#texts[@]}; i++)); do
            line=${texts[$i]}
            char="${line:$col:1}"
            if [[ -n $char ]]; then
                output[$i]+=$char
            else
                output[$i]+=" "
            fi
        done
        # 清屏
        tput clear
        for line in "${output[@]}"; do
            _green "$line"
        done
        sleep 0.05
    done

    # 恢复光标
    tput cnorm
}

#逐字打印
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
                printf "\r\033[0;31;36m[ %c ] 安装组件 ...\033[0m" "$spinstr"
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
    local filename="$1"

    if [[ -f "$installdir/$filename" && -s "$installdir/$filename" ]]; then
        return 0
    fi

    (

        # 下载链接列表，按顺序依次尝试 默认github
        local proxylinks=(
            "http://raw.githubusercontent.com"
            "https://gh.ddlc.top/http://raw.githubusercontent.com"
            "https://git.886.be/http://raw.githubusercontent.com"
        )

        # 设置超时时间（秒）
        local timeout=4

        for proxylink in "${proxylinks[@]}"; do

            wget -q --timeout="$timeout" "${proxylink}/sshpc/s/main/$1" -O "$installdir/$1" >/dev/null 2>&1

            if [[ -f "$installdir/$filename" && -s "$installdir/$filename" ]]; then
                exit 0
            else
                rm -f "$installdir/$filename"
            fi
        done

        _red "文件 $filename 下载失败！"
        exit 1
    ) &
}

# 检查目录是否存在(全新安装)
if [ ! -d "$installdir" ]; then
    slogo
    echo
    jumpfun "welcome" 0.04
    echo

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
    options=("状态" statusfun "软件管理" softwarefun "网络管理" networkfun "system系统管理" systemfun "docker" dockerfun "其他工具" ordertoolsfun "升级脚本" updateself "卸载脚本" removeself)
    menu "${options[@]}"
}

#判断配置文件是否存在或是否是真实函数

if [ -z "$(cat $installdir/config/lastfun)" ]; then
    main
else
    $(cat $installdir/config/lastfun)
fi
