softwarefun() {
    beforeMenu(){
        _blue "> ---  当前目录: [ $(pwd) ] ---- < v:${branch}-$selfversion"
        echo
        _yellow "当前菜单: $menuname "
        echo
    }
    
    #下载并执行sh #参数 例: 'vaxilu/x-ui/master/install.sh'
    runthirdscript() {
        local url="$1"
        local param="$2"
        local outputdir="$HOME/thirdscript"
        local timeout=3
        local filename=$(basename "$url")

        mkdir -p "$outputdir"

        local filepath="$outputdir/$filename"
        if [[ -s "$filepath" ]]; then
            bash "$filepath"
            return 0
        fi

        for base in "${proxylinks[@]}"; do
            _yellow "尝试从 ${base}/$url 下载..."
            if wget -q -N -P "$outputdir" --timeout="$timeout" "${base}/$url"; then
                if [[ -s "$outputdir/$filename" ]]; then
                    _green "已下载文件：$filename"
                    chmod +x "$outputdir/$filename"
                    bash "$outputdir/$filename" "$param"
                    return 0
                else
                    _red "文件为空或下载失败：$filename"
                fi
            else
                _red "下载失败：${base}/$url"
            fi
        done

        _red "所有源均下载失败，退出。"
        return 1
    }

    
    #更新所有已安装的软件包
    aptupdatefun() {
        dpkg --configure -a
        if [[ -n $(pgrep -f "apt|apt-get") ]]; then
            _yellow "→ 终止占用apt的进程..."
            pgrep -f "apt|apt-get" | xargs kill -9 2>/dev/null
        fi
        _blue "→ 正在更新软件包列表（apt update）..."
        apt-get update -y
        _blue "→ 是否升级所有已安装软件包（apt upgrade）？"
        read -p "输入 y 确认升级，不升级直接回车：" -n 1 -r -t 7 choice

        if [[ $choice =~ ^[Yy]$ ]]; then
            echo
            _blue "→ 开始升级软件包（过程可能较长）..."
            apt-get upgrade -y
        else
            _blue "跳过升级"
        fi
        _blue "更新完成"
    }
    #修复更新
    configureaptfun() {
        _red '注意这将结束apt|dpkg的全部进程！'
        waitinput
        _blue '修复更新..'
        pkill -9 -f 'apt|dpkg'
        rm -f /var/lib/dpkg/lock-frontend \
               /var/lib/dpkg/lock \
               /var/lib/apt/lists/lock \
               /var/cache/apt/archives/lock
        dpkg --configure -a
        apt-get install -f -y
        apt-get update -y
        apt autoremove --purge -y
        apt autoclean -y
        apt clean -y
        _green '修复完成'
    }
    #安装常用包
    installcomso() {
        check_and_install wget curl jq net-tools vim openssh-server git zip htop gdu
        echo "所有包都已安装完成"
    }
    
    smbdinstall(){
        _red '注意安装后默认会直接开放home目录匿名可读写访问'
        waitinput
        # 检查是否已安装samba
        check_and_install samba 
        
        # 备份原配置，文件名带日期时间，避免重复覆盖
        backup_time=$(date +"%Y%m%d_%H%M%S")
        cp /etc/samba/smb.conf /etc/samba/smb.conf.bak.$backup_time
        
        # 添加/home匿名共享配置
        echo "" >> /etc/samba/smb.conf
        echo "[home]" >> /etc/samba/smb.conf
        echo "   path = /home" >> /etc/samba/smb.conf
        echo "   browseable = yes" >> /etc/samba/smb.conf
        echo "   writable = yes" >> /etc/samba/smb.conf
        echo "   guest ok = yes" >> /etc/samba/smb.conf
        echo "   force user = root" >> /etc/samba/smb.conf
        echo "   force group = root" >> /etc/samba/smb.conf
        
        # 重启samba服务
        systemctl restart smbd
        systemctl restart nmbd
        
        _blue "samba 安装并配置完成，/home 目录可匿名读写，权限为 root。"
    }
    
    #换源
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
            
            mv /etc/apt/sources.list.bak "/etc/apt/sources.list.bak.$datevar"
            echo "sources.list.bak 已重命名为 /etc/apt/sources.list.bak.$datevar"
            
        fi
        
    }
    
    removefun() {
        #专项卸载
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
            apt-get autoremove mysql* --purge -y
            masterremove mysql-server
        }
        #彻底卸载
        masterremove() {
            if [ $# -eq 0 ]; then
                read -ep "请输入要卸载的软件名: " resoftname
            else
                resoftname=$1
            fi
            _red "注意：将会删除关于 $resoftname 所有内容"
            waitinput
            _red "开始卸载 $resoftname"
            echo "关闭服务.."
            service $resoftname stop
            systemctl stop $resoftname
            apt remove $resoftname -y
            apt-get --purge remove $resoftname -y
            apt-get --purge remove $resoftname-* -y
            echo "清除dept列表"
            apt purge $(dpkg -l | grep $resoftname | awk '{print $2}' | tr "\n" " ")
            echo "删除 $resoftname 的启动脚本"
            update-rc.d -f $resoftname remove
            echo "删除所有包含 $resoftname 的文件"
            rm -rf /etc/$resoftname
            rm -rf /etc/init.d/$resoftname
            find /etc -name *$resoftname* -print0 | xargs -0 rm -rf
            rm -rf /usr/bin/$resoftname
            rm -rf /var/log/$resoftname
            rm -rf /lib/systemd/system/$resoftname.service
            rm -rf /var/lib/$resoftname
            rm -rf /run/$resoftname
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
            _blue "> ---  当前目录: [ $(pwd) ] ---- < v:${branch}-$selfversion"
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
            _blue "> ---  当前目录: [ $(pwd) ] ---- < v:${branch}-$selfversion"
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

        #安装docker
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

        #docker换源
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

        #docker修复
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

        #---------------- docker 卸载公共步骤 ----------------
        # 停止服务并杀掉残留进程
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
                # shellcheck disable=SC2086
                docker rm -f $ids >/dev/null 2>&1 || true
            fi
            ids=$(docker volume ls -q 2>/dev/null)
            if [[ -n "$ids" ]]; then
                _blue "删除全部数据卷 ..."
                # shellcheck disable=SC2086
                docker volume rm -f $ids >/dev/null 2>&1 || true
            fi
            ids=$(docker network ls --format '{{.Name}}' 2>/dev/null | grep -vE '^(bridge|host|none)$')
            if [[ -n "$ids" ]]; then
                _blue "删除自定义网络 ..."
                # shellcheck disable=SC2086
                docker network rm $ids >/dev/null 2>&1 || true
            fi
            ids=$(docker images -aq 2>/dev/null)
            if [[ -n "$ids" ]]; then
                _blue "删除全部镜像 ..."
                # shellcheck disable=SC2086
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
        runthirdscript mack-a/v2ray-agent/master/install.sh
        vasma
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
