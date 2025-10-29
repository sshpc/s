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
    

    Fillupownmemory() {
        #!/bin/bash

        check_and_install python3

        # 定义 Python 代码块
        python_code=$(
            cat <<EOF
import sys

big_list = []
while True:
    big_list.append('a' * 1024 * 1024)
    print(f"当前列表元素数量: {len(big_list)}, 已使用内存: {sys.getsizeof(big_list)} 字节", end='\r')

EOF
        )

        # 运行 Python 代码
        python3 -c "$python_code"
        trap 'echo "停止填充内存。"; exit' INT

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

    gitfilemodefalse(){
        git config --add core.filemode false
    }


    menuname='首页/其他工具'
    echo "ordertoolsfun" >$installdir/config/lastfun
    options=("安装git便捷提交" igitcommiteasy "git忽略文件权限改动" gitfilemodefalse "杀死vscode进程" killvscode "Siege-web压力测试" siegetest  "打满自身内存" Fillupownmemory )
    menu "${options[@]}"
}
