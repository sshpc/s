#!/bin/bash
export LANG=en_US.UTF-8
# 配置区
# 安装目录 (root登录 /root/s)
installdir="$HOME/s"

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
    _green '# 交互式shell脚本工具'
    _green '# Author:SSHPC <https://github.com/sshpc>'
    echo
}

#回首页
backtomain(){
    echo
    _red '输入有误  回车返回首页'
    waitinput
    main
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

#解析ini
get_ini_value() {
    local section="$1"
    local key="$2"
    local file="$3"
    
    
    # 使用sed先处理文件：移除Windows换行符^M，再用awk解析
    result=$(sed 's/\r$//' "$file" | awk -v target_section="$section" -v target_key="$key" '
        BEGIN {
            in_target = 0
            found = 0
        }

        # 清除首尾空白
        {
            gsub(/^[ \t]+|[ \t]+$/, "", $0)
        }

        # 跳过空行
        $0 == "" { next }

        # 匹配section行
        /^\[.*\]$/ {
            current_section = substr($0, 2, length($0)-2)
            gsub(/^[ \t]+|[ \t]+$/, "", current_section)
            in_target = (current_section == target_section)
            if (in_target) {
                #print "调试: 找到目标section [" current_section "]" > "/dev/stderr"
            }
            next
        }

        # 在目标section中查找key
        in_target {
            if ($0 ~ "^[ \t]*" target_key "[ \t]*=") {
                # 提取值
                value = substr($0, index($0, "=") + 1)
                gsub(/^[ \t]+|[ \t]+$/, "", value)
                print value
                found = 1
                exit 0
            }
        }

        END {
            if (!found) exit 1
        }
    ')
    
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo "Error: 未找到 key '$key' 在 section '$section' 中" >&2
        return $exit_code
    fi
    
    echo "$result"
}

# 列出 modules.conf 中所有 section (模块 id)
list_all_modules_from_conf() {
    local file="$1"
    awk '/^\[.*\]/{gsub(/\[|\]/,"",$0); print $0}' "$file"
}

# 打印模块清单：全部以及已安装
modules_list() {
    local conf="$installdir/modules.conf"
    if [[ ! -f "$conf" ]]; then
        _yellow "未找到模块清单 ($conf)"
        return
    fi
    echo
    _blue "全部模块："
    while read -r m; do
        # 清除回车符、换行符等控制字符
        m=$(echo "$m" | tr -d '\r\n\t')
        [[ -z "$m" ]] && continue
        echo $m
        local func=$(get_ini_value "$m" "name" "$conf")
        local desc=$(get_ini_value "$m" "desc" "$conf")
        local req=$(get_ini_value "$m" "required" "$conf")
        printf "  - %s (%s) [required=%s]\n" "$m" "${desc:-no-desc}" "${req:-no}"
    done < <(list_all_modules_from_conf "$conf")
    
    echo
    _blue "已安装模块："
    for f in "$installdir/module"/*.sh; do
        [[ ! -f "$f" ]] && continue
        bn=$(basename "$f" .sh)
        printf "  - %s\n" "$bn"
    done
}

# 下载单个模块（module name，不带 .sh）
download_module() {
    local mod="$1"
    local target_dir="$installdir/module"
    mkdir -p "$target_dir"
    local filename="module/${mod}.sh"
    local outfile="$target_dir/${mod}.sh"
    
    if [[ -f "$outfile" ]]; then
        _yellow "模块 $mod 已存在，跳过下载"
        return 0
    fi
    
    if download_file "$filename" "$outfile"; then
        _green "模块 $mod 下载成功"
        return 0
    else
        _red "模块 $mod 下载失败"
        return 1
    fi
}

# 安装模块
modules_install() {
    _blue "安装模块"
    echo
    local conf="$installdir/modules.conf"
    [[ -f "$conf" ]] || { _red "缺少 modules.conf，无法安装模块"; return 1; }
    modules_list
    echo
    read -ep "全部安装-回车 基础安装-n 跳过-p: " choice
    
    # 获取并处理所有模块（清除控制字符和空行）
    local modules=($(list_all_modules_from_conf "$conf" | tr -d '\r\n\t' | grep -v '^$'))
    local to_download=()
    
    # 筛选需要下载的模块
    case "$choice" in
        n)
            _blue "仅安装 required 模块"
            for m in "${modules[@]}"; do
                [[ $(get_ini_value "$m" "required" "$conf") == "yes" ]] && to_download+=("$m")
            done
        ;;
        p)
            _yellow "跳过模块安装"
        ;;
        *)
            
            _blue "安装全部模块"
            to_download=("${modules[@]}")
        ;;
    esac
    
    # 并发下载处理
    if [[ ${#to_download[@]} -gt 0 ]]; then
        local pids=()
        for m in "${to_download[@]}"; do
            download_file_bg "module/${m}.sh" &  # 后台并发下载
            pids+=($!)
        done
        _yellow "模块下载中"
        loadingprogressbar "${pids[@]}"
        wait  # 等待所有下载完成
    fi
}

# 卸载模块：all / single
modules_uninstall() {
    echo
    read -ep "卸载全部模块请输入 a , 卸载单个请输入模块名 (或回车取消): " choice
    if [[ "$choice" == "a" ]]; then
        _yellow "卸载全部模块..."
        rm -f "$installdir/module"/*.sh
        _green "已卸载全部模块"
        elif [[ -n "$choice" ]]; then
        if [[ -f "$installdir/module/${choice}.sh" ]]; then
            rm -f "$installdir/module/${choice}.sh"
            _green "模块 $choice 已卸载"
        else
            _red "模块 $choice 未安装"
        fi
    else
        _yellow "已取消"
    fi
}

# 模块管理菜单（加入到脚本设置中）
module_manager() {
    menuname='模块管理'
    echo "selfsetting" >$installdir/config/lastfun
    options=("查看模块列表" modules_list "安装模块" modules_install "卸载模块" modules_uninstall)
    menu "${options[@]}"
}

#菜单渲染
menu() {
    if [ $is_param_mode -eq 1 ]; then
        return
    fi
    clear
    
    echo
    
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
    
    
    _blue "0: 首页 b: 返回 q: 退出 s:脚本设置"
    echo
    read -ep "请输入命令号(0-$((num_options / 2))): " number
    
    case "$number" in
        [1-9]|[1-9][0-9]*)
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
            else
                backtomain
            fi
        ;;
        0)
            main
        ;;
        b)
            if [[ -n "${FUNCNAME[3]}" ]]; then
                ${FUNCNAME[3]}
            else
                main
            fi
        ;;
        q)
            echo
            kill -15 $$
        ;;
        s)
            selfsetting
        ;;
        *)
            backtomain
        ;;
    esac
}

#重启脚本
selfrestart(){
    echo
    _green '保持配置..'
    sleep 0.5
    _yellow '重启脚本..'
    echo
    sleep 1
    exec s
}

#脚本设置
selfsetting(){
    
    #移除脚本
    removeself() {
        rm -rf $installdir/core/*
        rm -rf $installdir/config/*
        rm -rf $installdir/module/*
        rm -rf $installdir/version
    }
    
    #卸载脚本
    uninstallfun() {
        read -ep "确认卸载 (y/n, 默认n): " delself
        if [[ "$delself" != "y" ]]; then
            _yellow "已取消卸载"
            waitinput
            return
        fi
        
        removeself
        # 写入日志
        slog set install "$datevar  | 脚本卸载 | v$selfversion"
        
        read -ep "是否删除配置&日志 (y/n, 默认n): " delconf
        if [[ "$delconf" == "y" ]]; then
            rm -rf "$installdir" /bin/s
            _green "已删除配置和日志"
        else
            _yellow "保留了配置和日志"
        fi
        
        _blue '卸载完成'
        echo
        waitinput
        kill -15 $$
        
    }
    
    # 升级脚本
    updateself() {
        [[ $branch == 'main' ]] && _yellow "升级脚本? v:$selfversion -> v:$latestversion"
        waitinput
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
            loadfilefun
            exec "$installdir/s.sh"
        else
            _red "升级条件不满足，未执行更新"
        fi
        
        rm -rf "$tmpdir"
    }
    
    
    catselfrunlog(){
        echo
        slog get runscript
        echo
    }
    
    openexceptionlog(){
        echo 'open' >$installdir/config/exception
        selfrestart
    }
    closeexceptionlog(){
        echo 'close' >$installdir/config/exception
        selfrestart
    }
    switchoverbeta(){
        echo 'dev' >$installdir/config/branch
        selfrestart
    }
    
    switchovermain(){
        echo 'main' >$installdir/config/branch
        selfrestart
    }
    
    
    
    menuname='脚本设置'
    echo "selfsetting" >$installdir/config/lastfun
    
    options=("查看脚本执行日志" catselfrunlog "模块管理" module_manager "打开详细执行日志" openexceptionlog "关闭详细执行日志" closeexceptionlog "升级脚本" updateself "切换成beta版" switchoverbeta "切换成正式版" switchovermain "卸载脚本" uninstallfun)
    menu "${options[@]}"
}

#菜单顶部内容
beforeMenu(){
    _blue "> ---  当前目录: [ $(pwd) ] ---- < v:${branch}-$selfversion"
    echo
    _yellow "当前菜单: $menuname "
    echo
}
#主函数
main() {
    menuname='首页'
    echo "main" >$installdir/config/lastfun
    beforeMenu(){
    slogo
    # 检查是否有新版本
    if [ -n "$latestversion" ] && [ "$selfversion" != "$latestversion" ]; then
        _yellow "发现新版本 $latestversion ！"
        echo
    fi
    _blue "> ---  当前目录: [ $(pwd) ] ---- < v:${branch}-$selfversion"
    echo
    _yellow "当前菜单: $menuname "
    echo
    }
    
    local conf="$installdir/modules.conf"
    local options=()
    
    for m in $(list_all_modules_from_conf "$conf"); do
        # 清除回车符、换行符等控制字符
        m=$(echo "$m" | tr -d '\r\n\t')
        if  [[ -s "$installdir/module/$m.sh" ]] ; then
            # desc 用作显示文字， name 是要执行的函数
            local desc=$(get_ini_value "$m" "desc" "$conf")
            local func=$(get_ini_value "$m" "name" "$conf")
            [[ -z "$desc" ]] && desc="$m"
            [[ -z "$func" ]] && func="$m"
            options+=("$desc" "$func")
        fi
    done
    if [ ${#options[@]} -eq 0 ]; then
        options+=("模块为空,进入模块管理" module_manager)
    fi
    
    menu "${options[@]}"
}

#脚本初始化
selfinitfun(){
    if [ ! -d "$installdir" ]; then
        slogo
        _blue "欢迎使用"
        mkdir -p "$installdir" "$installdir/log" "$installdir/config" "$installdir/module"
        cp -f "$(pwd)/s.sh" "$installdir/s.sh"
        ln -s "$installdir/s.sh" /bin/s
        #默认关闭详细执行日志
        echo 'close' >$installdir/config/exception
        
        echo 'dev' >$installdir/config/branch
    fi
    
    #检查版本
    if [[ -f "$installdir/config/branch" ]] && grep -q '^dev$' "$installdir/config/branch"; then
        branch='dev'
    else
        branch='main'
    fi
    
    # 初始化下载地址列表
    local original_url="http://raw.githubusercontent.com"
    proxylinks=("$original_url")
    for host in "${proxyhost[@]}"; do
        proxylinks+=("${host}/${original_url}")
    done
}

# 加载文件
loadfilefun() {
    
    # 核心文件
    shfiles=(
        'version'
        'modules.conf'
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
        _yellow '核心文件下载'
        loadingprogressbar "${pids[@]}" # 显示下载进度
        wait # 等待所有子进程完成
    fi
    
    # 如果是首次安装（module 目录为空或没有模块），让用户选择全部安装或仅默认安装
    if [[ -z "$(ls -A $installdir/module 2>/dev/null)" ]] && [[ -s "$installdir/modules.conf" ]]; then
        echo
        modules_install
    fi
    
    # 加载 modules 目录下所有模块脚本（存在的才加载）
    for mfile in "$installdir/module"/*.sh; do
        [[ -f "$mfile" ]] && source "$mfile"
    done
}

#终止和日志函数
exceptionfun(){
    #异常终止函数
    _exit() {
        if [ -e "./speedtest-cli/speedtest" ]; then
            rm -rf ./speedtest-cli
        fi
        [[ -d "$installdir/tmp" ]] && rm -rf $installdir/tmp
        exit 1
    }
    #异常终止执行函数
    trap _exit INT QUIT TERM
    
    # 检查exceptionlogvar 是否开启(判断 $installdir/config/exception 文件是否有内容 'open' 则开启)
    if [[ -f "$installdir/config/exception" ]] && grep -q '^open$' "$installdir/config/exception"; then
        LOGFILE="${installdir}/log/runscript.log"
        
        # 把 xtrace 输出到日志文件
        exec 19>>"$LOGFILE"
        set -T   # 子 shell / 函数也触发 DEBUG
        
        # 白名单数组（不写日志的外部命令）
        CMD_WHITELIST=("sleep" "clear" "tr" "wc" "cat" "awk" "sort" "sed")
        
        # 用关联数组
        declare -A WHITELIST_MAP
        for w in "${CMD_WHITELIST[@]}"; do
            WHITELIST_MAP["$w"]=1
        done
        
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
            # 避免递归触发日志函数
            if [[ "$BASH_COMMAND" == *"BASH_COMMAND_LOGGER"* ]]; then
                return 0
            fi
            local cmd="${BASH_COMMAND%% *}"
            
            # 命令跳过
            if [[ -n "${WHITELIST_MAP["$cmd_name"]}" ]]; then
                return 0
            fi
            
            # 仅记录外部程序 & 不在白名单
            if [ "$(type -t "$cmd" 2>/dev/null)" = "file" ]; then
                local log_time=$(date '+%F %T')
                printf "%s [%d] %s\n" "$log_time" "$$" "$BASH_COMMAND" >> "$LOGFILE"
            fi
        }
        trap BASH_COMMAND_LOGGER DEBUG
    fi
    
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

#脚本运行
selfrun(){
    
    # 检测处理命令行参数（直接执行函数）
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
    
    #交互运行,判断配置文件是否存在或是否是真实函数
    if [ -z "$(cat $installdir/config/lastfun)" ]; then
        main
    else
        $(cat $installdir/config/lastfun)
    fi
}

selfinitfun
loadfilefun
exceptionfun
selfversionfun
selfrun



