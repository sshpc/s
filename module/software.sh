softwarefun() {
    beforeMenu(){
        _blue "> ---  当前目录: [ $(pwd) ] ---- < v:$selfversion"
        echo
        _yellow "当前菜单: $menuname "
        echo
    }
    
    # 下载并执行sh
    runthirdscript() {
        local url="$1"
        local param="$2"
        local outputdir="$HOME/thirdscript"
        local timeout=3
        local rawname
        rawname=$(basename "$url")

        local cachekey
        if command -v sha1sum >/dev/null 2>&1; then
            cachekey=$(printf '%s' "$url" | sha1sum | awk '{print substr($1,1,12)}')
        else
            cachekey=$(printf '%s' "$url" | tr -c '[:alnum:]' '_')
        fi
        local cachedir="$outputdir/$cachekey"
        local filename="$rawname"
        mkdir -p "$cachedir"

        local filepath="$cachedir/$filename"
        if [[ -s "$filepath" ]]; then
            _yellow "使用缓存脚本：$filepath（如内容过期可手动删除后重试）"
            bash "$filepath" "$param"
            return $?
        fi

        local downloaded=0
        local -a urlparts=()
        read -r -a urlparts <<< "${url} ${param}"
        if (( ${#urlparts[@]} == 0 )); then
            _red "空 URL"
            return 1
        fi

        for base in "${proxylinks[@]}"; do
            local fullurl="${base}/${urlparts[0]}"
            local tmppath="$filepath.part.$$"
            _yellow "使用地址前缀: ${base}/"
            _blue "下载: $fullurl"

            local total=0
            total=$(wget --spider -S --timeout="$timeout" --tries=1 -q "$fullurl" 2>&1 |
                awk 'tolower($0) ~ /content-length:/ {v = $2} END {gsub(/\r/, "", v); print v + 0}')
            [[ "$total" =~ ^[0-9]+$ ]] || total=0

            rm -f "$tmppath"
            wget -q --timeout="$timeout" --tries=1 -O "$tmppath" "$fullurl" >/dev/null 2>&1 &
            local wpid=$!
            while kill -0 "$wpid" 2>/dev/null; do
                local size=0
                [[ -f "$tmppath" ]] && size=$(stat -c %s "$tmppath" 2>/dev/null)
                [[ "$size" =~ ^[0-9]+$ ]] || size=0
                if [ -t 1 ]; then
                    if (( total > 0 )); then
                        local pct=$(( size * 100 / total ))
                        (( pct > 100 )) && pct=100
                        local fill=$(( pct * 40 / 100 ))
                        local bar=$(printf '%*s' "$fill" '' | tr ' ' '=')
                        local empty=$(printf '%*s' "$((40 - fill))" '' | tr ' ' '.')
                        printf "\r\033[0;36m下载中 [%s%s] %3d%% (%d/%d bytes) 源:%s\033[0m\033[K" \
                            "$bar" "$empty" "$pct" "$size" "$total" "${base:0:24}"
                    else
                        printf "\r\033[0;36m下载中 [已接收 %d bytes] 源:%s\033[0m\033[K" \
                            "$size" "${base:0:24}"
                    fi
                fi
                sleep 0.2
            done
            wait "$wpid"
            local rc=$?
            if [ -t 1 ]; then
                printf "\r\033[K"
            else
                echo
            fi

            if (( rc == 0 )) && [[ -s "$tmppath" ]]; then
                mv -f "$tmppath" "$filepath"
                downloaded=1
                _green "已下载文件：$filepath"
                break
            else
                _red "下载失败：${base}/${urlparts[0]}"
                rm -f "$tmppath"
            fi
        done

        if (( downloaded == 0 )); then
            _red "所有源均下载失败，退出。"
            return 1
        fi

        if ! bash -n "$filepath" 2>/dev/null; then
            _red "脚本语法校验失败，已保留文件供检查：$filepath"
            return 1
        fi
        chmod +x "$filepath"
        bash "$filepath" "${urlparts[@]:1}"
    }

    
    # 更新所有已安装的软件包
    aptupdatefun() {
        dpkg --configure -a
        local aptprocs
        aptprocs=$(pgrep -x apt-get 2>/dev/null; pgrep -x apt 2>/dev/null)
        if [[ -n "$aptprocs" ]]; then
            _yellow "→ 检测到 apt 进程仍在运行（PID: $(echo "$aptprocs" | tr '\n' ' ')），等待其结束..."
            local waited=0
            while (( waited < 30 )) && pgrep -x apt-get >/dev/null 2>&1; do
                sleep 1
                ((waited++))
            done
            if pgrep -x apt-get >/dev/null 2>&1 || pgrep -x apt >/dev/null 2>&1; then
                _red "apt 进程仍未结束，请手动确认后再重试（本脚本不再强杀进程）"
                next
                return 1
            fi
        fi
        _blue "→ 正在更新软件包列表（apt update）..."
        if ! apt-get update -y; then
            _red "apt update 失败，请检查网络或软件源"
            next
            return 1
        fi
        echo
        _blue "→ 是否升级所有已安装软件包（apt upgrade）？"
        local choice=""
        read -r -n 1 -p "输入 y 确认升级，不升级直接回车: " choice || choice=""
        echo

        if [[ "$choice" =~ ^[Yy]$ ]]; then
            _blue "→ 开始升级软件包（过程可能较长）..."
            if apt-get upgrade -y; then
                _green "软件包升级完成"
            else
                _red "apt upgrade 失败，请检查上面的错误信息"
                next
                return 1
            fi
        else
            _yellow "跳过升级"
        fi
        _green "更新完成"
        next
    }
    # 修复更新
    configureaptfun() {
        _red '注意：这将终止 apt/dpkg 进程并删除锁文件，请确保没有其他终端正在安装软件！'
        waitinput
        _blue '修复更新..'
        pkill -9 -x apt-get 2>/dev/null || true
        pkill -9 -x apt 2>/dev/null || true
        pkill -9 -x dpkg 2>/dev/null || true
        rm -f /var/lib/dpkg/lock-frontend \
              /var/lib/dpkg/lock \
              /var/lib/apt/lists/lock \
              /var/cache/apt/archives/lock
        dpkg --configure -a
        apt-get install -f -y
        apt-get update -y
        apt-get autoremove --purge -y
        apt-get clean -y
        apt-get autoclean -y
        _green '修复完成'
        next
    }
    # 安装常用包
    installcomso() {
        check_and_install wget curl jq net-tools vim openssh-server git zip htop gdu
        echo "所有包都已安装完成"
    }
    
    smbdinstall(){
        _red '注意安装后默认会直接开放home目录匿名可读写访问'
        waitinput
        check_and_install samba 
        
        backup_time=$(date +"%Y%m%d_%H%M%S")
        cp /etc/samba/smb.conf /etc/samba/smb.conf.bak.$backup_time
        
        echo "" >> /etc/samba/smb.conf
        echo "[home]" >> /etc/samba/smb.conf
        echo "   path = /home" >> /etc/samba/smb.conf
        echo "   browseable = yes" >> /etc/samba/smb.conf
        echo "   writable = yes" >> /etc/samba/smb.conf
        echo "   guest ok = yes" >> /etc/samba/smb.conf
        echo "   force user = root" >> /etc/samba/smb.conf
        echo "   force group = root" >> /etc/samba/smb.conf
        
        systemctl restart smbd
        systemctl restart nmbd
        
        _blue "samba 安装并配置完成，/home 目录可匿名读写，权限为 root。"
    }
    
    # 换源
    changemirrors() {
        cnmainland() {
            runthirdscript SuperManito/LinuxMirrors/main/ChangeMirrors.sh
        }
        overseas() {
            runthirdscript SuperManito/LinuxMirrors/main/ChangeMirrors.sh --abroad
        }

        cnmainlandedu(){
            runthirdscript SuperManito/LinuxMirrors/main/ChangeMirrors.sh --edu
        }

        getlinuxmirrorsmain(){
            bash <(curl -sSL https://linuxmirrors.cn/main.sh)
        }
        
        menuname='首页/软件/换源'
        options=("大陆" cnmainland "海外" overseas "教育网" cnmainlandedu "getlinuxmirrors大陆" getlinuxmirrorsmain)
        menu "${options[@]}"

        if [ -f /etc/apt/sources.list.bak ]; then
            local baksuffix
            baksuffix=$(date +"%Y%m%d_%H%M%S")
            mv /etc/apt/sources.list.bak "/etc/apt/sources.list.bak.$baksuffix"
            echo "sources.list.bak 已重命名为 /etc/apt/sources.list.bak.$baksuffix"
        fi
    }
    
    removefun() {
        # 专项卸载
        removephp() {
            masterremove php
        }
        removenginx() {
            apt-get --purge remove nginx-common -y
            apt-get --purge remove nginx-core -y
            masterremove nginx
        }
        removeapache() {
            apt-get --purge remove apache2-common -y
            apt-get --purge remove apache2-utils -y
            masterremove apache2
        }
        removev2() {
            masterremove v2ray
        }
        removemysql() {
            apt-get remove mysql-common -y
            apt-get remove dbconfig-mysql -y
            apt-get remove mysql-client -y
            apt-get remove mysql-client-5.7 -y
            apt-get remove mysql-client-core-5.7 -y
            apt-get remove apparmor -y
            apt-get autoremove -y
            masterremove mysql-server
        }
        # 软件名校验：按 dpkg 包名规范限制字符集，杜绝通配符/路径/命令注入
        _uninstall_name_valid() {
            local n="$1"
            [[ -n "$n" ]] || { _red "软件名不能为空"; return 1; }
            (( ${#n} >= 2 )) || { _red "软件名过短（至少 2 个字符），已拒绝：$n"; return 1; }
            (( ${#n} <= 64 )) || { _red "软件名过长（最多 64 个字符），已拒绝"; return 1; }
            if [[ ! "$n" =~ ^[a-zA-Z0-9][a-zA-Z0-9._+-]*$ ]]; then
                _red "软件名含非法字符，只允许字母、数字和 . _ + -：$n"
                return 1
            fi
            case "$n" in
                */*|*..*) _red "软件名不能包含路径分隔符或 ..：$n"; return 1 ;;
            esac
            case "$n" in
                etc|usr|var|lib|bin|sbin|boot|home|root|run|opt|tmp|sys|proc|dev|lib64|systemd)
                    _red "拒绝卸载系统关键目录名：$n"; return 1 ;;
            esac
            return 0
        }

        # 彻底卸载：按 dpkg 包清单精确删除，不再按名字模糊 find
        masterremove() {
            local resoftname
            if [ $# -eq 0 ]; then
                read -ep "请输入要卸载的软件名（dpkg 包名，可用 dpkg -l 查询）: " resoftname
            else
                resoftname="$1"
            fi

            if ! _uninstall_name_valid "$resoftname"; then
                _red "已取消卸载操作"
                next
                return 1
            fi

            local -a cand=()
            local pkg pkg_status
            pkg_status=$(dpkg-query -W -f='${Status}' -- "$resoftname" 2>/dev/null)
            if [[ "$pkg_status" == "install ok installed" ]]; then
                cand+=("$resoftname")
            else
                if [[ -n "$pkg_status" ]]; then
                    _red "包 $resoftname 当前状态为「$pkg_status」，不是已安装状态"
                else
                    _yellow "未在 apt 已安装包中找到 $resoftname（可能是手动安装或已经卸载）"
                fi
                local -a fixedpaths=()
                local cand_path
                for cand_path in \
                    "/etc/$resoftname" "/etc/$resoftname.d" \
                    "/usr/bin/$resoftname" "/usr/local/bin/$resoftname" \
                    "/usr/sbin/$resoftname" "/usr/local/sbin/$resoftname" \
                    "/usr/share/$resoftname" "/usr/lib/$resoftname" \
                    "/var/log/$resoftname" "/var/lib/$resoftname" \
                    "/opt/$resoftname" "/run/$resoftname" \
                    "/etc/systemd/system/$resoftname.service" \
                    "/lib/systemd/system/$resoftname.service" \
                    "/etc/init.d/$resoftname"; do
                    [[ -e "$cand_path" || -L "$cand_path" ]] && fixedpaths+=("$cand_path")
                done
                if (( ${#fixedpaths[@]} == 0 )); then
                    _yellow "也没有找到固定路径下的残留，无需处理"
                    next
                    return 1
                fi
                _yellow "将只清理以下固定路径（不扫描整个文件系统）："
                printf '  %s\n' "${fixedpaths[@]}"
                local fixedconfirm
                read -r -p "确认删除以上路径？(输入 yes 确认，其他任意键跳过): " fixedconfirm
                if [[ "$fixedconfirm" == "yes" ]]; then
                    for cand_path in "${fixedpaths[@]}"; do
                        [[ -z "$cand_path" || "$cand_path" == "/" ]] && continue
                        rm -rf -- "$cand_path"
                    done
                    _green "已清理固定路径下的残留"
                else
                    _yellow "已跳过"
                fi
                next
                return 0
            fi

            _yellow "匹配到已安装包："
            local meta
            for pkg in "${cand[@]}"; do
                meta=$(dpkg-query -W -f='${Version}  E=${Essential}  P=${Priority}' -- "$pkg" 2>/dev/null)
                printf '  %-30s %s\n' "$pkg" "$meta"
            done
            echo

            local -a critical=()
            for pkg in "${cand[@]}"; do
                meta=$(dpkg-query -W -f='${Essential} ${Priority}' -- "$pkg" 2>/dev/null)
                case "$meta" in
                    yes*|*" required"|*" important") critical+=("$pkg") ;;
                esac
            done
            if (( ${#critical[@]} > 0 )); then
                _red "警告：以下属于 Essential、Priority=required 或 important 的系统包："
                printf '  %s\n' "${critical[@]}"
                _red "卸载它们极可能损坏系统（缺少 shell、coreutils、systemd、passwd、hostname 等会导致无法登录或无法启动）"
                local riskconfirm
                read -r -p "确认继续？请输入 I-UNDERSTAND 全大写确认，其他任意内容取消: " riskconfirm
                if [[ "$riskconfirm" != "I-UNDERSTAND" ]]; then
                    _yellow "已取消（这是推荐的选择）"
                    next
                    return 1
                fi
            fi

            _red "注意：将会卸载以下包及其配置：${cand[*]}"
            waitinput
            echo "关闭服务.."
            for pkg in "${cand[@]}"; do
                service "$pkg" stop 2>/dev/null
                systemctl stop "$pkg" 2>/dev/null
            done

            local -a owned=()
            local f
            for pkg in "${cand[@]}"; do
                while IFS= read -r f; do
                    [[ "$f" == /* ]] || continue
                    owned+=("$f")
                done < <(dpkg -L "$pkg" 2>/dev/null)
            done

            echo "执行 purge.."
            apt-get --purge remove -y -- "${cand[@]}"
            local purge_rc=$?
            if (( purge_rc != 0 )); then
                _red "apt-get purge 返回 $purge_rc，请检查上面的输出"
                next
                return $purge_rc
            fi

            local -a uniq_left=()
            if (( ${#owned[@]} > 0 )); then
                local -a sorted_owned=()
                mapfile -t sorted_owned < <(printf '%s\n' "${owned[@]}" | sort -u)
                for f in "${sorted_owned[@]}"; do
                    [[ -n "$f" ]] || continue
                    [[ -f "$f" || -L "$f" ]] || continue
                    case "$f" in
                        /|/bin|/sbin|/lib|/lib64|/usr|/usr/bin|/usr/sbin|/usr/lib|/etc|/var|/var/lib|/var/lib/dpkg|/var/lib/dpkg/*|/boot|/proc|/sys|/dev)
                            continue ;;
                        /etc/passwd|/etc/shadow|/etc/group|/etc/gshadow|/etc/hosts|/etc/hostname|/etc/fstab|/etc/passwd-|/etc/shadow-|/etc/group-)
                            continue ;;
                        /etc/pam.d/*|/etc/ssh/*|/etc/sudoers*|/etc/ld.so.*|/etc/default/*)
                            continue ;;
                        /usr/bin/bash*|/usr/bin/sh|/usr/bin/env|/usr/bin/dpkg*|/usr/bin/apt*|/usr/bin/passwd|/usr/bin/hostname|/usr/bin/login|/usr/sbin/*)
                            continue ;;
                    esac
                    uniq_left+=("$f")
                done
            fi

            if (( ${#uniq_left[@]} == 0 )); then
                _green "没有残留文件，卸载干净"
            else
                _yellow "以下 ${#uniq_left[@]} 个残留文件（来自该包的 dpkg 清单）："
                printf '  %s\n' "${uniq_left[@]}"
                local delconfirm
                read -r -p "确认删除这些残留？(输入 yes 确认，其他任意键跳过): " delconfirm
                if [[ "$delconfirm" == "yes" ]]; then
                    for f in "${uniq_left[@]}"; do
                        [[ -z "$f" || "$f" == "/" ]] && continue
                        rm -rf -- "$f"
                    done
                    _green "残留文件已删除"
                else
                    _yellow "已跳过残留文件删除"
                fi
            fi

            next
            echo
            _blue "卸载完成"
        }
        menuname='首页/软件/卸载'
        options=("手动输入" masterremove "卸载nginx" removenginx "卸载Apache" removeapache "卸载php" removephp "卸载v2ray" removev2 "卸载mysql" removemysql)
        menu "${options[@]}"
    }
    
    snapfun() {
        beforeMenu(){
            _blue "> ---  当前目录: [ $(pwd) ] ---- < v:$selfversion"
            echo
            if command -v snap &> /dev/null; then
                _green "snap 已安装"
            else
                _red "snap 未安装"
            fi
            echo
            _yellow "当前菜单: $menuname "
            echo
        }
        snapls() {
            echo
            _blue version:
            echo
            snap version
            echo
            _blue list:
            echo
            snap list
        }
        checksnap() {
            check_and_install snap snapd
        }
        installbtop() {
            checksnap
            snap install btop
            btop
        }
        dockersnapinstall() {
            checksnap
            snap install docker
        }
        
        menuname='首页/软件/snap管理'
        options=("查看 snap 状态" snapls "安装" checksnap "安装btop" installbtop "安装snap版docker" dockersnapinstall)
        menu "${options[@]}"
    }
    
    softdockerfun() {
        beforeMenu(){
            _blue "> ---  当前目录: [ $(pwd) ] ---- < v:$selfversion"
            echo
            if command -v docker &>/dev/null; then
                _green "docker 已安装: $(docker --version 2>/dev/null)"
            else
                _red "docker 未安装"
            fi
            echo
            _yellow "当前菜单: $menuname "
            echo
        }

        # 安装docker
        softdocker_install() {
            _blue "开始安装 Docker ..."
            if command -v docker &>/dev/null; then
                _yellow "检测到已安装: $(docker --version 2>/dev/null)"
                read -ep "是否覆盖重装? (y/n, 默认n): " dkredo
                [[ "$dkredo" =~ ^[Yy]$ ]] || { _yellow "已取消"; return 0; }
            fi
            runthirdscript SuperManito/LinuxMirrors/main/DockerInstallation.sh
            check_and_install docker-compose
            echo
            if command -v docker &>/dev/null; then
                _green "docker 安装完成: $(docker --version 2>/dev/null)"
            else
                _red "未检测到 docker，安装可能失败，请检查上面的输出"
            fi
        }

        # docker换源
        softdocker_mirror() {
            _blue "调用 linuxmirrors.cn 换源脚本 ..."
            if command -v curl &>/dev/null; then
                bash <(curl -sSL https://linuxmirrors.cn/docker.sh)
            elif command -v wget &>/dev/null; then
                local tmp="/tmp/.s_dockermirror.$$"
                if wget -qO "$tmp" https://linuxmirrors.cn/docker.sh && [[ -s "$tmp" ]]; then
                    bash "$tmp"
                    rm -f "$tmp"
                else
                    rm -f "$tmp"
                    _red "换源脚本下载失败，请检查网络"
                    return 1
                fi
            else
                _red "未找到 curl 或 wget，无法执行换源脚本"
                return 1
            fi
        }

        # docker修复
        softdocker_repair() {
            _blue "=== docker 修复 ==="
            if ! command -v docker &>/dev/null; then
                _red "未检测到 docker 命令，请先安装"
                return 1
            fi

            _blue "1. 校验 /etc/docker/daemon.json"
            if [[ -s /etc/docker/daemon.json ]]; then
                if command -v python3 &>/dev/null && ! python3 -c "import json;json.load(open('/etc/docker/daemon.json'))" 2>/dev/null; then
                    local bk="/etc/docker/daemon.json.broken.$(date +%y%m%d%H%M%S)"
                    mv -f /etc/docker/daemon.json "$bk"
                    _red "daemon.json 不是合法 JSON，已备份到 $bk 并移除"
                elif command -v jq &>/dev/null && ! jq empty /etc/docker/daemon.json 2>/dev/null; then
                    local bk="/etc/docker/daemon.json.broken.$(date +%y%m%d%H%M%S)"
                    mv -f /etc/docker/daemon.json "$bk"
                    _red "daemon.json 不是合法 JSON，已备份到 $bk 并移除"
                else
                    _green "daemon.json 格式正常"
                fi
            else
                _yellow "daemon.json 不存在，跳过"
            fi

            _blue "2. 重载并重启服务"
            systemctl daemon-reload 2>/dev/null
            systemctl reset-failed docker 2>/dev/null
            systemctl start docker 2>/dev/null
            systemctl restart docker 2>/dev/null

            _blue "3. 结果"
            local st
            st=$(systemctl is-active docker 2>/dev/null)
            if [[ "$st" == "active" ]]; then
                _green "docker 服务运行中"
                docker info --format '{{.ServerVersion}}' 2>/dev/null | sed 's/^/    ServerVersion: /'
            else
                _red "docker 服务状态: $st"
                _yellow "最近日志:"
                journalctl -u docker -n 15 --no-pager 2>/dev/null
            fi
        }

        # docker 卸载公共步骤
        _dk_stop_services() {
            _blue "停止 docker 相关服务 ..."
            systemctl stop docker.socket 2>/dev/null || true
            systemctl stop docker.service 2>/dev/null || true
            systemctl stop containerd.service 2>/dev/null || true
            systemctl disable docker.socket 2>/dev/null || true
            systemctl disable docker.service 2>/dev/null || true
            systemctl disable containerd.service 2>/dev/null || true
            pkill -9 -x dockerd 2>/dev/null || true
            pkill -9 -x containerd 2>/dev/null || true
            pkill -9 -x containerd-shim 2>/dev/null || true
            pkill -9 -x docker-proxy 2>/dev/null || true
            pkill -9 -x runc 2>/dev/null || true
            sleep 1
        }

        # 清空容器/卷/网络/镜像（仅彻底卸载时调用）
        _dk_remove_data_objects() {
            command -v docker >/dev/null 2>&1 || return 0
            local ids
            ids=$(docker ps -aq 2>/dev/null)
            if [[ -n "$ids" ]]; then
                _blue "删除全部容器 ..."
                docker rm -f $ids >/dev/null 2>&1 || true
            fi
            ids=$(docker volume ls -q 2>/dev/null)
            if [[ -n "$ids" ]]; then
                _blue "删除全部数据卷 ..."
                docker volume rm -f $ids >/dev/null 2>&1 || true
            fi
            ids=$(docker network ls --format '{{.Name}}' 2>/dev/null | grep -vE '^(bridge|host|none)$')
            if [[ -n "$ids" ]]; then
                _blue "删除自定义网络 ..."
                docker network rm $ids >/dev/null 2>&1 || true
            fi
            ids=$(docker images -aq 2>/dev/null)
            if [[ -n "$ids" ]]; then
                _blue "删除全部镜像 ..."
                docker rmi -f $ids >/dev/null 2>&1 || true
            fi
        }

        # 移除 apt 管理的 docker 软件包（只对真实存在的包名执行，避免整条命令失败）
        _dk_purge_packages() {
            local pkgs=() p
            for p in docker-ce docker-ce-cli docker-ce-rootless-extras docker-compose-plugin \
                     docker-buildx-plugin docker-scan-plugin docker.io docker-doc \
                     docker-compose docker-engine docker-ce-rootless podman-docker \
                     containerd containerd.io runc; do
                dpkg -s "$p" >/dev/null 2>&1 && pkgs+=("$p")
            done
            while read -r p; do
                [[ -n "$p" ]] || continue
                case " ${pkgs[*]} " in
                    *" $p "*) ;;
                    *) pkgs+=("$p") ;;
                esac
            done < <(dpkg-query -W -f='${Package}\n' 2>/dev/null | grep -E '^(docker|containerd|podman-docker)' || true)

            if [[ ${#pkgs[@]} -eq 0 ]]; then
                _yellow "未发现 apt 管理的 docker 相关软件包"
                return 0
            fi
            _blue "卸载软件包: ${pkgs[*]}"
            if ! apt-get purge -y "${pkgs[@]}"; then
                _red "整批卸载失败，改为逐个卸载 ..."
                for p in "${pkgs[@]}"; do
                    apt-get purge -y "$p" || _red "卸载 $p 失败"
                done
            fi
            apt-get autoremove -y >/dev/null 2>&1 || true
            apt-get autoclean >/dev/null 2>&1 || true
        }

        # 移除 snap 版 docker
        _dk_remove_snap() {
            command -v snap >/dev/null 2>&1 || return 0
            if snap list 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx 'docker'; then
                _blue "移除 snap 版 docker ..."
                snap remove docker 2>/dev/null || _red "snap remove docker 失败"
            fi
        }

        # 卸载 docker（保留镜像/容器/数据卷/配置）
        softdocker_uninstall_keepdata() {
            echo
            _yellow "模式一：仅卸载 docker 程序，保留镜像、容器、数据卷与配置"
            _yellow "保留: /var/lib/docker  /var/lib/containerd  /etc/docker"
            read -ep "确认卸载? (y/n, 默认n): " dkrm1
            [[ "$dkrm1" =~ ^[Yy]$ ]] || { _yellow "已取消"; return 0; }

            _dk_stop_services
            _dk_remove_snap
            _dk_purge_packages

            rm -rf /etc/systemd/system/docker.service.d
            rm -f /etc/systemd/system/docker.service /etc/systemd/system/docker.socket
            rm -f /usr/lib/systemd/system/docker.service /usr/lib/systemd/system/docker.socket
            rm -f /lib/systemd/system/docker.service /lib/systemd/system/docker.socket
            systemctl daemon-reload 2>/dev/null || true
            systemctl reset-failed 2>/dev/null || true
            hash -r

            echo
            _blue "=== 结果 ==="
            if command -v docker >/dev/null 2>&1; then
                _red "docker 命令仍存在: $(command -v docker)"
            else
                _green "docker 程序已卸载"
            fi
            if [[ -d /var/lib/docker ]]; then
                _green "已保留: /var/lib/docker ($(du -sh /var/lib/docker 2>/dev/null | awk '{print $1}'))"
            fi
            if [[ -d /var/lib/containerd ]]; then
                _green "已保留: /var/lib/containerd ($(du -sh /var/lib/containerd 2>/dev/null | awk '{print $1}'))"
            fi
            if [[ -d /etc/docker ]]; then
                _green "已保留: /etc/docker"
            fi
            _yellow "以后重新安装 docker，原有镜像与容器可直接复用"
        }

        # 彻底卸载 docker（删除一切相关文件）
        softdocker_uninstall_all() {
            echo
            _red "模式二：彻底删除 docker，包括镜像、容器、数据卷、网络、配置与 apt 源"
            _red "此操作不可恢复！"
            read -ep "确认彻底删除? 输入 yes 继续: " dkrm2
            [[ "$dkrm2" == "yes" ]] || { _yellow "已取消"; return 0; }

            _dk_remove_data_objects
            _dk_stop_services
            _dk_remove_snap
            _dk_purge_packages

            _blue "删除目录与配置 ..."
            rm -rf /var/lib/docker /var/lib/containerd /var/lib/dockershim
            rm -rf /etc/docker /etc/containerd
            rm -rf /run/docker /run/containerd
            rm -f /run/docker.sock /var/run/docker.sock
            rm -rf /var/log/docker /var/log/containerd /var/log/pods
            rm -f /var/log/docker.log
            rm -rf /usr/libexec/docker /usr/libexec/docker-cli-plugins
            rm -rf /usr/lib/docker /usr/local/lib/docker
            rm -rf /etc/systemd/system/docker.service.d
            rm -f /etc/systemd/system/docker.service /etc/systemd/system/docker.socket
            rm -f /usr/lib/systemd/system/docker.service /usr/lib/systemd/system/docker.socket
            rm -f /lib/systemd/system/docker.service /lib/systemd/system/docker.socket
            rm -rf /var/snap/docker /snap/docker

            _blue "清理 apt 源与密钥 ..."
            rm -f /etc/apt/sources.list.d/docker.list /etc/apt/sources.list.d/docker.list.save
            rm -rf /etc/apt/sources.list.d/docker.list.d
            rm -f /etc/apt/keyrings/docker.gpg /etc/apt/keyrings/docker.asc
            rm -f /usr/share/keyrings/docker-archive-keyring.gpg /usr/share/keyrings/docker.gpg
            rm -f /etc/apt/trusted.gpg.d/docker.gpg /etc/apt/trusted.gpg.d/docker-archive-keyring.gpg

            _blue "清理 iptables 残留链 ..."
            local t
            for t in filter nat; do
                iptables -t "$t" -F DOCKER 2>/dev/null || true
                iptables -t "$t" -X DOCKER 2>/dev/null || true
                iptables -t "$t" -F DOCKER-USER 2>/dev/null || true
                iptables -t "$t" -X DOCKER-USER 2>/dev/null || true
                iptables -t "$t" -F DOCKER-ISOLATION-STAGE-1 2>/dev/null || true
                iptables -t "$t" -X DOCKER-ISOLATION-STAGE-1 2>/dev/null || true
                iptables -t "$t" -F DOCKER-ISOLATION-STAGE-2 2>/dev/null || true
                iptables -t "$t" -X DOCKER-ISOLATION-STAGE-2 2>/dev/null || true
                iptables -t "$t" -F DOCKER-ISOLATION 2>/dev/null || true
                iptables -t "$t" -X DOCKER-ISOLATION 2>/dev/null || true
            done

            _blue "删除 docker 用户组 ..."
            if getent group docker >/dev/null 2>&1; then
                groupdel docker 2>/dev/null || _yellow "docker 组仍在使用，跳过"
            fi

            systemctl daemon-reload 2>/dev/null || true
            systemctl reset-failed 2>/dev/null || true
            hash -r

            echo
            _blue "=== 残留检查 ==="
            local left=0 d svc
            for d in docker dockerd docker-compose containerd runc; do
                if command -v "$d" >/dev/null 2>&1; then
                    _red "命令仍在: $d -> $(command -v "$d")"
                    left=1
                fi
            done
            for d in /var/lib/docker /var/lib/containerd /etc/docker /run/docker \
                     /var/run/docker.sock /etc/apt/sources.list.d/docker.list; do
                if [[ -e "$d" ]]; then
                    _red "残留: $d"
                    left=1
                fi
            done
            for svc in docker.service docker.socket containerd.service; do
                if systemctl list-unit-files "$svc" 2>/dev/null | grep -q "^$svc"; then
                    _red "残留服务单元: $svc"
                    left=1
                fi
            done
            if [[ $left -eq 0 ]]; then
                _green "未发现残留，docker 已彻底移除"
            else
                _yellow "以上项目仍然存在，可按提示手动清理"
            fi
        }
        menuname='首页/软件/docker'
        options=("安装docker" softdocker_install "换源" softdocker_mirror "修复" softdocker_repair "卸载docker(保留数据)" softdocker_uninstall_keepdata "彻底删除docker" softdocker_uninstall_all)
        menu "${options[@]}"
    }

    cputest() {
        echo "检查安装 stress 和 sysbench"
        check_and_install stress sysbench
        
        echo "==== CPU 稳定性测试 (stress) ===="
        echo "持续满载60秒，用于温度与系统稳定性检查"
        stress -c "$(nproc)" -t 60
        
        echo "==== CPU 性能基准测试 (sysbench) ===="
        sysbench cpu --cpu-max-prime=20000 run
    }
    
    
    FastBenchfun() {
        runthirdscript sshpc/FastBench/main/FastBench.sh
    }
    
    ecstest() {
        runthirdscript spiritLHLS/ecs/main/ecs.sh
    }
    mysqlBenchfun(){
        runthirdscript sshpc/mysql-bench/main/mysql-bench.sh
    }
    
    installvasma() {
        runthirdscript mack-a/v2ray-agent/master/install.sh || return 1
        if command -v vasma >/dev/null 2>&1; then
            vasma
        else
            _yellow "未找到 vasma 命令，请按脚本提示手动执行 /etc/v2ray-agent/install.sh"
        fi
    }
    
    install3xui() {
        runthirdscript mhsanaei/3x-ui/master/install.sh
    }
    
    installopenvpn() {
        _blue '即将下载sh脚本,安装后记得修改/etc/openvpn/client-template.txt 文件路由规则'
        waitinput
        runthirdscript angristan/openvpn-install/master/openvpn-install.sh
    }
    
    installaapanel() {
        URL=https://www.aapanel.com/script/install_7.0_en.sh && if [ -f /usr/bin/curl ];then curl -ksSO "$URL" ;else wget --no-check-certificate -O install_7.0_en.sh "$URL";fi;bash install_7.0_en.sh
    }
    
    installrustdeskserver() {
        runthirdscript sshpc/rustdesktool/main/rustdesktool.sh
    }

    pvetoolsfun() {
        runthirdscript ivanhao/pvetools/master/pvetools.sh
    }

    hping3fun() {
        runthirdscript sshpc/trident/main/run.sh
    }
    lsyncdshelltoolfun(){
        runthirdscript sshpc/lsyncd-shell-tool/main/lsyncdtool.sh
    }
        
    
    menuname='首页/软件'
    echo "softwarefun" >$installdir/config/lastfun
    options=("aptupdate软件更新" aptupdatefun "修复更新" configureaptfun "换软件源" changemirrors "snap管理" snapfun "软件卸载" removefun "docker管理" softdockerfun "安装常用包" installcomso "安装smbd" smbdinstall "安装vasma八合一" installvasma "安装3x-ui" install3xui "安装openvpn" installopenvpn "安装aapanel" installaapanel "安装RustDesk-Server" installrustdeskserver "cpu测试" cputest  "小白机器跑分" FastBenchfun "融合怪测试" ecstest "mysql跑分测试" mysqlBenchfun "pvetools脚本" pvetoolsfun "基于hping3网络攻击脚本" hping3fun "基于lsyncd文件实时同步" lsyncdshelltoolfun)
    menu "${options[@]}"
    
}
