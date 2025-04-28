softwarefun() {

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

        sudo killall apt apt-get
        sudo rm /var/cache/apt/archives/lock
        sudo rm /var/lib/dpkg/lock*
        sudo rm /var/lib/apt/lists/lock
        sudo dpkg --configure -a
        sudo apt update
    }
    #安装常用包
    installcomso() {
        echo "开始安装.."
        install_package() {
            package_name=$1
            echo "开始安装 $package_name"
            apt install $package_name -y
            echo "$package_name 安装完成"
        }
        packages=(
            "wget"
            "curl"
            "net-tools"
            "vim"
            "openssh-server"
            "git"
            "zip"
            "htop"
        )
        for package in "${packages[@]}"; do
            package_name="${package%:*}"
            install_package "$package_name"
        done
        echo "所有包都已安装完成"
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
    #安装xray八合一
    installbaheyi() {
        wget -P /root -N --no-check-certificate "https://raw.githubusercontent.com/mack-a/v2ray-agent/master/install.sh" && chmod 700 /root/install.sh && /root/install.sh
        vasma
    }

    #安装xui
    installxui() {
        bash <(curl -Ls https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh)
    }
    #安装openvpn
    installopenvpn() {
        _blue '即将下载sh脚本到当前目录,安装后记得修改/etc/openvpn/client-template.txt 文件路由规则'
        waitinput
        curl -O https://raw.githubusercontent.com/angristan/openvpn-install/master/openvpn-install.sh && chmod +x openvpn-install.sh && ./openvpn-install.sh
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
        apt install snap -y
        apt install snapd -y
        snap install btop
        btop
    }

    installaapanel() {
        local URL=https://www.aapanel.com/script/install_6.0_en.sh && if [ -f /usr/bin/curl ]; then curl -ksSO "$URL"; else wget --no-check-certificate -O install_6.0_en.sh "$URL"; fi
        bash install_6.0_en.sh aapanel
    }

    installrustdeskserver() {
        wget -N http://raw.githubusercontent.com/sshpc/rustdesktool/main/rustdesktool.sh && chmod +x ./rustdesktool.sh && ./rustdesktool.sh
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
            apt install snap -y
            apt install snapd -y
        }

        menuname='首页/软件/snap管理'
        options=("查看 snap 状态" snapls "安装" installsnapfun)
        menu "${options[@]}"
    }

    dockersnapinstall() {
        apt install snap snapd
        snap install docker
    }

    dockerinstall() {
        bash <(curl -sSL https://gitee.com/SuperManito/LinuxMirrors/raw/main/DockerInstallation.sh)
        apt install docker-compose -y
    }

    menuname='首页/软件'
    echo "software" >$installdir/config/lastfun
    options=("aptupdate软件更新" aptupdatefun "修复更新" configureaptfun "换软件源" changemirrors "snap管理" snapfun "软件卸载" removefun "安装常用包" installcomso 安装docker dockerinstall "安装snap版docker" dockersnapinstall "安装btop" installbtop "安装八合一" installbaheyi "安装xui" installxui "安装openvpn" installopenvpn "安装aapanel" installaapanel "安装RustDesk-Server" installrustdeskserver)
    menu "${options[@]}"

}
