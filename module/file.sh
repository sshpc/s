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

    #压缩目录为 tar.gz
    packagingdir_targz(){
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
    #解压 tar.gz 目录
    uncompresseddir_targz(){
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

    #压缩目录为 zip
    packagingdir_zip(){
        #查看当前路径文件夹
        catcurrentpathfolder
        # 用户输入序号
        read -rp "请输入目录序号： " index

        # 检查序号合法性
        if [[ "$index" =~ ^[0-9]+$ ]] && (( index >= 1 && index <= ${#dirs[@]} )); then
            dirtmp=${dirs[$((index - 1))]}

            #打包后文件名
            filenametmp="$dirtmp.zip"

            _blue '目录大小'
            du -sh $dirtmp

            # 确认
            read -rp "确认将 '$dirtmp' (包含子目录) 打包为 '$filenametmp' ? [y/N]: " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                check_and_install zip
                zip -r "$filenametmp" "$dirtmp" &
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

    #解压 zip 目录
    uncompresseddir_zip(){
        #查看当前路径zip
         echo
        # 获取当前路径下的所有 zip 文件（不含隐藏文件）
        zip_files=($(ls *.zip 2>/dev/null))
        if [[ ${#zip_files[@]} -eq 0 ]]; then
            echo "当前目录下没有 zip 文件"
            return 1
        fi

        # 打印带序号的 zip 文件列表
        _blue "序号\tzip 文件名"
        for i in "${!zip_files[@]}"; do
            echo -e "$((i + 1))\t${zip_files[$i]}"
        done
        echo
        # 用户输入序号
        read -rp "请输入要解压的文件序号： " index

        # 检查序号合法性
        if [[ "$index" =~ ^[0-9]+$ ]] && (( index >= 1 && index <= ${#zip_files[@]} )); then
            # 获取选中的 zip 文件
            selected_file="${zip_files[$((index - 1))]}"

            _blue "待解压文件信息"
            ls -lh "$selected_file"  # 显示文件大小和详情

            # 确认解压操作
            read -rp "确认解压 '$selected_file' 到当前目录吗？[y/N]: " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                # 执行解压命令
                check_and_install unzip
                unzip -o "$selected_file" &
                loading $!  # 显示加载动画
                wait  # 等待解压完成
                _green "解压完成，文件已提取至当前目录"
            else
                echo "已取消解压操作。"
            fi
        else
            echo "无效的序号，请输入 1 到 ${#zip_files[@]} 之间的数字。"
            return 1
        fi
    }

    #压缩目录为 rar
    packagingdir_rar(){
        #查看当前路径文件夹
        catcurrentpathfolder
        # 用户输入序号
        read -rp "请输入目录序号： " index

        # 检查序号合法性
        if [[ "$index" =~ ^[0-9]+$ ]] && (( index >= 1 && index <= ${#dirs[@]} )); then
            dirtmp=${dirs[$((index - 1))]}

            #打包后文件名
            filenametmp="$dirtmp.rar"

            _blue '目录大小'
            du -sh $dirtmp

            # 确认
            read -rp "确认将 '$dirtmp' (包含子目录) 打包为 '$filenametmp' ? [y/N]: " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                check_and_install rar
                rar a -r "$filenametmp" "$dirtmp" &
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

    #解压 rar 目录
    uncompresseddir_rar(){
        #查看当前路径rar
         echo
        # 获取当前路径下的所有 rar 文件（不含隐藏文件）
        rar_files=($(ls *.rar 2>/dev/null))
        if [[ ${#rar_files[@]} -eq 0 ]]; then
            echo "当前目录下没有 rar 文件"
            return 1
        fi

        # 打印带序号的 rar 文件列表
        _blue "序号\trar 文件名"
        for i in "${!rar_files[@]}"; do
            echo -e "$((i + 1))\t${rar_files[$i]}"
        done
        echo
        # 用户输入序号
        read -rp "请输入要解压的文件序号： " index

        # 检查序号合法性
        if [[ "$index" =~ ^[0-9]+$ ]] && (( index >= 1 && index <= ${#rar_files[@]} )); then
            # 获取选中的 rar 文件
            selected_file="${rar_files[$((index - 1))]}"

            _blue "待解压文件信息"
            ls -lh "$selected_file"  # 显示文件大小和详情

            # 确认解压操作
            read -rp "确认解压 '$selected_file' 到当前目录吗？[y/N]: " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                # 执行解压命令 - 优先使用 unrar，其次 unrar-free，最后 7z
                if command -v unrar &>/dev/null; then
                    unrar x "$selected_file" &
                elif command -v unrar-free &>/dev/null; then
                    unrar-free -x "$selected_file" &
                elif command -v 7z &>/dev/null; then
                    7z x -y "$selected_file" &
                else
                    check_and_install unrar
                    if command -v unrar &>/dev/null; then
                        unrar x "$selected_file" &
                    elif command -v 7z &>/dev/null; then
                        7z x -y "$selected_file" &
                    else
                        _red "未找到可用的 rar 解压工具 (unrar, unrar-free, 7z)，请手动安装"
                        return 1
                    fi
                fi
                loading $!  # 显示加载动画
                wait  # 等待解压完成
                _green "解压完成，文件已提取至当前目录"
            else
                echo "已取消解压操作。"
            fi
        else
            echo "无效的序号，请输入 1 到 ${#rar_files[@]} 之间的数字。"
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
        check_and_install aria2
        echo 'aria2c -s 2 -x 2 -c http://xxx/xxx'
    }

    #SMB 连接浏览与下载
    smbfun() {
        #检查smbclient是否已安装
        if ! command -v smbclient &>/dev/null; then
            check_and_install smbclient
        fi
        if ! command -v smbclient &>/dev/null; then
            check_and_install samba-client
        fi
        if ! command -v smbclient &>/dev/null; then
            _red "smbclient 不可用，请手动安装 samba-client 后重试"
            return 1
        fi

        echo
        _blue "SMB 地址格式: \\\\主机 或 \\\\主机\\\\共享名"
        read -ep "请输入 SMB 地址 (例如 \\\\x.x.x.x 或 \\\\x.x.x.x\\\\共享名): " smbaddr
        if [[ -z "$smbaddr" ]]; then
            _yellow "已取消"
            return 1
        fi

        # 去除可能的引号
        smbaddr=$(echo "$smbaddr" | sed 's/^"//;s/"$//')

        read -ep "请输入用户名 (默认 guest): " smbuser
        smbuser=${smbuser:-guest}

        read -esp "请输入密码 (留空为空密码): " smbpass
        echo

        # 使用 smbclient 列出共享或进入共享
        if [[ "$smbaddr" == *\\* ]]; then
            # 已包含共享名，直接列出文件
            _blue "正在连接 $smbaddr ..."
            smbclient "$smbaddr" -U "$smbuser%$smbpass" -c "ls" 2>/dev/null
        else
            # 只有主机，列出所有共享
            _blue "正在列出 $smbaddr 的共享 ..."
            smbclient -L "$smbaddr" -U "$smbuser%$smbpass" 2>/dev/null
        fi

        echo
        read -ep "是否进入交互模式浏览/下载? [y/N]: " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            if [[ "$smbaddr" == *\\* ]]; then
                smbclient "$smbaddr" -U "$smbuser%$smbpass"
            else
                read -ep "请输入共享名: " share
                if [[ -n "$share" ]]; then
                    smbclient "\\\\$smbaddr\\$share" -U "$smbuser%$smbpass"
                fi
            fi
        fi
    }

    #统计当前目录占用
    statisticsusage() {
        echo
        _blue "当前目录磁盘占用统计"
        echo
        du -sh * 2>/dev/null | sort -hr | head -20
        echo
        _blue "总计:"
        du -sh . 2>/dev/null
    }

    #统计目录文件行数
    countfileslines() {
        echo
        _blue "统计当前目录下所有文件的行数 (排除二进制文件)"
        echo
        find . -type f -not -path "*/.git/*" -not -name "*.log" -not -name "*.gz" -not -name "*.zip" -not -name "*.tar" -not -name "*.rar" -not -name "*.7z" -not -name "*.bz2" -not -name "*.xz" -not -name "*.iso" -not -name "*.img" -not -name "*.bin" -not -name "*.dat" -not -name "*.db" -not -name "*.sqlite" -not -name "*.jpg" -not -name "*.jpeg" -not -name "*.png" -not -name "*.gif" -not -name "*.bmp" -not -name "*.ico" -not -name "*.mp3" -not -name "*.mp4" -not -name "*.avi" -not -name "*.mov" -not -name "*.mkv" -not -name "*.flv" -not -name "*.wmv" -not -name "*.pdf" -not -name "*.doc" -not -name "*.docx" -not -name "*.xls" -not -name "*.xlsx" -not -name "*.ppt" -not -name "*.pptx" | while read file; do
            if file "$file" | grep -q "text"; then
                lines=$(wc -l < "$file" 2>/dev/null)
                if [[ $lines -gt 0 ]]; then
                    printf "%-8d %s\n" "$lines" "$file"
                fi
            fi
        done | sort -rn | head -30
        echo
        _blue "统计完成"
    }

    #文件搜索
    filesearchfun() {
        echo
        _blue "文件搜索模式"
        echo
        echo "1. 按名称搜索"
        echo "2. 按大小搜索"
        echo "3. 按时间搜索"
        echo
        read -rp "请选择搜索模式 [1-3]: " search_mode

        case $search_mode in
            1)
                searchbyname
                ;;
            2)
                searchbysize
                ;;
            3)
                searchbytime
                ;;
            *)
                echo "无效选择"
                return 1
                ;;
        esac
    }

    #按名称搜索
    searchbyname() {
        read -rp "请输入文件名关键词: " keyword
        if [[ -z "$keyword" ]]; then
            _yellow "关键词不能为空"
            return 1
        fi
        echo
        _blue "搜索包含 '$keyword' 的文件..."
        files=($(find . -type f -name "*$keyword*" 2>/dev/null | head -100))
        if [[ ${#files[@]} -eq 0 ]]; then
            _yellow "未找到匹配文件"
            return 1
        fi

        _yellow "找到 ${#files[@]} 个文件，显示前50个:"
        echo
        printf "%-5s %-10s %-20s %s\n" "序号" "大小" "修改时间" "路径"
        printf "%-5s %-10s %-20s %s\n" "-----" "----------" "--------------------" "----"
        local show=$((${#files[@]} > 50 ? 50 : ${#files[@]}))
        for ((i=0; i<show; i++)); do
            local size=$(du -h "${files[$i]}" 2>/dev/null | awk '{print $1}')
            local mtime=$(stat -c '%Y-%m-%d %H:%M' "${files[$i]}" 2>/dev/null)
            printf "%-5d %-10s %-20s %s\n" "$((i+1))" "$size" "$mtime" "${files[$i]}"
        done
    }

    #按大小搜索
    searchbysize() {
        echo "大小格式示例: 10M, 1G, 500K, +100M (大于), -10M (小于)"
        read -rp "请输入大小条件: " size_cond
        if [[ -z "$size_cond" ]]; then
            _yellow "条件不能为空"
            return 1
        fi
        echo
        _blue "搜索大小 $size_cond 的文件..."
        files=($(find . -type f -size "$size_cond" 2>/dev/null | head -100))
        if [[ ${#files[@]} -eq 0 ]]; then
            _yellow "未找到匹配文件"
            return 1
        fi

        _yellow "找到 ${#files[@]} 个文件，显示前50个:"
        echo
        printf "%-5s %-10s %-20s %s\n" "序号" "大小" "修改时间" "路径"
        printf "%-5s %-10s %-20s %s\n" "-----" "----------" "--------------------" "----"
        local show=$((${#files[@]} > 50 ? 50 : ${#files[@]}))
        for ((i=0; i<show; i++)); do
            local size=$(du -h "${files[$i]}" 2>/dev/null | awk '{print $1}')
            local mtime=$(stat -c '%Y-%m-%d %H:%M' "${files[$i]}" 2>/dev/null)
            printf "%-5d %-10s %-20s %s\n" "$((i+1))" "$size" "$mtime" "${files[$i]}"
        done
    }

    #按时间搜索
    searchbytime() {
        echo "时间格式示例: -7 (7天内), +30 (30天前), -1 (1天内)"
        read -rp "请输入时间条件 (天): " time_cond
        if [[ -z "$time_cond" ]]; then
            _yellow "条件不能为空"
            return 1
        fi
        echo
        _blue "搜索修改时间 $time_cond 天的文件..."
        files=($(find . -type f -mtime "$time_cond" 2>/dev/null | head -100))
        if [[ ${#files[@]} -eq 0 ]]; then
            _yellow "未找到匹配文件"
            return 1
        fi

        _yellow "找到 ${#files[@]} 个文件，显示前50个:"
        echo
        printf "%-5s %-10s %-20s %s\n" "序号" "大小" "修改时间" "路径"
        printf "%-5s %-10s %-20s %s\n" "-----" "----------" "--------------------" "----"
        local show=$((${#files[@]} > 50 ? 50 : ${#files[@]}))
        for ((i=0; i<show; i++)); do
            local size=$(du -h "${files[$i]}" 2>/dev/null | awk '{print $1}')
            local mtime=$(stat -c '%Y-%m-%d %H:%M' "${files[$i]}" 2>/dev/null)
            printf "%-5d %-10s %-20s %s\n" "$((i+1))" "$size" "$mtime" "${files[$i]}"
        done
    }

    menuname='首页/文件管理'
    echo "filefun" >$installdir/config/lastfun
    options=("压缩目录tar.gz" packagingdir_targz "解压tar.gz" uncompresseddir_targz "压缩目录zip" packagingdir_zip "解压zip" uncompresseddir_zip "压缩目录rar" packagingdir_rar "解压rar" uncompresseddir_rar "配置目录权限www-data" chownwwwdata "文件搜索" filesearchfun "统计当前目录占用" statisticsusage  "统计目录文件行数" countfileslines "多线程下载" aria2fun "smb连接器" smbfun )

    menu "${options[@]}"
}