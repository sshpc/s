filefun() {
    beforeMenu(){
    _blue "> ---  当前目录: [ $(pwd) ] ---- < v:${branch}-$selfversion"
    echo
    _yellow "当前菜单: $menuname "
    echo
    }

    #配置目录权限www-data
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

    #多线程下载
    aria2fun() {
        #检查aria2是否已安装
        if _exists 'aria2c'; then
            _blue '安装aria2..'

            apt-get install aria2
        fi

        echo 'aria2c -s 2 -x 2 -c http://xxx/xxx'

    }

    #统计根目录占用
    statisticsusage() {
        _blue '占用空间最多的前10文件夹'
        du -sh /* | sort -rh | head -n 10
        _blue '占用空间最多的前50文件'
        find / -type f -not -path "/proc/*" -not -path "/sys/*" -exec du -ah {} + | sort -rh | head -n 50
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

    menuname='首页/文件管理'
    echo "filefun" >$installdir/config/lastfun
    options=("配置目录权限www-data" chownwwwdata "统计根目录占用" statisticsusage  "统计目录文件行数" countfileslines "多线程下载" aria2fun )

    menu "${options[@]}"

}