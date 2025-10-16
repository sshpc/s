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

download_with_mirrors() {
    local filename="$1"
    local output="$2/$filename"
    local branch="$3"
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

# 升级自身脚本函数
updateself() {

    local tmpdir="$installdir/tmp"
    mkdir -p "$tmpdir"

    _blue "尝试下载最新版脚本和版本信息..."

    local s_file_ok=false
    local v_file_ok=false


    read -ep "是否下载dev版 (默认n): " yorndev
    if [[ "$yorndev" = "y" ]]; then

        if download_with_mirrors "s.sh" "$tmpdir" "main"; then
        _green "s.sh 下载成功"
        s_file_ok=true
    else
        _red "s.sh 下载失败"
    fi

    if download_with_mirrors "version" "$tmpdir" "main"; then
        _green "version 下载成功"
        v_file_ok=true
    else
        _yellow "version 下载失败"
    fi

    else  


    if download_with_mirrors "s.sh" "$tmpdir" "main"; then
        _green "s.sh 下载成功"
        s_file_ok=true
    else
        _red "s.sh 下载失败"
    fi

    if download_with_mirrors "version" "$tmpdir" "main"; then
        _green "version 下载成功"
        v_file_ok=true
    else
        _yellow "version 下载失败"
    fi

    fi

    if $s_file_ok && $v_file_ok; then
        _blue "验证通过，准备更新"

        # 拷贝到正式目录
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

    # 无论如何清理临时目录
    rm -rf "$tmpdir"
}



#异常终止函数
_exit() {
    if [ -e "./speedtest-cli/speedtest" ]; then
        rm -rf ./speedtest-cli
    fi
    #_red "\n exit. again run 's'\n"
    #exit 1

    local status=$1
    echo "$(date '+%F %T') [$$] EXIT with status $status" >&19
    exit $status
}
#异常终止执行函数
trap _exit INT QUIT TERM


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
