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

    _green '# Ubuntu初始化&工具脚本'
    _green '# Author:SSHPC <https://github.com/sshpc>'
    echo

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


# 进度条
loadingprogressbar() {
    local pids=("$@")
    local total=${#pids[@]}
    local completed=0
    local delay=0.02
    local spinstr='|/-\'
    local spinindex=0

    tput civis # 隐藏光标

    while :; do
        completed=0
        for pid in "${pids[@]}"; do
            if ! kill -0 "$pid" 2>/dev/null; then
                ((completed++))
            fi
        done

        local percent=$((completed * 100 / total))
        local bar_length=$((percent / 2)) # 50格进度条
        local bar=$(printf '%-*s' "$bar_length" '' | tr ' ' '=')
        local empty=$(printf '%-*s' "$((50-bar_length))" '' | tr ' ' '.')

        # 取旋转字符
        local spinchar="${spinstr:$spinindex:1}"
        spinindex=$(( (spinindex + 1) % 4 ))
        printf "\r\033[0;31;36mloading[%c] [%-50s] %3d%% (%d/%d)\033[0m" "$spinchar" "$bar$empty" "$percent" "$completed" "$total"

        if [[ $completed -eq $total ]]; then
            break
        fi

        sleep "$delay"
    done

    tput cnorm # 恢复光标
    printf "\n"
}



# 检查文件是否存在
filecheck() {
    local filename="$1"

    (

        # 下载链接列表，按顺序依次尝试默认github
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
    _blue "欢迎使用"
    echo

    mkdir -p "$installdir" "$installdir/core" "$installdir/log" "$installdir/config" "$installdir/module"

    cp -f "$(pwd)/s.sh" "$installdir/s.sh"
    ln -s "$installdir/s.sh" /bin/s

fi



#加载文件

shfiles=(
    'version'
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
    # 检查文件是否存在
    if [[ ! -f "$installdir/$shfile" || ! -s "$installdir/$shfile" ]]; then
        filecheck "$shfile" # 如果文件不存在或为空，调用 filecheck
        pids+=($!)          # 收集子进程 PID
    fi
done
if [[ ${#pids[@]} -gt 0 ]]; then
    loadingprogressbar "${pids[@]}" # 显示加载动画
    wait                 # 等待所有子进程完成
fi

for shfile in "${shfiles[@]}"; do
    #如果是sh脚本则加载
    if [[ $shfile == *.sh ]]; then
        #加载脚本
        source "$installdir/$shfile"
    fi
done

#加载版本
selfversion=$(cat $installdir/version)

# 版本更新检测逻辑
getlatestversion() {
    (
        # 下载链接列表，复用filecheck的多源逻辑
        proxylinks=(
            "http://raw.githubusercontent.com"
            "https://gh.ddlc.top/http://raw.githubusercontent.com"
            "https://git.886.be/http://raw.githubusercontent.com"
        )
        timeout=4
        success=0
        for proxylink in "${proxylinks[@]}"; do
            wget -q --timeout="$timeout" "${proxylink}/sshpc/s/main/version" -O "$latestversion_file.tmp" >/dev/null 2>&1
            if [[ -f "$latestversion_file.tmp" && -s "$latestversion_file.tmp" ]]; then
                mv "$latestversion_file.tmp" "$latestversion_file"
                success=1
                break
            else
                rm -f "$latestversion_file.tmp"
            fi
        done
        
    ) &
}
latestversion_file="$installdir/config/latestversion"

if [ ! -f "$latestversion_file" ] ; then
touch "$latestversion_file" 
getlatestversion
fi

current_time=$(date +%s)
file_mod_time=$(stat -c %Y "$latestversion_file" 2>/dev/null)
time_diff=$((current_time - file_mod_time))

# 如果时间差超过1h或文件不存在，则后台更新latestversion
if [ -z "$file_mod_time" ] || [ $time_diff -ge 3600 ]; then
    getlatestversion
fi

# 加载最新版本号
latestversion=$(cat "$latestversion_file" 2>/dev/null)

#主函数
main() {
    menuname='首页'
    echo "main" >$installdir/config/lastfun

    options=("状态" statusfun "软件管理" softwarefun "网络管理" networkfun "系统管理" systemfun "docker管理" dockerfun "其他工具" ordertoolsfun "升级脚本" updateself "卸载脚本" uninstallfun)
    menu "${options[@]}"
}

#判断配置文件是否存在或是否是真实函数

if [ -z "$(cat $installdir/config/lastfun)" ]; then
    main
else
    $(cat $installdir/config/lastfun)
fi
