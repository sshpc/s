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

next(){
    echo '----------------------------'
}

dwidth() {
    local len
    len=$(echo -n "$1" | wc -L)
    echo "$len"
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

#通用安装函数
check_and_install() {
    
    # 检测包管理器
     if command -v apt &>/dev/null; then
        PKG_MGR="apt"
        INSTALL_CMD="apt install -y"
    elif command -v apt-get &>/dev/null; then
        PKG_MGR="apt-get"
        INSTALL_CMD="apt-get install -y"
    elif command -v yum &>/dev/null; then
        PKG_MGR="yum"
        INSTALL_CMD="yum install -y"
        SEARCH_CMD="yum search"
    elif command -v dnf &>/dev/null; then
        PKG_MGR="dnf"
        INSTALL_CMD="dnf install -y"
        SEARCH_CMD="dnf search"
    elif command -v apk &>/dev/null; then
        PKG_MGR="apk"
        INSTALL_CMD="apk add --no-cache"
        SEARCH_CMD="apk search"
    else
        _red "未检测到支持的包管理器 （apt, yum, dnf, apk）"
        return 1
    fi

     # 逐个检查并安装
    for cmd in "$@"; do

        # 检查命令是否已存在
        if command -v "$cmd" &>/dev/null; then
            continue
        fi

        _blue "正在尝试安装 $cmd ..."
        if ! $INSTALL_CMD "$cmd" ;then
            _red "安装 '$cmd' 失败，请手动检查包名"
            continue
        fi

    done
}


# 通用下载函数：从镜像列表中依次尝试下载文件
download_file() {
    local filename="$1"   # 要下载的文件名（带路径，如 module/status.sh）
    local output="$2"     # 输出路径（完整路径，不只是目录）
    local timeout=3
    
    for base in "${proxylinks[@]}"; do
        wget -q --timeout="$timeout" "${base}/sshpc/s/main/$filename" -O "$output"
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
        #echo $m
        local func=$(get_ini_value "$m" "name" "$conf")
        local desc=$(get_ini_value "$m" "desc" "$conf")
        local req=$(get_ini_value "$m" "required" "$conf")
        printf " - %s (%s) [required=%s]\n" "$m" "${desc:-no-desc}" "${req:-no}"
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
    local conf="$installdir/modules.conf"
    [[ -f "$conf" ]] || { _red "缺少 modules.conf，无法安装模块"; return 1; }
    modules_list
    echo
    read -ep "全部安装-回车 基础安装-n 跳过-p: " choice
    
    local to_download=()
    
    # 筛选需要下载的模块
    case "$choice" in
        n)
            _blue "仅安装 required 模块"
            for m in $(list_all_modules_from_conf "$conf"); do
                m=$(echo "$m" | tr -d '\r\n\t')
                [[ $(get_ini_value "$m" "required" "$conf") == "yes" ]] && to_download+=("$m")
            done
        ;;
        p)
            _yellow "跳过模块安装"
        ;;
        *)
            
            _blue "安装全部模块"
            for m in $(list_all_modules_from_conf "$conf"); do
                m=$(echo "$m" | tr -d '\r\n\t')
                to_download+=("$m")
            done
        ;;
    esac

    
    # 并发下载处理
    if [[ ${#to_download[@]} -gt 0 ]]; then
        local pids=()
        for m in "${to_download[@]}"; do
            download_file_bg "module/${m}.sh"
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

# ==================== 版本管理 ====================

# 备份当前版本到 bak 目录
backup_current_version() {
    local bakdir="$installdir/bak/$selfversion"
    mkdir -p "$bakdir/module"
    
    cp -f "$installdir/s.sh" "$bakdir/s.sh"
    cp -f "$installdir/version" "$bakdir/version"
    [[ -f "$installdir/modules.conf" ]] && cp -f "$installdir/modules.conf" "$bakdir/modules.conf"
    for f in "$installdir/module"/*.sh; do
        [[ -f "$f" ]] && cp -f "$f" "$bakdir/module/"
    done
}

# 列出所有备份版本
list_backup_versions() {
    local bakroot="$installdir/bak"
    if [[ ! -d "$bakroot" ]] || [[ -z "$(ls -A "$bakroot" 2>/dev/null)" ]]; then
        _yellow "暂无备份版本"
        return 1
    fi
    echo
    _blue "已备份版本列表："
    local idx=0
    for vdir in "$bakroot"/*/; do
        [[ ! -d "$vdir" ]] && continue
        local ver=$(basename "$vdir")
        local marker=""
        [[ "$ver" == "$selfversion" ]] && marker=" (当前)"
        ((idx++))
        printf "  %d. %s%s\n" "$idx" "$ver" "$marker"
    done
    [[ $idx -eq 0 ]] && _yellow "暂无备份版本"
}

# 切换到指定备份版本
switch_version() {
    local target_ver="$1"
    local bakdir="$installdir/bak/$target_ver"
    
    if [[ ! -d "$bakdir" ]]; then
        _red "备份版本 $target_ver 不存在"
        return 1
    fi
    
    if [[ "$target_ver" == "$selfversion" ]]; then
        _yellow "当前已是 v$target_ver，无需切换"
        return 0
    fi
    
    _yellow "切换到版本 v$selfversion -> v$target_ver"
    
    cp -f "$bakdir/s.sh" "$installdir/s.sh"
    cp -f "$bakdir/version" "$installdir/version"
    [[ -f "$bakdir/modules.conf" ]] && cp -f "$bakdir/modules.conf" "$installdir/modules.conf"
    rm -f "$installdir/module"/*.sh
    if [[ -d "$bakdir/module" ]]; then
        for f in "$bakdir/module"/*.sh; do
            [[ -f "$f" ]] && cp -f "$f" "$installdir/module/"
        done
    fi
    
    chmod +x "$installdir/s.sh"
    slog set install "$datevar  | 版本切换 | v$selfversion -> v$target_ver"
    _green "已切换到版本 v$target_ver"
}

# 交互式版本选择（数字选择，类似 docker restart）
version_select() {
    local bakroot="$installdir/bak"
    if [[ ! -d "$bakroot" ]] || [[ -z "$(ls -A "$bakroot" 2>/dev/null)" ]]; then
        _yellow "暂无可切换的备份版本"
        return
    fi

    local versions=()
    for vdir in "$bakroot"/*/; do
        [[ ! -d "$vdir" ]] && continue
        versions+=("$(basename "$vdir")")
    done

    if [[ ${#versions[@]} -eq 0 ]]; then
        _yellow "暂无可切换的备份版本"
        return
    fi

    echo
    _blue "选择版本 (输入序号):"
    echo
    for i in "${!versions[@]}"; do
        local marker=""
        [[ "${versions[$i]}" == "$selfversion" ]] && marker=" (当前)"
        printf "  %d) %s%s\n" "$((i+1))" "${versions[$i]}" "$marker"
    done
    echo
    read -ep "请输入序号 [1-${#versions[@]}], 回车取消: " choice
    [[ -z "$choice" ]] && { _yellow "已取消"; return; }

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#versions[@]} )); then
        _red "无效序号"
        return
    fi

    local target_ver="${versions[$((choice-1))]}"
    if [[ "$target_ver" == "$selfversion" ]]; then
        _yellow "当前已是 $target_ver"
        return
    fi

    switch_version "$target_ver"
    selfrestart
}

# 清理旧备份（保留最近N个）
cleanup_old_backups() {
    local keep=${1:-5}
    local bakroot="$installdir/bak"
    [[ ! -d "$bakroot" ]] && return
    
    local dirs=()
    for d in "$bakroot"/*/; do
        [[ -d "$d" ]] && dirs+=("$d")
    done
    
    local count=${#dirs[@]}
    if (( count <= keep )); then
        return
    fi
    
    # 按修改时间排序，删除最旧的
    local to_remove=$((count - keep))
    local sorted=($(ls -dt "$bakroot"/*/ 2>/dev/null))
    for ((i = count - 1; i >= count - to_remove; i--)); do
        [[ -d "${sorted[i]}" ]] && rm -rf "${sorted[i]}"
    done
}

# 版本管理菜单
version_manager() {
    menuname='版本管理'
    echo "selfsetting" >$installdir/config/lastfun
    options=("查看备份版本" list_backup_versions "切换版本" version_select "升级到最新" updateself)
    menu "${options[@]}"
}

# ==================== 菜单渲染 ====================

staticmenu() {
    if [ $is_param_mode -eq 1 ]; then
        return
    fi
    printf "\033[H\033[2J"
    echo
    
    declare -F beforeMenu >/dev/null 2>&1 && beforeMenu
    
    local options=("$@")
    local num_options=${#options[@]}
    local max_len=0
    
    for ((i = 0; i < num_options; i += 1)); do
        local w
        w=$(dwidth "${options[i]}")
        ((w > max_len)) && max_len=$w
    done
    
    for ((i = 0; i < num_options; i += 4)); do
        local w
        w=$(dwidth "${options[i]}")
        local pad=$((max_len - w))
        printf "%s%*s  " "$((i / 2 + 1)): ${options[i]}" "$pad"
        if (( i + 2 < num_options )); then  
            if [[ -n "${options[i + 2]}" ]]; then  
                printf "$((i / 2 + 2)): ${options[i + 2]}"
            fi
        fi
        echo -e "\n"
    done
    
    
    _blue "0: 首页 b: 返回 q: 退出 s:脚本设置"
    echo
    read -ep "请输入命令号(0-$((num_options / 2))): " number
    
    case "$number" in
        [1-9]|[1-9][0-9]*)
            if [[ $number -ge 1 && $number -le $((num_options / 2)) ]]; then
                local action_index=$((2 * (number - 1) + 1))
                parentfun=${options[action_index]}
                declare -F slog >/dev/null 2>&1 && slog set runscript "$datevar | $menuname | ${options[action_index]} (${options[action_index - 1]})"
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

menu() {
    if [ "$menustyle" = "staticmenu" ]; then
        staticmenu "$@"
        return
    fi

    if [ "$is_param_mode" -eq 1 ]; then
        return
    fi

    printf "\033[H\033[2J"
    echo

    declare -F beforeMenu >/dev/null 2>&1 && beforeMenu

    local options=("$@")
    local num_options=${#options[@]}
    
    if (( num_options == 0 )); then
        _blue "没有可用的菜单项"
        read -p "按回车返回..."
        return
    fi
    
    local num_items=$((num_options / 2))

    local max_len=0
    local widths=()
    for ((i = 0; i < num_options; i += 2)); do
        local w
        w=$(dwidth "${options[i]}")
        widths+=("$w")
        ((w > max_len)) && max_len=$w
    done

    local seq_width=${#num_items}
    (( seq_width < 1 )) && seq_width=1

    local terminal_width
    terminal_width=$(tput cols 2>/dev/null || echo 80)

    local cell_width=$((seq_width + 2 + max_len + 4))
    local items_per_row=$((terminal_width / cell_width))

    if (( items_per_row < 1 )); then
        items_per_row=1
    elif (( items_per_row > 5 )); then
        items_per_row=5
    fi

    for ((i = 0; i < num_items; i += items_per_row)); do
        local line_output=""
        for ((j = 0; j < items_per_row; j++)); do
            local current_item_index=$((i + j))
            if (( current_item_index >= num_items )); then
                break
            fi

            local opt_array_idx=$((current_item_index * 2))
            local desc="${options[opt_array_idx]}"
            local display_num=$((current_item_index + 1))
            local w=${widths[current_item_index]}
            local pad=$((max_len - w))
            local padded="${desc}$(printf '%*s' "$pad" '')"
            local formatted_item
            formatted_item=$(printf "%*d: %s" "$seq_width" "$display_num" "$padded")
            
            if (( j == 0 )); then
                line_output="$formatted_item"
            else
                line_output="$line_output    $formatted_item"
            fi
        done
        echo "$line_output"
    done
    echo
    _blue "0: 首页 b: 返回 q: 退出 s:脚本设置"
    echo
    
    read -ep "请输入命令号(0-$num_items): " number

    case "$number" in
        [1-9]|[1-9][0-9]*)
            if [[ $number -ge 1 && $number -le $num_items ]]; then
                local action_index=$((2 * (number - 1) + 1))
                parentfun=${options[action_index]}
                
                declare -F slog >/dev/null 2>&1 && slog set runscript "$datevar | $menuname | ${options[action_index]} (${options[action_index - 1]})"
                
                if declare -f "${options[action_index]}" >/dev/null; then
                    ${options[action_index]}
                    nextrun
                else
                    _red "错误：函数 ${options[action_index]} 未定义"
                    sleep 1
                    backtomain
                fi
            else
                backtomain
            fi
            ;;
        0) main ;;
        b)
            if [[ ${#FUNCNAME[@]} -gt 3 && -n "${FUNCNAME[3]}" ]]; then
                 if declare -f "${FUNCNAME[3]}" >/dev/null; then
                    ${FUNCNAME[3]}
                    return
                fi
            fi
            main
            ;;
        q) echo; kill -15 $$ ;;
        s) selfsetting ;;
        *) backtomain ;;
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
        rm -rf $installdir/modules.conf
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
        slog set install "$datevar  | 脚本卸载 | v$selfversion"
        
        read -ep "是否删除配置&日志&备份 (y/n, 默认n): " delconf
        if [[ "$delconf" == "y" ]]; then
            rm -rf "$installdir" /bin/s
            _green "已删除配置、日志和备份"
        else
            _yellow "保留了配置、日志和备份"
        fi
        
        _blue '卸载完成'
        echo
        waitinput
        kill -15 $$
        
    }
    
    # 升级脚本
    updateself() {
        if [[ "$selfversion" == "$latestversion" ]]; then
            _yellow "当前已是最新版本 v$selfversion"
            read -ep "是否强制重新下载? (y/n, 默认n): " force
            [[ "$force" != "y" ]] && return
        else
            _yellow "升级脚本? v:$selfversion -> v:$latestversion"
            read -ep "确认升级? (y/n/s跳过, 默认y): " upconfirm
            if [[ "$upconfirm" == "s" || "$upconfirm" == "n" ]]; then
                _yellow "已跳过升级"
                return
            fi
        fi
        
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
            local new_ver=$(cat "$tmpdir/version" | tr -d '\r\n\t ')
            
            _blue "备份当前版本 v$selfversion ..."
            backup_current_version
            
            _blue "安装新版本 v$new_ver ..."
            cp "$tmpdir/s.sh" "$installdir/s.sh"
            cp "$tmpdir/version" "$installdir/version"
            chmod +x "$installdir/s.sh"
            
            slog set install "$datevar  | 脚本升级 | v$selfversion -> v$new_ver"
            
            cleanup_old_backups 5
            
            _green "升级完成 v$selfversion -> v$new_ver"
            
            _blue "重新加载模块..."
            rm -f "$installdir/module"/*.sh
            rm -f "$installdir/modules.conf"
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
    
    switchmenumodern(){
        echo 'menu' >$installdir/config/menustyle
        selfrestart
    }
    switchstaticmenu(){
        echo 'staticmenu' >$installdir/config/menustyle
        selfrestart
    }
    
    menuname='脚本设置'
    echo "selfsetting" >$installdir/config/lastfun
    
    options=("查看脚本日志" catselfrunlog "版本管理" version_manager "模块管理" module_manager "打开详细执行日志" openexceptionlog "关闭详细执行日志" closeexceptionlog "升级脚本" updateself "设置响应式菜单样式" switchmenumodern "设置静态菜单样式" switchstaticmenu "卸载脚本" uninstallfun)
    menu "${options[@]}"
}

#菜单顶部内容
beforeMenu(){
    _blue "> ---  当前目录: [ $(pwd) ] ---- < v:$selfversion [$menustyle]"
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
    if [ -n "$latestversion" ] && [ "$selfversion" != "$latestversion" ]; then
        _yellow "发现新版本 $latestversion ！"
        echo
    fi
    _blue "> ---  当前目录: [ $(pwd) ] ---- < v:$selfversion [$menustyle]"
    echo
    _yellow "当前菜单: $menuname "
    echo
    }
    
    local conf="$installdir/modules.conf"
    local options=()
    
    for m in $(list_all_modules_from_conf "$conf"); do
        m=$(echo "$m" | tr -d '\r\n\t')
        if  [[ -s "$installdir/module/$m.sh" ]] ; then
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
        mkdir -p "$installdir" "$installdir/log" "$installdir/config" "$installdir/module" "$installdir/bak"
        cp -f "$(pwd)/s.sh" "$installdir/s.sh"
        ln -s "$installdir/s.sh" /bin/s
        echo 'close' >$installdir/config/exception
        echo 'menu' >$installdir/config/menustyle
    fi
    
    mkdir -p "$installdir/bak"
    
    #读取菜单样式
    if [[ -f "$installdir/config/menustyle" ]] && grep -q '^staticmenu$' "$installdir/config/menustyle"; then
        menustyle='staticmenu'
    else
        menustyle='menu'
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
            download_file_bg "$shfile"
            pids+=($!)
        fi
    done
    
    if [[ ${#pids[@]} -gt 0 ]]; then
        echo
        _yellow '核心文件下载'
        loadingprogressbar "${pids[@]}"
        wait
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
    _exit() {
        if [ -e "./speedtest-cli/speedtest" ]; then
            rm -rf ./speedtest-cli
        fi
        [[ -d "$installdir/tmp" ]] && rm -rf $installdir/tmp
        exit 1
    }
    trap _exit INT QUIT TERM
    
    if [[ -f "$installdir/config/exception" ]] && grep -q '^open$' "$installdir/config/exception"; then
        LOGFILE="${installdir}/log/runscript.log"
        
        exec 19>>"$LOGFILE"
        set -T
        
        CMD_WHITELIST=("sleep" "clear" "tr" "wc" "cat" "awk" "sort" "sed")
        
        declare -A WHITELIST_MAP
        for w in "${CMD_WHITELIST[@]}"; do
            WHITELIST_MAP["$w"]=1
        done
        
        in_whitelist() {
            local c="$1"
            for w in "${CMD_WHITELIST[@]}"; do
                if [[ "$c" == "$w" ]]; then
                    return 0
                fi
            done
            return 1
        }
        
        BASH_COMMAND_LOGGER() {
            if [[ "$BASH_COMMAND" == *"BASH_COMMAND_LOGGER"* ]]; then
                return 0
            fi
            local cmd="${BASH_COMMAND%% *}"
            
            if [[ -n "${WHITELIST_MAP["$cmd_name"]}" ]]; then
                return 0
            fi
            
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
    
    [[ $time_diff -ge 3600 ]] && getlatestversion
    
    latestversion=$(cat "$latestversion_file" 2>/dev/null)
}

#脚本运行
selfrun(){
    
    is_param_mode=0
    if [ $# -gt 0 ]; then
        is_param_mode=1
        for func in "$@"; do
            if declare -F "$func" >/dev/null 2>&1; then
                $func
            else
                _red "错误：函数 '$func' 不存在"
                exit 1
            fi
        done
        exit 0
    fi
    
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
