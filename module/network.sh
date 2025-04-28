networkfun() {
    

#获取网卡
    getnetcard() {
        # 获取系统中可用的网卡名称
        interfaces=$(ifconfig -a | sed -nE 's/^([^[:space:]]+).*$/\1/p')

        # 输出供用户选择的网卡名称列表
        PS3="请选择网卡名称： "
        select interface in $interfaces; do
            if [[ -n "$interface" ]]; then
                break
            fi
        done
        # 去掉网卡名称后面的冒号，并输出用户选择的网卡名称
        interface=$(echo "$interface" | sed 's/://')
        echo $interface
    }


    
    #ufw防火墙
    ufwfun() {
        ufwopen() {

            if _exists 'ufw'; then
                echo "ufw 已安装"
            else
                echo "ufw 未安装,正在安装..."
                apt install ufw -y
                echo "ufw 已安装"
            fi

            echo "请输入y以开启ufw"
            ufw enable
            echo "ufw已开启"
        }

        ufwdefault() {
            ufw allow 22
            echo "已配置允许 22 端口"
            ufw default deny
            echo "拒绝全部传入"
            ufwstatus
        }

        ufwadd() {
            read -ep "请输入端口号 (0-65535): " port
            until [[ -n "$port" || "$port" =~ ^[0-9]+$ && "$port" -le 65535 ]]; do
                echo "$port: 无效端口."
                read -ep "请输入端口号 (0-65535): " port
            done
            ufw allow $port
            echo "端口 $port 已放行"
            ufwstatus
        }
        ufwstatus() {
            ufw status verbose
            echo "提示:inactive 关闭状态 , active 开启状态"
        }
        ufwclose() {
            read -ep "请输入端口号 (0-65535): " unport
            until [[ -n "$unport" || "$unport" =~ ^[0-9]+$ && "$unport" -le 65535 ]]; do
                echo "$unport: 无效端口."
                read -ep "请输入端口号 (0-65535): " unport
            done
            ufw delete allow $unport
            echo "端口 $unport 已关闭"
            ufwstatus
        }
        ufwdisablefun() {
            ufw disable
            echo "ufw已关闭"
            ufwstatus
        }

        ufwlogtail() {
            tail -f /var/log/ufw.log
        }

        setufwfromip() {

            # 函数：允许特定 IP 和端口的入站流量
            allow_ip_port() {

                read -ep "请输入ip: " ip
                read -ep "请输入端口号 (0-65535): " unport
                until [[ -n "$unport" || "$unport" =~ ^[0-9]+$ && "$unport" -le 65535 ]]; do
                    echo "$unport: 无效端口."
                    read -ep "请输入端口号 (0-65535): " unport
                done

                echo "ip:$ip  端口:$unport"
                waitinput
                ufw allow from $ip to any port $unport

                _blue 'ok'

                ufwstatus

            }

            # 函数：拒绝特定 IP 和端口的入站流量
            deny_ip_port() {
                read -ep "请输入ip: " ip
                read -ep "请输入端口号 (0-65535): " unport
                until [[ -n "$unport" || "$unport" =~ ^[0-9]+$ && "$unport" -le 65535 ]]; do
                    echo "$unport: 无效端口."
                    read -ep "请输入端口号 (0-65535): " unport
                done

                echo "ip:$ip  端口:$unport"
                waitinput

                ufw deny from $ip to any port $unport

                _blue 'ok'

                ufwstatus
            }

            menuname='首页/网络/ufw/特定ip操作'
            options=("允许特定IP和端口的入站流量" allow_ip_port "拒绝特定IP和端口的入站流量" deny_ip_port)
            menu "${options[@]}"
        }

        menuname='首页/网络/ufw'
        options=("开启ufw" ufwopen "关闭ufw" ufwdisablefun "ufw默认配置仅ssh" ufwdefault "ufw状态" ufwstatus "查看实时日志" ufwlogtail "添加端口" ufwadd "关闭端口" ufwclose "对特定ip操作" setufwfromip)
        menu "${options[@]}"

    }

    fail2banfun() {
        fail2banstatusfun() {
            fail2ban-client status sshd
        }

        installfail2ban() {
            echo "检查并安装fail2ban"
            apt install fail2ban -y
            echo "fail2ban 已安装"
            echo "开始配置fail2ban"
            waitinput
            read -ep "请输入尝试次数 (直接回车默认4次): " retry
            read -ep "请输入拦截后禁止访问的时间 (直接回车默认604800s): " timeban
            if [[ "$retry" = "" ]]; then
                retry=4
            fi
            if [[ "$timeban" = "" ]]; then
                timeban=604800
            fi
            rm /etc/fail2ban/jail.d/sshd.local
            echo "[ssh-iptables]" >>/etc/fail2ban/jail.d/sshd.local
            echo "enabled  = true" >>/etc/fail2ban/jail.d/sshd.local
            echo "filter   = sshd" >>/etc/fail2ban/jail.d/sshd.local
            echo "action   = iptables[name=SSH, port=ssh, protocol=tcp]" >>/etc/fail2ban/jail.d/sshd.local
            echo "logpath  = /var/log/auth.log" >>/etc/fail2ban/jail.d/sshd.local
            echo "maxretry = $retry" >>/etc/fail2ban/jail.d/sshd.local
            echo "bantime  = $timeban" >>/etc/fail2ban/jail.d/sshd.local
            service fail2ban start
            echo "服务已开启"
            echo
            echo "----服务状态----"
            fail2banstatusfun
        }

        menuname='首页/网络/fail2ban'
        options=("安装配置sshd" installfail2ban "查看状态" fail2banstatusfun)
        menu "${options[@]}"

    }
    
    #iperf3打流
    iperftest() {

        if _exists 'iperf3'; then
            echo "iperf3 已安装"
        else
            echo "iperf3 未安装,正在安装..."
            apt install iperf3 -y
        fi

        iperf3client() {

            until [[ "$serversip" ]]; do
                read -ep "请输入服务器ip: " serversip
            done
            _blue '默认udp  手动执行'
            next
            _yellow "iperf3 -u -c $serversip -b 2000M -t 40"
            next
            iperf3 -u -c $serversip -b 2000M -t 40
        }

        echo "请选择运行模式  1.服务端  2.客户端"
        until [[ $PROTOCOL_CHOICE =~ ^[1-2]$ ]]; do
            read -rp "Protocol [1-2]: " PROTOCOL_CHOICE
        done
        case $PROTOCOL_CHOICE in
        1)
            _blue '端口为 5201 请放行端口'
            iperf3 -s
            ;;
        2)
            iperf3client
            ;;
        esac
    }
    #nmap扫描
    nmapfun() {

        if _exists 'nmap'; then
            echo "nmap 已安装"

        else
            echo "nmap 未安装,正在安装..."
            apt install nmap -y
        fi

        nmapdetection() {
            echo '本地网络：'
            ip addr show | grep "inet " | grep -v "127.0.0.1"
            echo

            until [[ -n "$ips" ]]; do
                read -ep "请输入网段x.x.x.x/x: " ips
            done

            nmap -sP $ips
        }
        nmapportcat() {

            read -ep "请输入ip: " ip
            read -ep "请输入端口(1-65535): " port
            nmap "$ip" -p "$port" -Pn
        }

        echo "1.主机探测  2.端口扫描"
        until [[ $PROTOCOL_CHOICE =~ ^[1-2]$ ]]; do
            read -rp "Protocol [1-2]: " PROTOCOL_CHOICE
        done
        case $PROTOCOL_CHOICE in
        1)
            _blue '扫描网段中有哪些主机在线，本质上是Ping扫描'
            nmapdetection
            ;;
        2)
            _blue '示例 nmap ip -p 1-2000 -Pn'
            nmapportcat
            ;;
        esac
    }
    
    #外网测速
    publicnettest() {

        netfast() {
            apt install speedtest-cli -y
            echo "开始测速"
            speedtest-cli
            echo "测速完成"
        }

        #SpeedCLI 测速
        netfast2() {
            echo "开始测速"
            curl -fsSL git.io/speedtest-cli.sh | sudo bash
            speedtest
            echo "测速完成"
        }
        #三网测速
        sanwang() {
            bash <(curl -Lso- https://down.wangchao.info/sh/superspeed.sh)
        }
        #多地区测速
        netfast3() {

            if [ ! -e "./speedtest-cli/speedtest" ]; then
                sys_bit=""
                local sysarch
                sysarch="$(uname -m)"
                if [ "${sysarch}" = "unknown" ] || [ "${sysarch}" = "" ]; then
                    sysarch="$(arch)"
                fi
                if [ "${sysarch}" = "x86_64" ]; then
                    sys_bit="x86_64"
                fi
                if [ "${sysarch}" = "i386" ] || [ "${sysarch}" = "i686" ]; then
                    sys_bit="i386"
                fi
                if [ "${sysarch}" = "armv8" ] || [ "${sysarch}" = "armv8l" ] || [ "${sysarch}" = "aarch64" ] || [ "${sysarch}" = "arm64" ]; then
                    sys_bit="aarch64"
                fi
                if [ "${sysarch}" = "armv7" ] || [ "${sysarch}" = "armv7l" ]; then
                    sys_bit="armhf"
                fi
                if [ "${sysarch}" = "armv6" ]; then
                    sys_bit="armel"
                fi
                [ -z "${sys_bit}" ] && _red "Error: Unsupported system architecture (${sysarch}).\n" && exit 1
                url1="https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-${sys_bit}.tgz"
                url2="https://dl.lamp.sh/files/ookla-speedtest-1.2.0-linux-${sys_bit}.tgz"
                if ! wget --no-check-certificate -q -T10 -O speedtest.tgz ${url1}; then
                    if ! wget --no-check-certificate -q -T10 -O speedtest.tgz ${url2}; then
                        _red "Error: Failed to download speedtest-cli.\n" && exit 1
                    fi
                fi
                mkdir -p speedtest-cli && tar zxf speedtest.tgz -C ./speedtest-cli && chmod +x ./speedtest-cli/speedtest
                rm -f speedtest.tgz
            fi
            printf "%-18s%-18s%-20s%-12s\n" " Node Name" "Upload Speed" "Download Speed" "Latency"

            speed_test() {
                local nodeName="$2"
                if [ -z "$1" ]; then
                    ./speedtest-cli/speedtest --progress=no --accept-license --accept-gdpr >./speedtest-cli/speedtest.log 2>&1
                else
                    ./speedtest-cli/speedtest --progress=no --server-id="$1" --accept-license --accept-gdpr >./speedtest-cli/speedtest.log 2>&1
                fi
                if [ $? -eq 0 ]; then
                    local dl_speed up_speed latency
                    dl_speed=$(awk '/Download/{print $3" "$4}' ./speedtest-cli/speedtest.log)
                    up_speed=$(awk '/Upload/{print $3" "$4}' ./speedtest-cli/speedtest.log)
                    latency=$(awk '/Latency/{print $3" "$4}' ./speedtest-cli/speedtest.log)
                    if [[ -n "${dl_speed}" && -n "${up_speed}" && -n "${latency}" ]]; then
                        printf "\033[0;33m%-18s\033[0;32m%-18s\033[0;31m%-20s\033[0;36m%-12s\033[0m\n" " ${nodeName}" "${up_speed}" "${dl_speed}" "${latency}"
                    fi
                fi
            }
            speed_test '' 'Speedtest.net'
            speed_test '21541' 'Los Angeles, US'
            speed_test '43860' 'Dallas, US'
            speed_test '40879' 'Montreal, CA'
            speed_test '24215' 'Paris, FR'
            speed_test '28922' 'Amsterdam, NL'
            speed_test '24447' 'Shanghai, CN'
            speed_test '5530' 'Chongqing, CN'
            speed_test '60572' 'Guangzhou, CN'
            speed_test '32155' 'Hongkong, CN'
            speed_test '23647' 'Mumbai, IN'
            speed_test '13623' 'Singapore, SG'
            speed_test '21569' 'Tokyo, JP'

            rm -rf speedtest-cli

        }

        menuname='首页/网络/外网测速'
        options=("测速1" netfast "测速2-SpeedCLI" netfast2 "多地区测速" netfast3 "三网测速" sanwang)

        menu "${options[@]}"

    }
    #配置局域网ip
    lanfun() {

        staticip() {
            echo "备份原文件/etc/netplan/00-installer-config.yaml"
            cp /etc/netplan/00-installer-config.yaml /etc/netplan/00-installer-config.yaml.bak."$datevar"
            #获取网卡名称
            ens=$(getnetcard)

            until [[ -n "$ipaddresses" ]]; do
                read -ep "请输入ip地址+网络号 (x.x.x.x/x): " ipaddresses
            done
            until [[ -n "$gateway" ]]; do
                read -ep "请输入网关(x.x.x.x): " gateway
            done
            until [[ -n "$nameservers" ]]; do
                read -ep "请输入DNS(x.x.x.x): " nameservers
            done
            _red "请仔细检查配置是否正确!"
            echo "网卡为" $ens
            echo "网络地址为(x.x.x.x/x):$ipaddresses"
            echo "网关为:$gateway"
            echo "DNS地址为:$nameservers "
            waitinput

            cat <<EOM >/etc/netplan/00-installer-config.yaml
# This is the network config written by 'subiquity'
network:
  version: 2
  ethernets:
     $ens:
         dhcp4: no
         addresses: [$ipaddresses]
         gateway4: $gateway
         nameservers:
             addresses: [$nameservers]
EOM
            echo "配置信息成功写入,成功切换ip 、若ssh断开,请使用设置的ip:$ipaddresses 重新登录"
            netplan apply
            echo "ok"
        }
        dhcpip() {
            echo "开始配置DHCP"
            echo "备份原文件/etc/netplan/00-installer-config.yaml"
            cp /etc/netplan/00-installer-config.yaml /etc/netplan/00-installer-config.yaml.bak."$datevar"
            #获取网卡名称
            ens=$(getnetcard)
            _red "请仔细检查配置是否正确!"
            echo "网卡为" $ens
            waitinput
            cat <<EOM >/etc/netplan/00-installer-config.yaml
# This is the network config written by 'subiquity'
network:
  ethernets:
     $ens:
      dhcp4: true
  version: 2
EOM
            echo "配置信息成功写入"
            netplan apply
            echo "ok"
        }

        menuname='首页/网络/配置局域网ip'
        options=("配置静态ip" staticip "配置dhcp" dhcpip)

        menu "${options[@]}"

    }

    #配置临时代理
    http_proxy() {
        _blue '配置后仅当前窗口生效,需手动执行'
        echo 'export http_proxy=http://x.x.x.x:x'
    }

    #系统网络配置优化
    system_best() {
        sed -i '/net.ipv4.tcp_retries2/d' /etc/sysctl.conf
        sed -i '/net.ipv4.tcp_slow_start_after_idle/d' /etc/sysctl.conf
        sed -i '/net.ipv4.tcp_fastopen/d' /etc/sysctl.conf
        sed -i '/fs.file-max/d' /etc/sysctl.conf
        sed -i '/fs.inotify.max_user_instances/d' /etc/sysctl.conf
        sed -i '/net.ipv4.tcp_syncookies/d' /etc/sysctl.conf
        sed -i '/net.ipv4.tcp_fin_timeout/d' /etc/sysctl.conf
        sed -i '/net.ipv4.tcp_tw_reuse/d' /etc/sysctl.conf
        sed -i '/net.ipv4.tcp_max_syn_backlog/d' /etc/sysctl.conf
        sed -i '/net.ipv4.ip_local_port_range/d' /etc/sysctl.conf
        sed -i '/net.ipv4.tcp_max_tw_buckets/d' /etc/sysctl.conf
        sed -i '/net.ipv4.route.gc_timeout/d' /etc/sysctl.conf
        sed -i '/net.ipv4.tcp_synack_retries/d' /etc/sysctl.conf
        sed -i '/net.ipv4.tcp_syn_retries/d' /etc/sysctl.conf
        sed -i '/net.core.somaxconn/d' /etc/sysctl.conf
        sed -i '/net.core.netdev_max_backlog/d' /etc/sysctl.conf
        sed -i '/net.ipv4.tcp_timestamps/d' /etc/sysctl.conf
        sed -i '/net.ipv4.tcp_max_orphans/d' /etc/sysctl.conf
        sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf

        echo "net.ipv4.tcp_retries2 = 8
net.ipv4.tcp_slow_start_after_idle = 0
fs.file-max = 1000000
fs.inotify.max_user_instances = 8192
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 1024 65000
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.tcp_max_tw_buckets = 6000
net.ipv4.route.gc_timeout = 100
net.ipv4.tcp_syn_retries = 1
net.ipv4.tcp_synack_retries = 1
net.core.somaxconn = 32768
net.core.netdev_max_backlog = 32768
net.ipv4.tcp_timestamps = 0
net.ipv4.tcp_max_orphans = 32768
# forward ipv4
#net.ipv4.ip_forward = 1" >>/etc/sysctl.conf
        sysctl -p
        echo "*               soft    nofile           1000000
*               hard    nofile          1000000" >/etc/security/limits.conf
        echo "ulimit -SHn 1000000" >>/etc/profile
        read -p "需要重启VPS后，才能生效系统优化配置，是否现在重启 ? [Y/n] :" yn
        [ -z "${yn}" ] && yn="y"
        if [[ $yn == [Yy] ]]; then
            echo -e "${Info} VPS 重启中..."
            reboot
        fi
    }

    portforward() {
        # 检查是否安装了 socat
        if ! command -v socat &>/dev/null; then
            _yellow "socat 未安装，正在安装..."
            apt-get update
            apt-get install socat -y
        fi
        # 定义函数：启动端口转发
        start_port_forward() {

            # 获取监听端口和目标地址
            read -p "请输入监听端口: " listen_port
            read -p "请输入目标 IP:  " target_addr
            read -p "请输入目标端口: " target_port

            # 服务名称
            service_name="port-forwarding-$listen_port"

            # 创建 systemd 服务文件
            service_file="/etc/systemd/system/$service_name.service"
            cat <<EOF >$service_file
[Unit]
Description=lookname
After=network.target

[Service]
ExecStart=/usr/bin/socat TCP-LISTEN:$listen_port,fork,reuseaddr TCP:$target_addr:$target_port
Restart=always
RestartSec=5
StandardOutput=file:$HOME/$service_name.log
StandardError=file:$HOME/$service_name.log

[Install]
WantedBy=multi-user.target
EOF

            # 重载 systemd 管理器配置
            systemctl daemon-reload

            # 启动服务
            systemctl start $service_name
            _blue "服务 $service_name 已启动。"

            # 启用服务，使其开机自启
            systemctl enable $service_name
            _green "服务 $service_name 已设置为开机自启。"

        }
        # 定义函数：停止端口转发
        stop_port_forward() {
            # 获取所有以 port-forwarding 开头的服务
            services=($(systemctl list-units --full -all | grep 'port-forwarding' | awk '{print $1}'))
            if [ ${#services[@]} -eq 0 ]; then
                _red "未找到任何 port-forwarding 相关的服务。"
                return
            fi

            echo "以下是所有 port-forwarding 相关的服务："
            for i in "${!services[@]}"; do
                status=$(systemctl is-active "${services[$i]}")
                echo "$((i + 1)). ${services[$i]} - $status"
            done

            read -p "请输入要删除的服务编号（输入 0 退出）: " choice
            if [ "$choice" -eq 0 ]; then
                return
            fi

            index=$((choice - 1))
            if [ $index -ge 0 ] && [ $index -lt ${#services[@]} ]; then
                service_to_delete="${services[$index]}"
                systemctl stop $service_to_delete
                systemctl disable $service_to_delete
                rm -f "/etc/systemd/system/$service_to_delete"
                systemctl daemon-reload
                _blue "服务 $service_to_delete 已停止并删除"
            else
                _red "输入的编号无效，请重新运行该函数。"
            fi
        }
        # 定义函数：检查端口转发状态
        list_port_forward() {
            _blue "列出所有端口转发："
            pgrep -f "socat TCP-LISTEN:" | xargs -I {} ps -p {} -o pid,cmd

            # 获取所有以 port-forwarding 开头的服务
            services=($(systemctl list-units --full -all | grep 'port-forwarding' | awk '{print $1}'))
            if [ ${#services[@]} -eq 0 ]; then
                _red "未找到任何 port-forwarding 相关的服务。"
                return
            fi

            echo "以下是所有 port-forwarding 相关的服务："
            for i in "${!services[@]}"; do
                status=$(systemctl is-active "${services[$i]}")
                echo "$((i + 1)). ${services[$i]} - $status"
            done
        }
        # 定义函数：主菜单
        menuname='首页/网络/端口转发服务'
        options=("开启转发" start_port_forward "终止转发" stop_port_forward "列出所有转发" list_port_forward)

        menu "${options[@]}"
    }

    #测试端口延迟
    testport(){
        # 提示用户输入 IP 地址和端口号
        read -p "请输入目标 IP 地址: " ip
        read -p "请输入目标端口号: " port

        # 记录开始时间
        start_time=$(date +%s%N)

        # 尝试连接到指定的 IP 和端口
        nc -z -w 2 $ip $port
        result=$?

        # 记录结束时间
        end_time=$(date +%s%N)

        # 计算延迟（毫秒）
        latency=$(( (end_time - start_time) / 1000000 ))

        if [ $result -eq 0 ]; then
            echo "端口 $port 在 $ip 上开放，延迟约为 $latency 毫秒。"
        else
            echo "端口 $port 在 $ip 上未开放或连接超时，延迟计算失败。"
        fi

    }

    menuname='首页/网络'
    echo "networkfun" >$installdir/config/lastfun
    options=( "外网测速" publicnettest "iperf3打流" iperftest "临时http代理" http_proxy  "配置局域网ip" lanfun "nmap扫描" nmapfun "ufw" ufwfun "fail2ban" fail2banfun "系统网络配置优化" system_best "端口转发服务" portforward "测试端口延迟" testport)

    menu "${options[@]}"

    }