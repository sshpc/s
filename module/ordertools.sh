ordertoolsfun() {
    beforeMenu(){
    _blue "> ---  当前目录: [ $(pwd) ] ---- < v:${branch}-$selfversion"
    echo
    _yellow "当前菜单: $menuname "
    echo
    }

    
    #安装git便捷提交
    igitcommiteasy() {
        check_and_install git
        if  _exists 'sgit'; then
            _red '系统已存在sgit程序,停止安装,请检查!'
            exit
        else
            touch /bin/sgit
            chmod +x /bin/sgit
            echo 'git add . && git commit -m "`date +%y%m%d%H%M%S`" && git push' >/bin/sgit
            _blue '安装完成'
            echo
            echo '如卸载删掉/bin/sgit 即可'
            echo '现在使用sgit命令 完成git add commit +时间字符串 push 提交'
            echo
        fi
    }
    siegetest() {
        check_and_install siege
        read -rp "输入被测试的url:" -e url
        read -rp "输入并发数1-255: " -e -i 10 erupt
        read -rp "输入测试时间: " -e -i 10 time
        echo
        _yellow '-c 并发数 -t 时间 -b 禁用请求之间的延迟(暴力模式)'
        echo "siege -c $erupt -t $time $url"
        echo
        waitinput

        _blue '开始测试...'
        siege -c $erupt -t $time $url

    }
    

    #杀死vscode进程
    killvscode() {

        #仅杀掉占用最大的进程
        killtopvscode() {
            ps -uxa | grep '\.vscode-server' | sort -k3 -nr | head -n 1 | awk '{print $2}' | xargs kill -9
        }

        #杀死所有vscode进程
        killallvscode() {
            ps uxa | grep .vscode-server | awk '{print $2}' | xargs kill -9
        }
        menuname='首页/其他工具/杀死vscode进程'
        echo "ordertoolsfun" >$installdir/config/lastfun
        options=("仅杀掉占用最大的进程" killtopvscode "杀死所有vscode进程" killallvscode)
        menu "${options[@]}"
    }

    #清理 VS Code Server 目录
    clearvscodefun() {
        echo
        _blue "=== 清理 VS Code Server 目录 (.vscode-server) ==="
        echo "将扫描以下用户目录下的 .vscode-server："
        echo "  /root/.vscode-server"
        for home in /home/*/; do
            [[ -d "$home" ]] && echo "  $home.vscode-server"
        done
        echo
        read -rp "确认清理以上 .vscode-server 目录? [y/N]: " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            _yellow "已取消"
            return 1
        fi

        local total_freed=0
        local count=0

        # 清理 root 目录
        if [[ -d /root/.vscode-server ]]; then
            local sz=$(du -sb /root/.vscode-server 2>/dev/null | awk '{print $1}')
            rm -rf /root/.vscode-server
            total_freed=$((total_freed + sz))
            count=$((count + 1))
            _green "[已清理] /root/.vscode-server"
        fi

        # 清理所有普通用户目录
        for home in /home/*/; do
            local user_dir="${home%.vscode-server}"
            user_dir="${user_dir#/home/}"
            local target="${home}.vscode-server"
            if [[ -d "$target" ]]; then
                local sz=$(du -sb "$target" 2>/dev/null | awk '{print $1}')
                rm -rf "$target"
                total_freed=$((total_freed + sz))
                count=$((count + 1))
                _green "[已清理] $target"
            fi
        done

        if (( count > 0 )); then
            local freed_human
            if (( total_freed >= 1048576 )); then
                freed_human=$(awk "BEGIN {printf \"%.2f GB\", $total_freed/1048576}")
            elif (( total_freed >= 1024 )); then
                freed_human=$(awk "BEGIN {printf \"%.2f MB\", $total_freed/1024}")
            else
                freed_human="${total_freed} KB"
            fi
            _green "[OK] 共清理 $count 个 .vscode-server 目录，释放空间：$freed_human"
        else
            _yellow "未发现任何 .vscode-server 目录"
        fi
    }

    gitfilemodefalse(){
        git config --add core.filemode false
    }

    gitautocrlf(){
        git config --global core.autocrlf input
    }


    menuname='首页/其他工具'
    echo "ordertoolsfun" >$installdir/config/lastfun
    options=("安装git便捷提交" igitcommiteasy "git忽略文件权限改动" gitfilemodefalse "git自动处理换行符" gitautocrlf "杀死vscode进程" killvscode "清理VS Code Server目录" clearvscodefun "Siege-web压力测试" siegetest )
    menu "${options[@]}"
}
