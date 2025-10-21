ordertoolsfun() {
    beforeMenu(){
    _blue "> ---  当前目录: [ $(pwd) ] ---- < v:${branch}-$selfversion"
    echo
    _yellow "当前菜单: $menuname "
    echo
    }

    #统计根目录占用
    statisticsusage() {
        _blue '占用空间最多的前10文件夹'
        du -sh /* | sort -rh | head -n 10
        _blue '占用空间最多的前50文件'
        find / -type f -not -path "/proc/*" -not -path "/sys/*" -exec du -ah {} + | sort -rh | head -n 50
    }
    #多线程下载
    aria2fun() {
        #检查aria2是否已安装
        if _exists 'aria2c'; then
            _blue '安装aria2..'

            apt-get install aria2
        fi

        echo 'aria2c -s 2 -x 2 -c http://xxx/xxx'

    }

    #统计目录文件行数
    countfileslines() {
        echo
        _yellow '目前仅支持单一文件后缀搜索!'
        read -ep "请输入绝对路径 ./(默认当前目录) /.../..  : " abpath
        if [[ "$abpath" = "" ]]; then
            abpath='./'
        fi
        read -ep "请输入要搜索的文件后缀: sh(默认) php  html ...  : " suffix
        if [[ "$suffix" = "" ]]; then
            suffix='sh'
        fi
        # 使用 find 命令递归地查找指定目录下的所有文件,并执行计算行数的命令
        total=$(find $abpath -type f -name "*.$suffix" -exec wc -l {} \; | awk '{total += $1} END{print total}')
        # 输出总行数
        echo "$abpath 目录下的 后缀为 $suffix 文件的总行数是: $total"
    }
    #安装git便捷提交
    igitcommiteasy() {
        _yellow '检查系统环境..'
        if ! command -v git &>/dev/null; then
            echo "Git没有安装"
            _blue "Git is already installed"
        elif _exists 'sgit'; then
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
        apt install siege -y
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
    hping3fun() {
        wget -N http://raw.githubusercontent.com/sshpc/trident/main/run.sh && chmod +x run.sh && sudo ./run.sh

    }

    Fillupownmemory() {
        #!/bin/bash

        # 检查系统是否安装了 Python
        if ! command -v python3 &>/dev/null; then
            echo "Python 3 未安装，请先安装 Python 3 再运行此脚本。"
            apt install python3 -y
        fi

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

    IntegratedFunctionScript() {
        lionfun() {
            curl -sS -O https://kejilion.pro/kejilion.sh && chmod +x kejilion.sh && ./kejilion.sh
        }
        SKY-BOXfun() {
            wget -O box.sh https://raw.githubusercontent.com/BlueSkyXN/SKY-BOX/main/box.sh && chmod +x box.sh && clear && ./box.sh
        }

        menuname='首页/其他工具/综合功能脚本'

        options=("科技lion" lionfun "SKY-BOX" SKY-BOXfun)
        menu "${options[@]}"

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

        chownwwwdata() {
        echo
        # 获取当前路径下的所有目录（不含隐藏目录）
        dirs=($(ls -d */ 2>/dev/null | sed 's#/##'))
        if [[ ${#dirs[@]} -eq 0 ]]; then
            echo "当前目录下没有可用目录"
            return 1
        fi

        # 打印带序号的目录列表
        _blue "序号\t目录名"
        for i in "${!dirs[@]}"; do
            echo -e "$((i + 1))\t${dirs[$i]}"
        done
        echo

        # 用户输入序号
        read -rp "请输入目录序号（从 1 开始）： " index

        # 检查序号合法性
        if [[ "$index" =~ ^[0-9]+$ ]] && (( index >= 1 && index <= ${#dirs[@]} )); then
            dirtmp=${dirs[$((index - 1))]}

            # 确认
            read -rp "确认将 '$dirtmp' (包含子目录) 权限修改为 www-data? [y/N]: " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                chown -R www-data:www-data "$dirtmp"
                echo
                ls -ld "$dirtmp"
                _blue '权限修改完成'
            else
                echo "已取消操作。"
            fi
        else
            echo "无效的序号，请输入有效的数字。"
            return 1
        fi
    }


    menuname='首页/其他工具'
    echo "ordertoolsfun" >$installdir/config/lastfun
    options=("配置目录权限www-data" chownwwwdata "统计根目录占用" statisticsusage "多线程下载" aria2fun "统计目录文件行数" countfileslines "安装git便捷提交" igitcommiteasy "杀死vscode进程" killvscode "Siege-web压力测试" siegetest "hping3-DDOS" hping3fun "打满自身内存" Fillupownmemory "综合功能脚本" IntegratedFunctionScript)
    menu "${options[@]}"
}
