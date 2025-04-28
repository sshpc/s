#异常终止执行函数
trap _exit INT QUIT TERM

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

#检测命令是否存在
_exists() {
    local cmd="$1"
    which $cmd >/dev/null 2>&1
    local rt=$?
    return ${rt}
}

#卸载脚本
removeself() {
    _red '确定移除所有内容?'
    waitinput
    #写入日志
    slog set install "$datevar  | 脚本卸载 | v$selfversion"
    rm -rf $installdir/core/*
    rm -rf $installdir/config/*
    rm -rf $installdir/module/*
    rm -rf $installdir/version
    #rm -rf /bin/s

    read -ep "是否删除配置&日志 (默认n): " yorn
    if [[ "$yorn" = "y" ]]; then
        rm -rf $installdir
    fi
    
    _blue '卸载完成'
    echo
}
#脚本升级
updateself() {

    _blue '下载最新版'
    wget -N http://raw.githubusercontent.com/sshpc/s/main/s.sh -O "$installdir/s.sh"
    # 检查上一条命令的退出状态码
    if [ $? -eq 0 ]; then
        _blue '卸载旧版...'
        removeself
        #写入日志
        slog set install "$datevar  | 脚本升级"
        wget -N http://raw.githubusercontent.com/sshpc/s/main/version -O "$installdir/version"
        chmod +x "$installdir/s.sh"
        s

    else
        _red "下载失败,请重试"
    fi

}

#异常终止函数
_exit() {
    if [ -e "./speedtest-cli/speedtest" ]; then
        rm -rf ./speedtest-cli
    fi
    #_red "\n exit. again run 's'\n"
    exit 1
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


