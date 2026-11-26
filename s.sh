#!/bin/bash
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
# UTF-8 locale 处理
_s_locale=""
for _l in en_US.UTF-8 zh_CN.UTF-8 C.UTF-8; do
    if locale -a 2>/dev/null | grep -qix "${_l%.UTF-8}.utf8"; then
        _s_locale="$_l"
        break
    fi
done
export LANG="${_s_locale:-C.UTF-8}"
export LC_ALL="${_s_locale:-C.UTF-8}"
unset _s_locale _l

menuname='主页'
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

# logo
slogo() {
    _green '# 交互式shell脚本工具'
    _green '# Author:SSHPC <https://github.com/sshpc>'
    echo
}

# 回首页
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
    
    tput civis
    
    while :; do
        completed=0
        for pid in "${pids[@]}"; do
            if ! kill -0 "$pid" 2>/dev/null; then
                ((completed++))
            fi
        done
        
        local percent=$((completed * 100 / total))
        local bar_length=$((percent / 2))
        local bar=$(printf '%-*s' "$bar_length" '' | tr ' ' '=')
        local empty=$(printf '%-*s' "$((50-bar_length))" '' | tr ' ' '.')
        
        local spinchar="${spinstr:$spinindex:1}"
        spinindex=$(( (spinindex + 1) % 4 ))
        printf "\r\033[0;31;36mloading[%c] [%-50s] %3d%% (%d/%d)\033[0m" "$spinchar" "$bar$empty" "$percent" "$completed" "$total"
        
        if [[ $completed -eq $total ]]; then
            break
        fi
        
        sleep "$delay"
    done
    
    tput cnorm
    printf "\n"
}

# 等待输入
waitinput() {
    echo
    read -n1 -r -p "按任意键继续...(退出 Ctrl+C)"
}

# 继续执行函数
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
    tput civis
    
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
    
    tput cnorm
    printf "\r\033[K"
}

# 检测命令是否存在
_exists() {
    local cmd="$1"
    which $cmd >/dev/null 2>&1
    local rt=$?
    return ${rt}
}

# s日志读写
slog() {
    local method=$1
    local file=$2
    local info=$3
    
    case $method in
        set)
            echo $info >>${installdir}/log/$file.log
        ;;
        get)
            tail -20 ${installdir}/log/$file.log
            
        ;;
        *)
            echo 'log error'
            
        ;;
    esac
    
}

# 通用安装函数
check_and_install() {
    
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

    for cmd in "$@"; do

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



_DL_TIMEOUT="${_DL_TIMEOUT:-4}"
_DL_ROUNDS="${_DL_ROUNDS:-2}"
_DL_PIDS=()
_DL_COLOR=0        
_DL_DREW=0         
_DL_WGET_PID=''    

_DL_ABORT_FILE="${TMPDIR:-/tmp}/.s-dl-abort.$$"
rm -f "$_DL_ABORT_FILE" 2>/dev/null
for _dl_stale in "${TMPDIR:-/tmp}"/.s-dl-abort.*; do
    [[ -e "$_dl_stale" ]] || continue
    _dl_sp="${_dl_stale##*.}"
    [[ "$_dl_sp" =~ ^[0-9]+$ ]] && ! kill -0 "$_dl_sp" 2>/dev/null && rm -f "$_dl_stale" 2>/dev/null
done
unset _dl_stale _dl_sp

declare -A _DL_SIZECACHE=()

_dl_cols() {
    local c
    c=$(tput cols 2>/dev/null)
    [[ "$c" =~ ^[0-9]+$ ]] || c=80
    (( c < 40 )) && c=40
    printf '%s' "$c"
}

_dl_human_to() {
    local __out="$1" n="${2:-0}"
    [[ "$n" =~ ^[0-9]+$ ]] || n=0
    if (( n >= 1073741824 )); then
        printf -v "$__out" '%d.%dG' $(( n / 1073741824 )) $(( (n % 1073741824) * 10 / 1073741824 ))
    elif (( n >= 1048576 )); then
        printf -v "$__out" '%d.%dM' $(( n / 1048576 )) $(( (n % 1048576) * 10 / 1048576 ))
    elif (( n >= 1024 )); then
        printf -v "$__out" '%d.%dK' $(( n / 1024 )) $(( (n % 1024) * 10 / 1024 ))
    else
        printf -v "$__out" '%dB' "$n"
    fi
}

_dl_host() {
    local u="$1"
    u="${u#http://}"
    u="${u#https://}"
    printf '%s' "${u%%/*}"
}

_dl_log() {
    local f="${installdir}/log/download.log"
    [[ -d "${installdir}/log" ]] || return 0
    printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$f" 2>/dev/null
}

_dl_aborted() {
    [[ -n "$_DL_ABORT_FILE" && -e "$_DL_ABORT_FILE" ]]
}

_dl_status() {
    local sf="$1"
    shift
    [[ -n "$sf" && -d "${sf%/*}" ]] || return 0
    { printf '%s\n' "$*" > "${sf}.tmp" && mv -f "${sf}.tmp" "$sf"; } 2>/dev/null
    return 0
}

_dl_remote_size() {
    local url="$1" size=0
    if [[ -n "${_DL_SIZECACHE[$url]+x}" ]]; then
        printf '%s' "${_DL_SIZECACHE[$url]}"
        return 0
    fi
    if command -v curl >/dev/null 2>&1; then
        size=$(curl -sIL --max-time 3 "$url" 2>/dev/null |
            awk 'tolower($0) ~ /^content-length:/ {v = $2} END {gsub(/\r/, "", v); print v + 0}')
    fi
    if [[ ! "$size" =~ ^[0-9]+$ ]] || (( size == 0 )); then
        if command -v wget >/dev/null 2>&1; then
            size=$(wget --spider -S --timeout=3 --tries=1 -q "$url" 2>&1 |
                awk 'tolower($0) ~ /content-length:/ {v = $2} END {gsub(/\r/, "", v); print v + 0}')
        fi
    fi
    [[ "$size" =~ ^[0-9]+$ ]] || size=0
    _DL_SIZECACHE[$url]="$size"
    printf '%s' "$size"
}

_dl_bar_to() {
    local __out="$1" pct="$2" w="$3" fill _bar _rest
    if (( pct < 0 )); then
        printf -v _bar '%*s' "$w" ''
        printf -v "$__out" '%s' "${_bar// /.}"
        return 0
    fi
    fill=$(( pct * w / 100 ))
    (( fill > w )) && fill=$w
    if (( fill >= w )); then
        printf -v _bar '%*s' "$w" ''
        printf -v "$__out" '%s' "${_bar// /=}"
        return 0
    fi
    (( fill > 0 )) && fill=$(( fill - 1 ))
    printf -v _bar '%*s' "$fill" ''
    printf -v _rest '%*s' "$(( w - fill - 1 ))" ''
    printf -v "$__out" '%s>%s' "${_bar// /=}" "$_rest"
}

_dl_bar() {
    local _b
    _dl_bar_to _b "$1" "$2"
    printf '%s' "$_b"
}

_dl_line_to() {
    local __out="$1" sf="$2" spin="$3" barw="$4" width="${5:-0}"
    local name='?' state=wait size=0 total=0 source='-' round=0
    if [[ -r "$sf" ]]; then
        read -r name state size total source round < "$sf" 2>/dev/null
    fi
    [[ "$size" =~ ^[0-9]+$ ]] || size=0
    [[ "$total" =~ ^[0-9]+$ ]] || total=0

    local icon color=36 pct=-1
    case "$state" in
        ok)    icon='+' ; color=32 ;;
        fail)  icon='x' ; color=31 ;;
        retry) icon='~' ; color=33 ;;
        run)   icon="$spin" ;;
        *)     icon=' ' ; color=90 ;;
    esac
    (( total > 0 )) && pct=$(( size * 100 / total ))
    (( pct > 100 )) && pct=100

    local bar human_cur human_tot pctxt src plain pad spaces=''
    _dl_bar_to bar "$pct" "$barw"
    _dl_human_to human_cur "$size"
    _dl_human_to human_tot "$total"
    if (( total <= 0 )); then
        pctxt='--'
    elif (( pct < 0 )); then
        pctxt='  -'
    else
        pctxt="$pct"
    fi
    src="${source:0:12}"
    (( round > 1 )) && src="r${round}:${src}"
    src="${src:0:12}"
    [[ -z "$name" || "$name" == '?' ]] && name='(待开始)'

    printf -v plain '%s %-20.20s [%s] %3s%% %6s/%-6s %s' \
        "$icon" "$name" "$bar" "$pctxt" "$human_cur" "$human_tot" "$src"
    if (( width > 0 )); then
        pad=$(( width - ${#plain} ))
        if (( pad > 0 )); then
            printf -v spaces '%*s' "$pad" ''
            plain+="$spaces"
        fi
    fi

    if (( _DL_COLOR )); then
        printf -v "$__out" '\033[0;%sm%s\033[0m %-20.20s [\033[0;36m%s\033[0m] %3s%% %6s/%-6s \033[90m%s\033[0m%s' \
            "$color" "$icon" "$name" "$bar" "$pctxt" "$human_cur" "$human_tot" "$src" "$spaces"
    else
        printf -v "$__out" '%s' "$plain"
    fi
}

_dl_line() {
    local _l
    _dl_line_to _l "$1" "$2" "$3"
    printf '%s' "$_l"
}

_dl_state_to() {
    local __out="$1" st='wait'
    if [[ -r "$2" ]]; then
        read -r _ st _ < "$2" 2>/dev/null
    fi
    printf -v "$__out" '%s' "$st"
}

_dl_state() {
    local _s
    _dl_state_to _s "$1"
    printf '%s' "$_s"
}

_dl_watch() {
    local -a sfs=("$@")
    local n=${#sfs[@]}
    local tty=0
    [ -t 1 ] && tty=1
    local cols rows barw linew
    cols=$(_dl_cols)
    rows=$(tput lines 2>/dev/null)
    [[ "$rows" =~ ^[0-9]+$ ]] || rows=24
    (( rows < 8 )) && rows=8
    barw=$(( cols - 59 ))
    (( barw > 24 )) && barw=24
    (( barw < 8 )) && barw=8
    linew=$(( cols - 1 ))          
    (( cols < 60 )) && tty=0       
    (( n > rows - 2 )) && tty=0    

    local spinstr='|/-\' si=0 i drawn=0 ndone=0 state alive
    local ch frame ln
    local -a prev=()

    (( tty )) && { printf '\033[?25l'; _DL_COLOR=1; _DL_DREW=1; }    

    while :; do
        ndone=0
        alive=0
        for (( i = 0; i < n; i++ )); do
            _dl_state_to state "${sfs[$i]}"
            if [[ "$state" == ok || "$state" == fail ]]; then
                ndone=$(( ndone + 1 ))
            fi
            if [ ${#_DL_PIDS[@]} -gt 0 ] && kill -0 "${_DL_PIDS[$i]}" 2>/dev/null; then
                alive=$(( alive + 1 ))
            fi
        done
        if (( tty )); then
            ch="${spinstr:si:1}"
            si=$(( (si + 1) % 4 ))
            frame=''
            (( drawn > 0 && n > 1 )) && frame+=$'\033['"$(( n - 1 ))"'A'
            for (( i = 0; i < n; i++ )); do
                frame+=$'\r'
                _dl_line_to ln "${sfs[$i]}" "$ch" "$barw" "$linew"
                if [[ "${prev[$i]:-}" != "$ln" ]]; then
                    prev[$i]="$ln"
                    frame+="$ln"
                fi
                (( i < n - 1 )) && frame+=$'\n'
            done
            printf '%s' "$frame"
            drawn=$n
        fi

        if _dl_aborted; then
            break
        fi
        (( ndone >= n )) && break
        (( alive == 0 )) && break
        sleep 0.2
    done

    if _dl_aborted; then
        if (( tty )); then
            _DL_COLOR=0
            printf '\033[?25h'
        fi
        return 0
    fi

    if (( tty )); then
        frame=''
        (( drawn > 0 && n > 1 )) && frame+=$'\033['"$(( n - 1 ))"'A'
        for (( i = 0; i < n; i++ )); do
            frame+=$'\r'
            _dl_line_to ln "${sfs[$i]}" '+' "$barw" "$linew"
            if [[ "${prev[$i]:-}" != "$ln" ]]; then
                prev[$i]="$ln"
                frame+="$ln"
            fi
            (( i < n - 1 )) && frame+=$'\n'
        done
        frame+=$'\n'
        _DL_COLOR=0
        printf '%s\033[?25h' "$frame"
    fi
    return 0
}

# 文件当前大小（不存在算 0）
_dl_filesize() {
    local f="$1" sz
    if [[ -n "$f" && -f "$f" ]]; then
        sz=$(stat -c %s "$f" 2>/dev/null)
    else
        sz=0
    fi
    [[ "$sz" =~ ^[0-9]+$ ]] || sz=0
    printf '%s' "$sz"
}

# 单源拉取：wget 后台跑 + 轮询文件大小上报进度
_dl_fetch() {
    local url="$1" output="$2" sf="$3" filename="$4" total="$5" source="$6" round="$7" timeout="$8"
    local pid rc size
    _dl_aborted && return 1
    rm -f "$output" 2>/dev/null
    wget -q --timeout="$timeout" --tries=1 -O "$output" "$url" >/dev/null 2>&1 &
    pid=$!
    _DL_WGET_PID=$pid
    while kill -0 "$pid" 2>/dev/null; do
        if _dl_aborted || [[ ! -d "${sf%/*}" ]]; then
            kill -9 "$pid" 2>/dev/null
            wait "$pid" 2>/dev/null
            _DL_WGET_PID=''
            return 1
        fi
        size=$(_dl_filesize "$output")
        _dl_status "$sf" "$filename" run "$size" "$total" "$source" "$round"
        sleep 0.15
    done
    wait "$pid" 2>/dev/null
    rc=$?
    _DL_WGET_PID=''
    size=$(_dl_filesize "$output")

    if (( rc == 0 && size > 0 )); then
        (( total > 0 )) || total=$size
        _dl_status "$sf" "$filename" ok "$size" "$total" "$source" "$round"
        _dl_log "OK   round=$round src=$source file=$filename size=$size"
        return 0
    fi
    _dl_log "FAIL round=$round src=$source file=$filename"
    return 1
}

# 单个文件的完整下载流程：多来源 × 多轮
_dl_job() {
    local filename="$1" output="$2" sf="$3"
    local base url total source round
    local -a bases=("${proxylinks[@]}")

    mkdir -p "$(dirname "$output")" 2>/dev/null
    _dl_status "$sf" "$filename" wait 0 0 '-' 0

    for (( round = 1; round <= _DL_ROUNDS; round++ )); do
        for base in "${bases[@]}"; do
            _dl_aborted && return 1
            source=$(_dl_host "$base")
            url="${base}/sshpc/s/main/${filename}"
            total=$(_dl_remote_size "$url")
            _dl_status "$sf" "$filename" run 0 "$total" "$source" "$round"
            if _dl_fetch "$url" "$output" "$sf" "$filename" "$total" "$source" "$round" "$_DL_TIMEOUT"; then
                return 0
            fi
            _dl_aborted && return 1
            rm -f "$output" 2>/dev/null
            _dl_status "$sf" "$filename" retry 0 "$total" "$source" "$round"
        done
    done

    _dl_status "$sf" "$filename" fail 0 0 '-' "$_DL_ROUNDS"
    return 1
}

# 下载单个文件（串行，自己一行进度）
download_file() {
    local filename="$1"
    local output="$2"
    [[ -n "$filename" && -n "$output" ]] || return 1

    local dir="${installdir}/tmp/dldash"
    mkdir -p "$dir" 2>/dev/null
    local sf="$dir/single.$$.${RANDOM}"
    : > "$sf" 2>/dev/null

    _dl_job "$filename" "$output" "$sf" &
    local pid=$!

    _DL_DREW=0
    if [ -t 1 ] && [[ -z "$_DL_NOPROGRESS" ]]; then
        _DL_PIDS=("$pid")
        _dl_watch "$sf"
    fi

    wait "$pid" 2>/dev/null
    local rc=$?
    if (( ! _DL_DREW )) && [[ -z "$_DL_NOPROGRESS" ]] && ! _dl_aborted; then
        _dl_line "$sf" '-' 20
        printf '\n'
    fi
    rm -f "$sf" 2>/dev/null
    return $rc
}

# 并发下载多个文件：每个文件一行，进度同时刷新（docker pull 风格）
download_batch() {
    local -a names=("$@")
    local n=${#names[@]}
    (( n > 0 )) || return 0

    local dir="${installdir}/tmp/dldash"
    rm -rf "$dir" 2>/dev/null
    mkdir -p "$dir" 2>/dev/null
    dir="${dir}/b$$.${RANDOM}"
    mkdir -p "$dir" 2>/dev/null

    local -a sfs=() pids=()
    local i=0 name sf outdir="${_DL_OUTDIR:-$installdir}"
    for name in "${names[@]}"; do
        i=$(( i + 1 ))
        sf="$dir/j$i"
        : > "$sf" 2>/dev/null
        _dl_job "$name" "${outdir}/${name}" "$sf" &
        pids+=($!)
        sfs+=("$sf")
    done

    _DL_PIDS=("${pids[@]}")
    _DL_DREW=0
    _dl_watch "${sfs[@]}"

    local rc=0 state
    for (( i = 0; i < n; i++ )); do
        wait "${pids[$i]}" 2>/dev/null || rc=1
    done
    for (( i = 0; i < n; i++ )); do
        state=$(_dl_state "${sfs[$i]}")
        [[ "$state" == "ok" ]] || rc=1
    done

    if (( ! _DL_DREW )) && ! _dl_aborted; then
        for (( i = 0; i < n; i++ )); do
            _dl_line "${sfs[$i]}" '-' 20
            printf '\n'
        done
    fi

    rm -rf "$dir" 2>/dev/null
    return $rc
}

# 后台下载（调用方自己 pids+=($!)）
download_file_bg() {
    local filename="$1"
    local output="${2:-$installdir/$filename}"
    download_file "$filename" "$output" &
}

# 解析ini
get_ini_value() {
    local section="$1"
    local key="$2"
    local file="$3"
    
    
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
        m=$(echo "$m" | tr -d '\r\n\t')
        [[ -z "$m" ]] && continue
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

    
    if [[ ${#to_download[@]} -gt 0 ]]; then
        local -a files=()
        for m in "${to_download[@]}"; do
            [[ -f "$installdir/module/${m}.sh" ]] && continue
            files+=("module/${m}.sh")
        done
        if [[ ${#files[@]} -gt 0 ]]; then
            _yellow "模块下载中"
            download_batch "${files[@]}" || _red "部分模块下载失败，可用 安装模块 重试"
        else
            _green "模块均已存在"
        fi
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

# 菜单渲染

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

# 重启脚本
selfrestart(){
    echo
    _green '保持配置..'
    sleep 0.5
    _yellow '重启脚本..'
    echo
    sleep 1
    exec s
}

# 脚本设置
selfsetting(){
    
    # 移除脚本
    removeself() {
        [[ -n "${installdir:-}" && -d "$installdir" ]] || { _red "安装目录无效，已中止"; return 1; }
        rm -rf -- "${installdir:?}/core"/* 2>/dev/null
        rm -rf -- "${installdir:?}/config"/*
        rm -rf -- "${installdir:?}/module"/*
        rm -rf -- "${installdir:?}/version"
        rm -rf -- "${installdir:?}/modules.conf"
    }
    
    # 卸载脚本
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
            [[ -n "${installdir:-}" && "$installdir" != "/" ]] && rm -rf -- "${installdir:?}" /bin/s
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

        local stage="$installdir/tmp/upd"
        rm -rf "$stage"
        mkdir -p "$stage/module"

        _blue "尝试下载最新版脚本和版本信息..."
        local ok=0
        local -a core=("s.sh" "version" "modules.conf")

        _DL_OUTDIR="$stage"
        if download_batch "${core[@]}"; then
            _green "脚本与配置下载成功"
        else
            _red "脚本或配置下载失败"
            ok=1
        fi

        if [[ $ok -eq 0 ]]; then
            local m
            local -a mods=()
            for m in $(list_all_modules_from_conf "$stage/modules.conf"); do
                m=$(echo "$m" | tr -d '\r\n\t')
                [[ -z "$m" ]] && continue
                mods+=("module/${m}.sh")
            done
            if [[ ${#mods[@]} -gt 0 ]]; then
                download_batch "${mods[@]}" || ok=1
            fi
            _DL_OUTDIR=""
        fi

        if [[ $ok -ne 0 ]]; then
            _red "下载未全部成功，已保留当前版本 v$selfversion，未做任何替换"
            rm -rf "$stage"
            return 1
        fi

        _blue "校验下载内容..."
        local f
        local files=("$stage/s.sh")
        for f in "$stage"/module/*.sh; do
            [[ -f "$f" ]] && files+=("$f")
        done
        for f in "${files[@]}"; do
            if [[ ! -s "$f" ]]; then
                _red "校验失败：$f 为空"
                rm -rf "$stage"
                return 1
            fi
            if ! bash -n "$f" 2>/dev/null; then
                _red "校验失败：$f 语法错误（可能下载到了错误页面）"
                rm -rf "$stage"
                return 1
            fi
        done
        if ! grep -qE '^[0-9]+\.[0-9]+(\.[0-9]+)*$' "$stage/version"; then
            _red "校验失败：version 内容不合法 ($(head -c 40 "$stage/version" 2>/dev/null))"
            rm -rf "$stage"
            return 1
        fi
        _green "校验通过"

        local new_ver
        new_ver=$(tr -d '\r\n\t ' <"$stage/version")

        _blue "备份当前版本 v$selfversion ..."
        backup_current_version

        _blue "安装新版本 v$new_ver ..."
        cp -f "$stage/s.sh" "$installdir/s.sh"
        chmod +x "$installdir/s.sh"
        cp -f "$stage/version" "$installdir/version"
        cp -f "$stage/modules.conf" "$installdir/modules.conf"

        mkdir -p "$installdir/module"
        for f in "$stage"/module/*.sh; do
            [[ -f "$f" ]] || continue
            mv -f "$f" "$installdir/module/"
        done

        local keep m2 fname
        for f in "$installdir/module"/*.sh; do
            [[ -f "$f" ]] || continue
            fname=$(basename "$f" .sh)
            keep=0
            for m2 in $(list_all_modules_from_conf "$installdir/modules.conf"); do
                m2=$(echo "$m2" | tr -d '\r\n\t')
                if [[ "$m2" == "$fname" ]]; then
                    keep=1
                    break
                fi
            done
            [[ $keep -eq 0 ]] && rm -f "$f"
        done

        slog set install "$datevar  | 脚本升级 | v$selfversion -> v$new_ver"
        cleanup_old_backups 5
        rm -rf "$stage"

        _green "升级完成 v$selfversion -> v$new_ver"
        exec "$installdir/s.sh"
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

# 菜单顶部内容
beforeMenu(){
    _blue "> ---  当前目录: [ $(pwd) ] ---- < v:$selfversion [$menustyle]"
    echo
    _yellow "当前菜单: $menuname "
    echo
}
# 主函数
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

# 脚本初始化
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
    
    if [[ -f "$installdir/config/menustyle" ]] && grep -q '^staticmenu$' "$installdir/config/menustyle"; then
        menustyle='staticmenu'
    else
        menustyle='menu'
    fi
    
    local original_url="http://raw.githubusercontent.com"
    proxylinks=("$original_url")
    for host in "${proxyhost[@]}"; do
        proxylinks+=("${host}/${original_url}")
    done
}

# 加载文件
loadfilefun() {
    
    shfiles=(
        'version'
        'modules.conf'
    )
    
    local -a missing=()
    for shfile in "${shfiles[@]}"; do
        [[ -s "$installdir/$shfile" ]] || missing+=("$shfile")
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo
        _yellow '核心文件下载'
        download_batch "${missing[@]}" || _red '核心文件下载失败，请检查网络后重跑'
        wait
    fi
    
    if [[ -z "$(ls -A $installdir/module 2>/dev/null)" ]] && [[ -s "$installdir/modules.conf" ]]; then
        echo
        modules_install
    fi
    
    for mfile in "$installdir/module"/*.sh; do
        [[ -f "$mfile" ]] && source "$mfile"
    done
}

# 终止和日志函数
exceptionfun(){
    _exit() {
        printf '\033[?25h' 2>/dev/null
        [[ -n "$_DL_ABORT_FILE" ]] && : > "$_DL_ABORT_FILE" 2>/dev/null
        if [ -e "./speedtest-cli/speedtest" ]; then
            rm -rf ./speedtest-cli
        fi
        [[ -d "$installdir/tmp" ]] && rm -rf -- "${installdir:?}/tmp"
        if [[ -n "$_DL_ABORT_FILE" ]]; then
            ( sleep 3; rm -f "$_DL_ABORT_FILE" ) >/dev/null 2>&1 &
        fi
        exit 1
    }
    trap _exit INT QUIT TERM
    
    if [[ -f "$installdir/config/exception" ]] && grep -q '^open$' "$installdir/config/exception"; then
        LOGFILE="${installdir}/log/runscript.log"
        
        exec 19>>"$LOGFILE"
        set -T
        
        CMD_WHITELIST=("sleep" "clear" "tr" "wc" "cat" "awk" "sort" "sed"
                       "stat" "wget" "curl" "tput" "mv" "rm" "mkdir" "date")
        
        in_whitelist() {
            local c="$1"
            local w
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
            
            if in_whitelist "$cmd"; then
                return 0
            fi
            
            if [ "$(type -t "$cmd" 2>/dev/null)" = "file" ]; then
                local log_time=$(date '+%F %T')
                printf "%s [%d] %s\n" "$log_time" "$$" "$BASH_COMMAND" >&19
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
            _DL_NOPROGRESS=1
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

# 脚本运行
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
selfrun "$@"
