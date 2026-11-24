filefun() {
    beforeMenu(){
    _blue "> ---  当前目录: [ $(pwd) ] ---- < v:$selfversion"
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
    #解压缩目录
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

    #配置目录权限www-data

    #压缩一个目录为 zip
    packagingdir_zip(){
        catcurrentpathfolder
        read -rp "请输入目录序号： " index
        if [[ "$index" =~ ^[0-9]+$ ]] && (( index >= 1 && index <= ${#dirs[@]} )); then
            dirtmp=${dirs[$((index - 1))]}
            filenametmp="$dirtmp.zip"
            du -sh $dirtmp
            read -rp "确认将 '$dirtmp' 打包为 '$filenametmp' ? [y/N]: " confirm
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

    #解压缩 zip 文件
    uncompresseddir_zip(){
        echo
        zip_files=($(ls *.zip 2>/dev/null))
        if [[ ${#zip_files[@]} -eq 0 ]]; then
            echo "当前目录下没有 zip 文件"
            return 1
        fi
        _blue "序号	zip 文件名"
        for i in "${!zip_files[@]}"; do
            echo -e "$((i + 1))	${zip_files[$i]}"
        done
        echo
        read -rp "请输入要解压的文件序号： " index
        if [[ "$index" =~ ^[0-9]+$ ]] && (( index >= 1 && index <= ${#zip_files[@]} )); then
            selected_file="${zip_files[$((index - 1))]}"
            _blue "待解压文件信息"
            ls -lh "$selected_file"
            read -rp "确认解压 '$selected_file' 到当前目录吗？[y/N]: " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                check_and_install unzip
                unzip -o "$selected_file" &
                loading $!
                wait
                _green "解压完成，文件已提交至当前目录"
            else
                echo "已取消解压操作。"
            fi
        else
            echo "无效的序号，请输入 1 到 ${#zip_files[@]} 之间的数字。"
            return 1
        fi
    }

    #压缩一个目录为 rar
    packagingdir_rar(){
        catcurrentpathfolder
        read -rp "请输入目录序号： " index
        if [[ "$index" =~ ^[0-9]+$ ]] && (( index >= 1 && index <= ${#dirs[@]} )); then
            dirtmp=${dirs[$((index - 1))]}
            filenametmp="$dirtmp.rar"
            du -sh $dirtmp
            read -rp "确认将 '$dirtmp' 打包为 '$filenametmp' ? [y/N]: " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                if ! command -v rar &>/dev/null; then
                    _blue "未检测到 rar 命令，尝试安装..."
                    check_and_install rar || { _red "rar 安装失败，请手动安装 rar (Debian/Ubuntu需启用non-free源)"; return 1; }
                fi
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

    #解压缩 rar 文件
    uncompresseddir_rar(){
        echo
        rar_files=($(ls *.rar 2>/dev/null))
        if [[ ${#rar_files[@]} -eq 0 ]]; then
            echo "当前目录下没有 rar 文件"
            return 1
        fi
        _blue "序号	rar 文件名"
        for i in "${!rar_files[@]}"; do
            echo -e "$((i + 1))	${rar_files[$i]}"
        done
        echo
        read -rp "请输入要解压的文件序号： " index
        if [[ "$index" =~ ^[0-9]+$ ]] && (( index >= 1 && index <= ${#rar_files[@]} )); then
            selected_file="${rar_files[$((index - 1))]}"
            _blue "待解压文件信息"
            ls -lh "$selected_file"
            read -rp "确认解压 '$selected_file' 到当前目录吗？[y/N]: " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                if command -v unrar &>/dev/null; then
                    unrar x -y "$selected_file" &
                elif command -v unrar-free &>/dev/null; then
                    unrar-free x -y "$selected_file" &
                elif command -v 7z &>/dev/null; then
                    7z x -y "$selected_file" &
                else
                    _blue "未检测到 unrar/unrar-free/7z 命令，尝试安装..."
                    check_and_install unrar || check_and_install p7zip || { _red "解压工具安装失败，请手动安装 unrar 或 p7zip"; return 1; }
                    if command -v unrar &>/dev/null; then
                        unrar x -y "$selected_file" &
                    elif command -v unrar-free &>/dev/null; then
                        unrar-free x -y "$selected_file" &
                    elif command -v 7z &>/dev/null; then
                        7z x -y "$selected_file" &
                    else
                        _red "安装后仍未找到可用的解压工具"; return 1
                    fi
                fi
                loading $!
                wait
                _green "解压完成，文件已提交至当前目录"
            else
                echo "已取消解压操作。"
            fi
        else
            echo "无效的序号，请输入 1 到 ${#rar_files[@]} 之间的数字。"
            return 1
        fi
    }


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

        # 统一分隔符并解析主机与共享名
        local raw="${smbaddr//\\//}"
        while [[ "$raw" == /* ]]; do raw="${raw#/}"; done
        local host="${raw%%/*}"
        local share=""
        [[ "$raw" == */* ]] && share="${raw#*/}"
        while [[ "$share" == /* ]]; do share="${share#/}"; done
        share="${share%%/*}"
        host="${host// /}"
        if [[ -z "$host" ]]; then
            _red "地址格式不正确，应为 \\\\主机 或 \\\\主机\\\\共享名"
            return 1
        fi

        local -a auth_opts=()
        local auth_desc="匿名"
        local smb_ok=0

        # 首先尝试匿名登录
        _blue "尝试匿名登录 $host ..."
        if [[ -n "$share" ]]; then
            smbclient "//$host/$share" -N -c 'ls' &>/dev/null || smb_ok=1
        else
            smbclient -L "//$host" -N &>/dev/null || smb_ok=1
        fi

        if [[ $smb_ok -ne 0 ]]; then
            _yellow "匿名登录失败，请提供用户名和密码"
            local smbuser="" smbpass=""
            read -ep "用户名: " smbuser
            if [[ -z "$smbuser" ]]; then
                _red "未输入用户名，已取消"
                return 1
            fi
            read -rsp "密码: " smbpass
            echo
            auth_opts=(-U "$smbuser%$smbpass")
            auth_desc="$smbuser"

            smb_ok=0
            if [[ -n "$share" ]]; then
                smbclient "//$host/$share" "${auth_opts[@]}" -c 'ls' &>/dev/null || smb_ok=1
            else
                smbclient -L "//$host" "${auth_opts[@]}" &>/dev/null || smb_ok=1
            fi
            if [[ $smb_ok -ne 0 ]]; then
                _red "登录失败，请检查用户名、密码或网络连通性"
                return 1
            fi
            _green "登录成功: $smbuser@$host"
        else
            auth_opts=(-N)
            _green "匿名登录成功"
        fi

        # 未指定共享名时，列出共享供选择
        if [[ -z "$share" ]]; then
            local -a shares=()
            local sline=""
            while IFS= read -r sline; do
                [[ -n "$sline" ]] && shares+=("$sline")
            done < <(smbclient -L "//$host" "${auth_opts[@]}" 2>/dev/null | awk '$2 == "Disk" { print $1 }')

            if [[ ${#shares[@]} -eq 0 ]]; then
                _red "未发现可用的共享目录"
                return 1
            fi

            if [[ ${#shares[@]} -eq 1 ]]; then
                share="${shares[0]}"
                _green "使用共享: $share"
            else
                echo
                _blue "可用共享列表:"
                local si
                for si in "${!shares[@]}"; do
                    echo -e "$((si + 1))\t${shares[$si]}"
                done
                echo
                read -ep "请输入共享目录序号 (默认 1): " snum
                [[ -z "$snum" ]] && snum=1
                if ! [[ "$snum" =~ ^[0-9]+$ ]] || [[ $snum -lt 1 ]] || [[ $snum -gt ${#shares[@]} ]]; then
                    _red "序号无效"
                    return 1
                fi
                share="${shares[$((snum - 1))]}"
            fi
        fi

        # 目录浏览循环
        local cwd=""
        local sel=0
        local key="" rest=""
        local -a names=() types=() sizes=()
        local listing="" total=0 rows=0 start=0 i=0
        local curname="" curtype="" localname=""

        while true; do
            # 拉取当前 SMB 目录列表
            local -a smbcmd=(smbclient "//$host/$share" "${auth_opts[@]}")
            [[ -n "$cwd" ]] && smbcmd+=(-D "$cwd")
            listing=$("${smbcmd[@]}" -c 'ls' 2>/dev/null)

            names=(); types=(); sizes=()
            while IFS='|' read -r n t s; do
                [[ -z "$n" ]] && continue
                [[ "$n" == "." ]] && continue
                names+=("$n"); types+=("$t"); sizes+=("$s")
            done < <(printf '%s\n' "$listing" | awk '
                {
                    attr = ""; idx = 0; size = ""
                    for (i = 2; i < NF; i++) {
                        if ($i ~ /^[A-Z]+$/ && $(i + 1) ~ /^[0-9]+$/) { attr = $i; idx = i; break }
                    }
                    if (idx == 0) next
                    name = ""
                    for (i = 1; i < idx; i++) name = (name == "" ? $i : name " " $i)
                    if (name == "") next
                    size = $(idx + 1)
                    type = (attr ~ /D/) ? "d" : "f"
                    printf "%s|%s|%s\n", name, type, size
                }')

            # 目录排在前面，.. 排最前
            local -a dnames=() dtypes=() dsizes=() fnames=() ftypes=() fsizes=()
            for i in "${!names[@]}"; do
                if [[ "${names[$i]}" == ".." ]]; then
                    dnames=(".." "${dnames[@]}")
                    dtypes=("d" "${dtypes[@]}")
                    dsizes=("0" "${dsizes[@]}")
                elif [[ "${types[$i]}" == "d" ]]; then
                    dnames+=("${names[$i]}"); dtypes+=("d"); dsizes+=("0")
                else
                    fnames+=("${names[$i]}"); ftypes+=("f"); fsizes+=("${sizes[$i]}")
                fi
            done
            names=("${dnames[@]}" "${fnames[@]}")
            types=("${dtypes[@]}" "${ftypes[@]}")
            sizes=("${dsizes[@]}" "${fsizes[@]}")
            total=${#names[@]}

            [[ $sel -ge $total ]] && sel=$((total > 0 ? total - 1 : 0))

            # 渲染列表
            printf "\033[H\033[2J"
            _blue "SMB: //$host/$share    用户: $auth_desc    路径: /${cwd}"
            echo
            rows=$(( $(tput lines 2>/dev/null || echo 24) - 8 ))
            [[ $rows -lt 5 ]] && rows=5
            start=0
            [[ $sel -ge $rows ]] && start=$((sel - rows + 1))

            if [[ $total -eq 0 ]]; then
                _yellow "  (目录为空)"
            fi
            for ((i = start; i < total && i < start + rows; i++)); do
                local icon="[FILE]"
                local disp="${names[$i]}"
                if [[ "${types[$i]}" == "d" ]]; then
                    icon="[DIR ]"
                    [[ "$disp" == ".." ]] && disp=".. (上级目录)"
                fi
                if [[ $i -eq $sel ]]; then
                    printf "\033[7m %s %s \033[0m\n" "$icon" "$disp"
                else
                    printf " %s %s\n" "$icon" "$disp"
                fi
            done
            echo
            _yellow "↑/↓ 选择    回车 进入目录/下载文件    q 退出"

            # 读取按键
            key=""
            IFS= read -rsn1 key
            if [[ "$key" == $'\x1b' ]]; then
                rest=""
                IFS= read -rsn2 -t 0.2 rest
                case "$rest" in
                    '[A') [[ $sel -gt 0 ]] && sel=$((sel - 1)) ;;
                    '[B') [[ $sel -lt $((total - 1)) ]] && sel=$((sel + 1)) ;;
                esac
                continue
            fi

            case "$key" in
                q|Q)
                    _yellow "已退出 SMB 浏览"
                    break
                    ;;
                k)
                    [[ $sel -gt 0 ]] && sel=$((sel - 1))
                    continue
                    ;;
                j)
                    [[ $sel -lt $((total - 1)) ]] && sel=$((sel + 1))
                    continue
                    ;;
                '')
                    if [[ $total -eq 0 ]]; then
                        continue
                    fi
                    curname="${names[$sel]}"
                    curtype="${types[$sel]}"

                    if [[ "$curname" == ".." ]]; then
                        if [[ -z "$cwd" ]]; then
                            continue
                        fi
                        if [[ "$cwd" == */* ]]; then
                            cwd="${cwd%/*}"
                        else
                            cwd=""
                        fi
                        sel=0
                    elif [[ "$curtype" == "d" ]]; then
                        if [[ -z "$cwd" ]]; then
                            cwd="$curname"
                        else
                            cwd="$cwd/$curname"
                        fi
                        sel=0
                    else
                        localname="${curname##*/}"
                        local expsize="${sizes[$sel]}"
                        [[ "$expsize" =~ ^[0-9]+$ ]] || expsize=0
                        echo
                        _blue "开始下载: $curname  ->  $(pwd)/$localname"
                        # 后台下载：stdout/stderr 全部隔离，屏蔽 smb.conf 参数告警
                        local dlerr="/tmp/.s_smb_err.$$"
                        rm -f "$localname"
                        "${smbcmd[@]}" -c "get \"$curname\" \"$localname\"" >/dev/null 2>"$dlerr" &
                        local dlpid=$!
                        if [[ $expsize -gt 0 ]]; then
                            # 已知大小：显示实时进度条
                            local bar_len=30 spin='|/-\' si=0
                            tput civis 2>/dev/null
                            while kill -0 "$dlpid" 2>/dev/null; do
                                local cur=$(stat -c %s "$localname" 2>/dev/null || echo 0)
                                [[ "$cur" =~ ^[0-9]+$ ]] || cur=0
                                local pct=$(( cur * 100 / expsize ))
                                [[ $pct -gt 100 ]] && pct=100
                                local filled=$(( pct * bar_len / 100 ))
                                local empty=$(( bar_len - filled ))
                                local barf="" bare=""
                                [[ $filled -gt 0 ]] && barf=$(printf '█%.0s' $(seq 1 $filled))
                                [[ $empty -gt 0 ]] && bare=$(printf '░%.0s' $(seq 1 $empty))
                                printf "\r\033[0;36m[%s%s] %3d%%  %s %s/%s\033[0m" \
                                    "$barf" "$bare" "$pct" "${spin:si++%4:1}" \
                                    "$(du -h "$localname" 2>/dev/null | awk '{print $1}')" \
                                    "$(echo "$expsize" | awk '{printf "%.1fM", $1/1048576}')"
                                sleep 0.2
                            done
                            tput cnorm 2>/dev/null
                            printf "\r\033[K"
                        else
                            # 大小未知：沿用脚本自带的转圈等待
                            loading "$dlpid"
                        fi
                        wait "$dlpid"
                        local dlrc=$?
                        if [[ $dlrc -eq 0 && -s "$localname" ]]; then
                            _green "下载完成: $localname  [$(du -h "$localname" 2>/dev/null | awk '{print $1}')]"
                        else
                            _red "下载失败: $curname"
                            [[ -s "$dlerr" ]] && tail -n 3 "$dlerr"
                        fi
                        rm -f "$dlerr"
                        waitinput
                    fi
                    ;;
            esac
        done
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

    filesearchfun() {
        searchbyname() {
            read -ep "请输入搜索路径 (默认当前目录): " searchpath
            searchpath=${searchpath:-.}
            read -ep "请输入文件名关键词: " keyword
            [[ -z "$keyword" ]] && { _yellow "已取消"; return; }

            echo
            _blue "搜索结果: $searchpath 下包含 '$keyword' 的文件"
            echo

            local files=()
            while IFS= read -r -d '' f; do
                files+=("$f")
            done < <(find "$searchpath" -name "*$keyword*" -print0 2>/dev/null)

            if [[ ${#files[@]} -eq 0 ]]; then
                _yellow "未找到匹配文件"
                return
            fi

            printf "%-5s %-10s %-20s %s\n" "序号" "大小" "修改时间" "路径"
            printf "%-5s %-10s %-20s %s\n" "-----" "----------" "--------------------" "----"
            for i in "${!files[@]}"; do
                local size=$(du -h "${files[$i]}" 2>/dev/null | awk '{print $1}')
                local mtime=$(stat -c '%Y-%m-%d %H:%M' "${files[$i]}" 2>/dev/null)
                printf "%-5d %-10s %-20s %s\n" "$((i+1))" "$size" "$mtime" "${files[$i]}"
            done

            echo
            read -ep "操作: 1)查看 2)删除 3)移动 0)取消: " action
            case "$action" in
                1)
                    read -ep "请输入序号: " idx
                    if [[ "$idx" =~ ^[0-9]+$ ]] && (( idx >= 1 && idx <= ${#files[@]} )); then
                        echo
                        if file "${files[$((idx-1))]}" | grep -q "text"; then
                            less "${files[$((idx-1))]}"
                        else
                            file "${files[$((idx-1))]}"
                            ls -lh "${files[$((idx-1))]}"
                        fi
                    fi
                    ;;
                2)
                    read -ep "请输入要删除的序号 (多个空格分隔): " dels
                    for d in $dels; do
                        if [[ "$d" =~ ^[0-9]+$ ]] && (( d >= 1 && d <= ${#files[@]} )); then
                            rm -f "${files[$((d-1))]}"
                            _green "已删除: ${files[$((d-1))]}"
                        fi
                    done
                    ;;
                3)
                    read -ep "请输入文件序号: " fidx
                    read -ep "请输入目标目录: " destdir
                    if [[ "$fidx" =~ ^[0-9]+$ ]] && (( fidx >= 1 && fidx <= ${#files[@]} )) && [[ -d "$destdir" ]]; then
                        mv "${files[$((fidx-1))]}" "$destdir/"
                        _green "已移动到 $destdir/"
                    else
                        _red "无效输入"
                    fi
                    ;;
                *) ;;
            esac
        }

        searchbysize() {
            read -ep "请输入搜索路径 (默认当前目录): " searchpath
            searchpath=${searchpath:-.}
            echo "大小选项: +100M  +1G  +10G  -1M  ..."
            read -ep "请输入大小条件 (如 +100M 表示大于100M): " sizecond
            [[ -z "$sizecond" ]] && { _yellow "已取消"; return; }

            echo
            _blue "搜索结果: $searchpath 下大小 $sizecond 的文件"
            echo

            local files=()
            while IFS= read -r -d '' f; do
                files+=("$f")
            done < <(find "$searchpath" -type f -size "$sizecond" -print0 2>/dev/null)

            if [[ ${#files[@]} -eq 0 ]]; then
                _yellow "未找到匹配文件"
                return
            fi

            printf "%-5s %-10s %-20s %s\n" "序号" "大小" "修改时间" "路径"
            printf "%-5s %-10s %-20s %s\n" "-----" "----------" "--------------------" "----"
            for i in "${!files[@]}"; do
                local size=$(du -h "${files[$i]}" 2>/dev/null | awk '{print $1}')
                local mtime=$(stat -c '%Y-%m-%d %H:%M' "${files[$i]}" 2>/dev/null)
                printf "%-5d %-10s %-20s %s\n" "$((i+1))" "$size" "$mtime" "${files[$i]}"
            done
        }

        searchbytime() {
            read -ep "请输入搜索路径 (默认当前目录): " searchpath
            searchpath=${searchpath:-.}
            echo "时间选项:"
            echo "  1) 最近1天内修改"
            echo "  2) 最近7天内修改"
            echo "  3) 最近30天内修改"
            echo "  4) 最近60分钟内修改"
            read -ep "请选择: " timeopt

            local findtime=""
            case "$timeopt" in
                1) findtime="-mtime -1" ;;
                2) findtime="-mtime -7" ;;
                3) findtime="-mtime -30" ;;
                4) findtime="-mmin -60" ;;
                *) _yellow "已取消"; return ;;
            esac

            echo
            _blue "搜索结果:"
            echo

            local files=()
            while IFS= read -r -d '' f; do
                files+=("$f")
            done < <(eval "find '$searchpath' -type f $findtime -print0" 2>/dev/null)

            if [[ ${#files[@]} -eq 0 ]]; then
                _yellow "未找到匹配文件"
                return
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

        menuname='首页/文件管理/文件搜索'
        options=("按名称搜索" searchbyname "按大小搜索" searchbysize "按时间搜索" searchbytime)
        menu "${options[@]}"
    }

    menuname='首页/文件管理'
    echo "filefun" >$installdir/config/lastfun
    options=("打包目录tar.gz" packagingdir_targz "解压tar.gz" uncompresseddir_targz "打包目录zip" packagingdir_zip "解压zip" uncompresseddir_zip "打包目录rar" packagingdir_rar "解压rar" uncompresseddir_rar "配置目录权限www-data" chownwwwdata "文件搜索" filesearchfun "统计当前目录占用" statisticsusage  "统计目录文件行数" countfileslines "多线程下载" aria2fun "smb连接" smbfun )

    menu "${options[@]}"

}