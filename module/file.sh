filefun() {
    beforeMenu(){
    _blue "> ---  当前目录: [ $(pwd) ] ---- < v:${branch}-$selfversion"
    echo
    _yellow "当前菜单: $menuname "
    echo
    }

    #查看当前路径文件夹
    catcurrentpathfolder(){
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
    }

    #压缩一个目录
    packagingdir(){
        #查看当前路径文件夹
        catcurrentpathfolder
        # 用户输入序号
        read -rp "请输入目录序号： " index

        # 检查序号合法性
        if [[ "$index" =~ ^[0-9]+$ ]] && (( index >= 1 && index <= ${#dirs[@]} )); then
            dirtmp=${dirs[$((index - 1))]}

            #打包后文件名
            filenametmp="$dirtmp.tar.gz"

            _blue '目录大小'
            du -sh $dirtmp

            # 确认
            read -rp "确认将 '$dirtmp' (包含子目录) 打包为 '$filenametmp' ? [y/N]: " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                tar -czf $filenametmp $dirtmp &
                loading $!
                wait
                _green "压缩完成"
            else
                echo "已取消操作。"
            fi
        else
            echo "无效的序号，请输入有效的数字。"
            return 1
        fi
    }
    #解压缩目录
    uncompresseddir(){
        #查看当前路径tar.gz
         echo
        # 获取当前路径下的所有 tar.gz 文件（不含隐藏文件）
        tar_files=($(ls *.tar.gz 2>/dev/null))
        if [[ ${#tar_files[@]} -eq 0 ]]; then
            echo "当前目录下没有 tar.gz 文件"
            return 1
        fi

        # 打印带序号的 tar.gz 文件列表
        _blue "序号\ttar.gz 文件名"
        for i in "${!tar_files[@]}"; do
            echo -e "$((i + 1))\t${tar_files[$i]}"
        done
        echo
        # 用户输入序号
        read -rp "请输入要解压的文件序号： " index

        # 检查序号合法性
        if [[ "$index" =~ ^[0-9]+$ ]] && (( index >= 1 && index <= ${#tar_files[@]} )); then
            # 获取选中的 tar.gz 文件
            selected_file="${tar_files[$((index - 1))]}"

            _blue "待解压文件信息"
            ls -lh "$selected_file"  # 显示文件大小和详情

            # 确认解压操作
            read -rp "确认解压 '$selected_file' 到当前目录吗？[y/N]: " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                # 执行解压命令（-xzf 为解压参数）
                tar -xzf "$selected_file" &
                loading $!  # 显示加载动画
                wait  # 等待解压完成
                _green "解压完成，文件已提取至当前目录"
            else
                echo "已取消解压操作。"
            fi
        else
            echo "无效的序号，请输入 1 到 ${#tar_files[@]} 之间的数字。"
            return 1
        fi
    }

    #配置目录权限www-data
    chownwwwdata() {
        #查看当前路径文件夹
        catcurrentpathfolder
        # 用户输入序号
        read -rp "请输入目录序号： " index

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

    #统计当前目录占用
    statisticsusage() {
        _blue '占用空间最多的前5文件夹'
        du -sh * | sort -rh | head -n 5
        _blue '占用空间最多的前5文件'
        find * -type f -exec du -ah {} + | sort -rh | head -n 5
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
    options=("打包压缩目录" packagingdir "解压缩目录" uncompresseddir  "配置目录权限www-data" chownwwwdata "统计当前目录占用" statisticsusage  "统计目录文件行数" countfileslines "多线程下载" aria2fun )

    menu "${options[@]}"

}