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
                    bash "$outputdir/$filename"
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
        _blue "更新所有软件包"
        dpkg --configure -a
        if [[ -n $(pgrep -f "apt") ]]; then
            pgrep -f apt | xargs kill -9
        fi
        apt-get update -y && apt-get install curl -y
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
        check_and_install wget curl net-tools vim openssh-server git zip htop gdu
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
            bash <(curl -sSL https://linuxmirrors.cn/main.sh)
        }
        overseas() {
            bash <(curl -sSL https://raw.githubusercontent.com/SuperManito/LinuxMirrors/main/ChangeMirrors.sh) --abroad
        }
        
        menuname='首页/软件/换源'
        options=("大陆" cnmainland "海外" overseas)
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
        removedocker() {
            docker kill $(docker ps -a -q)
            docker rm $(docker ps -a -q)
            docker rmi $(docker images -q)
            apt-get autoremove docker docker-ce docker-engine docker.io containerd runc
            apt-get autoremove docker-ce-*
            rm -rf /etc/systemd/system/docker.service.d
            rm -rf /var/lib/docker
            rm -rf /etc/docker
            rm -rf /run/docker
            rm -rf /var/lib/dockershim
            umount /var/lib/docker/devicemapper
            masterremove docker
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
        options=("手动输入" masterremove "卸载nginx" removenginx "卸载Apache" removeapache "卸载php" removephp "卸载docker" removedocker "卸载v2ray" removev2 "卸载mysql" removemysql)
        menu "${options[@]}"
    }
    
    installbtop() {
        check_and_install snap snapd
        snap install btop
        btop
    }
    
    snapfun() {
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
        
        installsnapfun() {
            check_and_install snap snapd
        }
        
        menuname='首页/软件/snap管理'
        options=("查看 snap 状态" snapls "安装" installsnapfun)
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
    
    dockersnapinstall() {
        check_and_install snap snapd
        snap install docker
    }
    
    dockerinstall() {
        runthirdscript https://gitee.com/SuperManito/LinuxMirrors/raw/main/DockerInstallation.sh
        check_and_install docker-compose 
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
        runthirdscript oneclickvirt/pve/main/scripts/build_backend.sh
    }

    hping3fun() {
        runthirdscript sshpc/trident/main/run.sh
    }
    lsyncdshelltoolfun(){
        runthirdscript sshpc/lsyncd-shell-tool/main/lsyncdtool.sh
    }
        
    
    menuname='首页/软件'
    echo "softwarefun" >$installdir/config/lastfun
    options=("aptupdate软件更新" aptupdatefun "修复更新" configureaptfun "换软件源" changemirrors "snap管理" snapfun "软件卸载" removefun "安装常用包" installcomso "安装smbd" smbdinstall 安装docker dockerinstall "安装snap版docker" dockersnapinstall "安装btop" installbtop "安装vasma八合一" installvasma "安装3x-ui" install3xui "安装openvpn" installopenvpn "安装aapanel" installaapanel "安装RustDesk-Server" installrustdeskserver "cpu测试" cputest  "小白机器跑分" FastBenchfun "融合怪测试" ecstest "mysql跑分测试" mysqlBenchfun "pvetools脚本" pvetoolsfun "基于hping3网络攻击脚本" hping3fun "基于lsyncd文件实时同步" lsyncdshelltoolfun)
    menu "${options[@]}"
    
}
