#!/bin/bash
export LANG=en_US.UTF-8
# 配置区
# 安装目录 (root登录 /root/s)
installdir=$HOME/s
# 配置文件下载代理主机列表（github加速）
proxyhost=(
    "https://gh.ddlc.top"
    "https://gh-proxy.com"
    "https://edgeone.gh-proxy.com"
    "https://cdn.gh-proxy.com"
    "https://hk.gh-proxy.com"
)

# 默认主页
menuname='主页'
#分支(main 正式版 dev开发版)
branch='dev'
# 日期时间
datevar=$(date +"%Y-%m-%d %H:%M:%S")
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
    
    _green '# 交互式shell脚本工具'
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

#菜单渲染
menu() {
    # 渲染菜单前 检查是否有beforeMenu函数，执行
    declare -F beforeMenu >/dev/null 2>&1 && beforeMenu
    
    
    local options=("$@")
    local num_options=${#options[@]}
    local max_len=0
    
    for ((i = 0; i < num_options; i += 1)); do
        local str_len=${#options[i]}
        ((str_len > max_len)) && max_len=$str_len
    done
    
    for ((i = 0; i < num_options; i += 4)); do
        printf "%s%*s  " "$((i / 2 + 1)): ${options[i]}" "$((max_len - ${#options[i]}))"
        [[ -n "${options[i + 2]}" ]] && printf "$((i / 2 + 2)): ${options[i + 2]}"
        echo -e "\n"
    done
    
    _blue "0: 首页 b: 返回 q: 退出"
    
    echo
    read -ep "请输入命令号(0-$((num_options / 2))): " number
    
    if [[ $number -ge 1 && $number -le $((num_options / 2)) ]]; then
        #找到函数名索引
        local action_index=$((2 * (number - 1) + 1))
        #函数名赋值
        parentfun=${options[action_index]}
        #记录运行日志
        declare -F slog >/dev/null 2>&1 && slog set runscript "$datevar | $menuname | ${options[action_index]} (${options[action_index - 1]})"
        
        #函数执行
        ${options[action_index]}
        nextrun
        elif [[ $number == 0 ]]; then
        main
        elif [[ $number == 'b' ]]; then
        if [[ -n "${FUNCNAME[3]}" ]]; then
            ${FUNCNAME[3]}
        else
            main
        fi
        elif [[ $number == 'q' ]]; then
        echo
        kill -15 $$
    else
        echo
        _red '输入有误  回车返回首页'
        waitinput
        main
    fi
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

# 等待输入
waitinput() {
    echo
    read -n1 -r -p "按任意键继续...(退出 Ctrl+C)"
}
#继续执行函数
nextrun() {
    waitinput
    if [ -z "$(cat $installdir/config/lastfun)" ]; then
        main
    else
        $(cat $installdir/config/lastfun)
    fi
    
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
                printf "\r\033[0;31;36m[ %c ] loading ...\033[0m" "$spinstr"
                local spinstr=$temp${spinstr%"$temp"}
                sleep $delay
            fi
        done
        [[ $all_done == true ]] && break
    done
    
    tput cnorm        # 恢复光标
    printf "\r\033[K" # 清除行
}

#检测命令是否存在
_exists() {
    local cmd="$1"
    which $cmd >/dev/null 2>&1
    local rt=$?
    return ${rt}
}

#移除脚本
removeself() {
    rm -rf $installdir/core/*
    rm -rf $installdir/config/*
    rm -rf $installdir/module/*
    rm -rf $installdir/version
}

#卸载脚本
uninstallfun() {
    _red '卸载核心和所有模块？'
    waitinput
    
    removeself
    #写入日志
    slog set install "$datevar  | 脚本卸载 | v$selfversion"
    read -ep "是否删除配置&日志 (默认n): " yorn
    if [[ "$yorn" = "y" ]]; then
        rm -rf $installdir
        rm -rf /bin/s
    fi
    _blue '卸载完成'
    echo
    kill -15 $$
    
}

# 通用下载函数：从镜像列表中依次尝试下载文件
download_file() {
    local filename="$1"   # 要下载的文件名（带路径，如 module/status.sh）
    local output="$2"     # 输出路径（完整路径，不只是目录）
    local timeout=3

    for base in "${proxylinks[@]}"; do
        wget -q --timeout="$timeout" "${base}/sshpc/s/$branch/$filename" -O "$output"
        if [[ -s "$output" ]]; then
            return 0
        else
            rm -f "$output"
        fi
    done

    return 1
}

# 下载文件（后台模式，用于并发下载）
download_file_bg() {
    local filename="$1"
    local output="$installdir/$filename"

    (
        if ! download_file "$filename" "$output"; then
        _red "文件 $filename 下载失败！"
        exit 1
        fi
    ) &
}

# 升级自身脚本函数
updateself() {
    local tmpdir="$installdir/tmp"
    mkdir -p "$tmpdir"

    _blue "尝试下载最新版脚本和版本信息..."

    local s_ok=false v_ok=false

    if download_file "s.sh" "$tmpdir/s.sh"; then
        _green "s.sh 下载成功"
        s_ok=true
    else
        _red "s.sh 下载失败"
    fi

    if download_file "version" "$tmpdir/version"; then
        _green "version 下载成功"
        v_ok=true
    else
        _yellow "version 下载失败"
    fi

    if $s_ok && $v_ok; then
        _blue "验证通过，准备更新"
        cp "$tmpdir/s.sh" "$installdir/s.sh"
        cp "$tmpdir/version" "$installdir/version"
        chmod +x "$installdir/s.sh"

        slog set install "$datevar  | 脚本升级"
        _blue "卸载旧版本..."
        removeself

        exec "$installdir/s.sh"
    else
        _red "升级条件不满足，未执行更新"
    fi

    rm -rf "$tmpdir"
}

# 版本检测函数
selfversionfun() {
    selfversion=$(cat "$installdir/version")

    latestversion_file="$installdir/config/latestversion"
    [[ -f "$latestversion_file" ]] || touch "$latestversion_file"

    getlatestversion() {
        (
            local tmpfile="$latestversion_file.tmp"
            if download_file "version" "$tmpfile"; then
                mv "$tmpfile" "$latestversion_file"
            else
                rm -f "$tmpfile"
            fi
        ) &
    }

    local current_time=$(date +%s)
    local file_mod_time=$(stat -c %Y "$latestversion_file" 2>/dev/null || echo 0)
    local time_diff=$((current_time - file_mod_time))

    # 如果文件超过1小时没更新，就后台拉取一次
    [[ $time_diff -ge 3600 ]] && getlatestversion

    latestversion=$(cat "$latestversion_file" 2>/dev/null)
}

# 加载文件
loadfilefun() {
    if [ ! -d "$installdir" ]; then
        slogo
        _blue "欢迎使用"
        mkdir -p "$installdir" "$installdir/log" "$installdir/config" "$installdir/module"
        cp -f "$(pwd)/s.sh" "$installdir/s.sh"
        ln -s "$installdir/s.sh" /bin/s
    fi

    # 初始化下载地址列表
    local original_url="http://raw.githubusercontent.com"
    proxylinks=("$original_url")
    for host in "${proxyhost[@]}"; do
        proxylinks+=("${host}/${original_url}")
    done

    # 需要下载的文件
    shfiles=(
        'version'
        'module/status.sh'
        'module/software.sh'
        'module/network.sh'
        'module/system.sh'
        'module/docker.sh'
        'module/ordertools.sh'
    )

    # 并行下载缺失文件
    pids=()
    for shfile in "${shfiles[@]}"; do
        if [[ ! -s "$installdir/$shfile" ]]; then
            download_file_bg "$shfile" # 如果文件不存在或为空，调用 filecheck
            pids+=($!)          # 收集子进程 PID
        fi
    done

    if [[ ${#pids[@]} -gt 0 ]]; then
        echo
        _yellow '文件下载中'
        loadingprogressbar "${pids[@]}" # 显示下载进度
        wait # 等待所有子进程完成
    fi

    # 加载脚本
    for shfile in "${shfiles[@]}"; do
        [[ $shfile == *.sh ]] && source "$installdir/$shfile"
    done
}

#终止和日志函数
exceptionfun(){
    #异常终止函数
    _exit() {
        if [ -e "./speedtest-cli/speedtest" ]; then
            rm -rf ./speedtest-cli
        fi
        exit 1
    }
    #异常终止执行函数
    trap _exit INT QUIT TERM
    
    LOGFILE="${installdir}/log/runscript.log"
    
    # 把 xtrace 输出到日志文件
    exec 19>>"$LOGFILE"
    set -T   # 子 shell / 函数也触发 DEBUG
    
    # 白名单数组（不写日志的外部命令）
    CMD_WHITELIST=("sleep" "clear" "tr" "wc" "cat" "awk" "sort" "sed")
    
    # 判断是否在白名单里
    in_whitelist() {
        local c="$1"
        for w in "${CMD_WHITELIST[@]}"; do
            if [[ "$c" == "$w" ]]; then
                return 0
            fi
        done
        return 1
    }
    
    # 捕获外部程序命令
    BASH_COMMAND_LOGGER() {
        local cmd="${BASH_COMMAND%% *}"   # 取第一个单词
        # 仅记录外部程序 & 不在白名单
        if [ "$(type -t "$cmd" 2>/dev/null)" = "file" ] && ! in_whitelist "$cmd"; then
            echo "$(date '+%F %T') [$$] $BASH_COMMAND" >&19
        fi
    }
    trap BASH_COMMAND_LOGGER DEBUG
    
}

#s日志读写
slog() {
    local method=$1 #set or get
    local file=$2
    local info=$3
    
    case $method in
        set) #写入#
            echo $info >>${installdir}/log/$file.log
        ;;
        get) #读取#
            tail -20 ${installdir}/log/$file.log
            
        ;;
        *)
            echo 'log error'
            
        ;;
    esac
    
}

#菜单顶部内容钩子函数
beforeMenu(){
    if [ $is_param_mode -eq 1 ]; then
        return
    fi
    clear
    
    echo
    # 检查是否有新版本
    if [ -n "$latestversion" ] && [ "$selfversion" != "$latestversion" ]; then
        _yellow "发现新版本！v: $latestversion"
        echo
    fi
    _blue "> ----- S脚本 当前目录: [ $(pwd) ] -------- < v: $selfversion"
    echo
    _yellow "当前菜单: $menuname "
    echo
}

#参数检测
paramdetectionfun(){
    # 处理命令行参数（直接执行函数）
    is_param_mode=0  # 新增：标记是否为参数模式
    if [ $# -gt 0 ]; then
        is_param_mode=1  # 有参数时进入参数模式
        # 循环执行所有参数对应的函数
        for func in "$@"; do
            # 检查函数是否存在
            if declare -F "$func" >/dev/null 2>&1; then
                $func  # 执行函数
            else
                _red "错误：函数 '$func' 不存在"
                exit 1
            fi
        done
        exit 0
    fi
}

#主函数
main() {
    menuname='首页'
    echo "main" >$installdir/config/lastfun
    
    options=("状态" statusfun "软件管理" softwarefun "网络管理" networkfun "系统管理" systemfun "docker管理" dockerfun "其他工具" ordertoolsfun "升级脚本" updateself "卸载脚本" uninstallfun)
    menu "${options[@]}"
}

loadfilefun
exceptionfun
selfversionfun
paramdetectionfun


#判断配置文件是否存在或是否是真实函数

if [ -z "$(cat $installdir/config/lastfun)" ]; then
    main
else
    $(cat $installdir/config/lastfun)
fi
