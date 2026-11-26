networkfun() {

    beforeMenu(){
    _blue "> ---  当前目录: [ $(pwd) ] ---- < v:$selfversion"
    echo
    _yellow "当前菜单: $menuname "
    echo
    }
    

# 获取网卡
    getnetcard() {
        interfaces=$(ifconfig -a | sed -nE 's/^([^[:space:]]+).*$/\1/p')

        PS3="请选择网卡名称： "
        select interface in $interfaces; do
            if [[ -n "$interface" ]]; then
                break
            fi
        done
        interface=$(echo "$interface" | sed 's/://')
        echo $interface
    }

    # 实时网速
    Realtimenetworkspeedfun() {
        check_and_install bmon
        bmon
    }

    # 网络信息
    netinfo() {
        echo
        _blue "--本机IP--" 
        ifconfig -a | grep "inet " | grep -v "127.0.0.1" | grep -v "docker" | grep -v "veth" | grep -v "br-"

        _blue "--路由表--" 
        route -n
        _blue "--活动连接--"
        tcpcount=$(netstat -antp | grep ESTABLISHED | wc -l)
        udpcount=$(netstat -antp | grep -v ESTABLISHED | wc -l)
        totalcount=$(($tcpcount + $udpcount))
        check_and_install bc
        cent=$(echo "scale=2; $totalcount / 65535 * 100" | bc)
        if [ $(echo "$cent < 1" | bc) -eq 1 ]; then
            cent=1
        fi
        echo
        echo "TCP连接数: $tcpcount UDP连接数: $udpcount 总计：$totalcount /65535 ($cent%)"
        echo
        _blue "--对外暴露监听端口--" 
        netstat -tunlp | grep -v "127.0.0.1" | grep -v "0.0.0.0" | grep -v "docker" | grep -v "veth"

        _blue "--公网IP及地区--" 
        local pubip
        pubip="$(curl -s -m 10 cip.cc | head -1)"
        echo "$pubip"
        local org city country region
        org="$(wget -q -T10 -O- ipinfo.io/org)"
        city="$(wget -q -T10 -O- ipinfo.io/city)"
        country="$(wget -q -T10 -O- ipinfo.io/country)"
        region="$(wget -q -T10 -O- ipinfo.io/region)"
        if [[ -n "${org}" ]]; then
            echo "Organization       : $(_blue "${org}")"
        fi
        if [[ -n "${city}" && -n "${country}" ]]; then
            echo "Location           : $(_blue "${city} / ${country}")"
        fi
        if [[ -n "${region}" ]]; then
            echo "Region             : $(_yellow "${region}")"
        fi
        if [[ -z "${org}" ]]; then
            echo "Region             : $(_red "No ISP detected")"
        fi
        echo
    }

    


    
    # ufw防火墙
    ufwfun() {
        ufwopen() {
            check_and_install ufw
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

            # 允许特定 IP 和端口的入站流量
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

            # 拒绝特定 IP 和端口的入站流量
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
        if ! command -v fail2ban-client &>/dev/null; then
            check_and_install fail2ban
        fi
        if ! command -v fail2ban-client &>/dev/null; then
            _red "fail2ban 安装失败，请手动安装后重试"
            return 1
        fi

        fail2banstatusfun() {
            fail2ban-client status
            echo
            _blue "sshd 详细状态:"
            fail2ban-client status sshd 2>/dev/null || _red "sshd jail 未加载"
        }

        fail2banconfig() {
            echo
            _blue "fail2ban jail 配置"
            echo "1. sshd 防暴力破解"
            echo "2. smb 防暴力破解"
            echo "3. 自定义端口防暴力破解"
            echo
            read -rp "请选择 [1-3]: " f2b_choice

            case $f2b_choice in
                1)
                    _blue "配置 sshd jail..."
                    cat > /etc/fail2ban/jail.d/sshd.local <<'EOF'
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 5
bantime = 3600
findtime = 600
EOF
                    ;;
                2)
                    _blue "配置 smb jail..."
                    cat > /etc/fail2ban/jail.d/samba.local <<'EOF'
[samba]
enabled = true
port = 139,445
filter = samba
logpath = /var/log/samba/log.smbd
maxretry = 5
bantime = 3600
findtime = 600
EOF
                    ;;
                3)
                    read -rp "请输入监听端口 (例如 8080): " port
                    [[ -z "$port" ]] && { _yellow "已取消"; return 1; }
                    jailname="custom-port-${port}"
                    read -rp "请输入日志路径 (例如 /var/log/custom.log): " logpath
                    [[ -z "$logpath" ]] && { _yellow "已取消"; return 1; }
                    read -rp "请输入最大重试次数 (默认5): " maxretry
                    maxretry=${maxretry:-5}
                    read -rp "请输入封禁时间秒数 (默认3600): " bantime
                    bantime=${bantime:-3600}
                    read -rp "请输入统计时间窗口秒数 (默认600): " findtime
                    findtime=${findtime:-600}
                    _blue "配置自定义端口 jail: $jailname"
                    cat > /etc/fail2ban/jail.d/${jailname}.local <<EOF
[$jailname]
enabled = true
port = $port
filter = $jailname
logpath = $logpath
maxretry = $maxretry
bantime = $bantime
findtime = $findtime
EOF
                    ;;
                *)
                    _yellow "无效选择"
                    return 1
                    ;;
            esac

            if command -v systemctl &>/dev/null; then
                systemctl restart fail2ban 2>/dev/null || systemctl start fail2ban 2>/dev/null || true
            else
                service fail2ban restart 2>/dev/null || service fail2ban start 2>/dev/null || true
            fi
            sleep 1
            _green "fail2ban 配置已写入，服务已重启"
            echo
            fail2ban-client status 2>/dev/null || { _yellow "fail2ban 状态查询失败，可能服务尚未完全启动，请稍后再试"; }
        }

        fail2banbanip() {
            read -rp "请输入要封禁的 IP: " banip
            [[ -z "$banip" ]] && { _yellow "已取消"; return 1; }
            read -rp "请输入 jail 名称 (默认 sshd): " jail
            jail=${jail:-sshd}
            fail2ban-client set "$jail" banip "$banip" && _green "已封禁 IP: $banip (jail: $jail)" || _red "封禁失败"
        }

        fail2banunbanip() {
            read -rp "请输入要解封的 IP: " unbanip
            [[ -z "$unbanip" ]] && { _yellow "已取消"; return 1; }
            read -rp "请输入 jail 名称 (默认 sshd): " jail
            jail=${jail:-sshd}
            fail2ban-client set "$jail" unbanip "$unbanip" && _green "已解封 IP: $unbanip (jail: $jail)" || _red "解封失败"
        }

        fail2banbanned() {
            read -rp "请输入 jail 名称 (默认 sshd): " jail
            jail=${jail:-sshd}
            _blue "当前 jail ($jail) 被封禁的 IP:"
            fail2ban-client status "$jail" 2>/dev/null | grep "Banned IP list" || _red "无法获取封禁列表，请检查 jail 名称是否正确"
        }

        fail2banlistjails() {
            _blue "所有 fail2ban jail:"
            fail2ban-client status 2>/dev/null || _red "fail2ban 未运行"
        }

        fail2banrestart() {
            service fail2ban restart && _green "fail2ban 已重启" || _red "重启失败"
        }

        fail2banstop() {
            service fail2ban stop && _green "fail2ban 已停止" || _red "停止失败"
        }

        fail2banstart() {
            service fail2ban start && _green "fail2ban 已启动" || _red "启动失败"
        }

        menuname='首页/网络/fail2ban'
        options=("配置jail" fail2banconfig "查看状态" fail2banstatusfun "列出所有jail" fail2banlistjails "封禁IP" fail2banbanip "解封IP" fail2banunbanip "查看封禁列表" fail2banbanned "重启服务" fail2banrestart "停止服务" fail2banstop "启动服务" fail2banstart)
        menu "${options[@]}"
    }

    # iperf3打流
    iperftest() {

        check_and_install iperf3
        
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
    # nmap扫描
    nmapfun() {

        check_and_install nmap

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
    
    # 外网测速
    publicnettest() {
        local speeddir="${HOME}/.speedtest-cli-ookla"

        netfast() {
            if ! command -v speedtest-cli &>/dev/null; then
                check_and_install speedtest-cli
                command -v speedtest-cli &>/dev/null || { _red "speedtest-cli 安装失败，请手动安装"; return 1; }
            fi
            _blue "开始测速..."
            speedtest-cli || { _red "测速失败"; return 1; }
            _green "测速完成"
        }

        # SpeedCLI 测速
        netfast2() {
            command -v curl &>/dev/null || { _red "未安装 curl"; return 1; }
            local script tmp
            script=$(curl -fsSL --max-time 15 https://git.io/speedtest-cli.sh) || { _red "测速脚本下载失败（git.io 短链可能已失效）"; return 1; }
            [[ -n "$script" ]] || { _red "测速脚本为空"; return 1; }
            tmp=$(mktemp) || { _red "无法创建临时文件"; return 1; }
            printf '%s\n' "$script" > "$tmp"
            _blue "开始安装/测速..."
            if command -v sudo &>/dev/null; then
                sudo bash "$tmp"
            else
                bash "$tmp"
            fi
            local rc=$?
            rm -f "$tmp"
            (( rc == 0 )) || { _red "安装/测速失败"; return 1; }
            command -v speedtest &>/dev/null || { _red "speedtest 命令不可用"; return 1; }
            speedtest || { _red "测速失败"; return 1; }
            _green "测速完成"
        }
        # 三网测速
        sanwang() {
            command -v curl &>/dev/null || { _red "未安装 curl"; return 1; }
            local script
            script=$(curl -fsSL --max-time 15 https://down.wangchao.info/sh/superspeed.sh) || { _red "三网测速脚本下载失败"; return 1; }
            [[ -n "$script" ]] || { _red "测速脚本为空"; return 1; }
            bash -c "$script"
        }
        # 多地区测速
        netfast3() {
            local stbin="${speeddir}/speedtest"
            local logfile="${speeddir}/speedtest.log"

            if [ ! -x "$stbin" ]; then
                local sysarch sys_bit url1 url2
                sysarch="$(uname -m)"
                [[ "$sysarch" = "unknown" || -z "$sysarch" ]] && sysarch="$(arch)"
                case "$sysarch" in
                    x86_64|amd64) sys_bit="x86_64" ;;
                    i386|i686) sys_bit="i386" ;;
                    armv8|armv8l|aarch64|arm64) sys_bit="aarch64" ;;
                    armv7|armv7l) sys_bit="armhf" ;;
                    armv6) sys_bit="armel" ;;
                    *) sys_bit="" ;;
                esac
                [[ -z "$sys_bit" ]] && { _red "不支持的系统架构: ${sysarch}"; return 1; }
                if ! command -v wget &>/dev/null && ! command -v curl &>/dev/null; then
                    _red "需要 wget 或 curl 下载测速程序"
                    return 1
                fi
                url1="https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-${sys_bit}.tgz"
                url2="https://dl.lamp.sh/files/ookla-speedtest-1.2.0-linux-${sys_bit}.tgz"
                local tgz="${speeddir}/speedtest.tgz"
                mkdir -p "$speeddir" || { _red "无法创建目录 $speeddir"; return 1; }
                local ok=0
                if command -v wget &>/dev/null; then
                    wget --no-check-certificate -q -T15 -O "$tgz" "$url1" && ok=1
                    (( ok == 0 )) && wget --no-check-certificate -q -T15 -O "$tgz" "$url2" && ok=1
                elif command -v curl &>/dev/null; then
                    curl -kfsSL --max-time 15 -o "$tgz" "$url1" && ok=1
                    (( ok == 0 )) && curl -kfsSL --max-time 15 -o "$tgz" "$url2" && ok=1
                fi
                (( ok == 0 )) && { rm -f "$tgz"; _red "测速程序下载失败"; return 1; }
                if ! tar zxf "$tgz" -C "$speeddir" 2>/dev/null || [ ! -f "$stbin" ]; then
                    rm -f "$tgz"
                    _red "测速程序解压失败"
                    return 1
                fi
                chmod +x "$stbin"
                rm -f "$tgz"
            fi

            printf "%-18s%-18s%-20s%-12s\n" " Node Name" "Download Speed" "Upload Speed" "Latency"

            speed_test() {
                local nodeName="$2" sid="$1"
                if [ -z "$sid" ]; then
                    "$stbin" --progress=no --accept-license --accept-gdpr >"$logfile" 2>&1
                else
                    "$stbin" --progress=no --server-id="$sid" --accept-license --accept-gdpr >"$logfile" 2>&1
                fi
                if [ $? -ne 0 ]; then
                    printf "\033[0;33m%-18s\033[0;31m%s\033[0m\n" " ${nodeName}" "测速失败（节点不可用或网络超时）"
                    return
                fi
                local dl_speed up_speed latency
                dl_speed=$(awk '/Download:/{print $2" "$3}' "$logfile")
                up_speed=$(awk '/Upload:/{print $2" "$3}' "$logfile")
                latency=$(awk '/Latency:/{print $2" "$3}' "$logfile")
                if [[ -n "${dl_speed}" && -n "${up_speed}" && -n "${latency}" ]]; then
                    printf "\033[0;33m%-18s\033[0;32m%-18s\033[0;31m%-20s\033[0;36m%-12s\033[0m\n" \
                        " ${nodeName}" "${dl_speed}" "${up_speed}" "${latency}"
                else
                    printf "\033[0;33m%-18s\033[0;31m%s\033[0m\n" " ${nodeName}" "结果解析失败"
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
            unset -f speed_test
        }

        menuname='首页/网络/外网测速'
        options=("测速1" netfast "测速2-SpeedCLI" netfast2 "多地区测速" netfast3 "三网测速" sanwang)

        menu "${options[@]}"
    }
    # 局域网ip
    lanfun() {

        cidr2mask() {
            local cidr=$1
            local mask=""
            local i
            for ((i = 0; i < 4; i++)); do
                if (( cidr >= 8 )); then
                    mask+="255"
                    cidr=$((cidr-8))
                else
                    if (( cidr > 0 )); then
                        val=$((256 - 2**(8-cidr)))
                        mask+="$val"
                        cidr=0
                    else
                        mask+="0"
                    fi
                fi
                if (( i < 3 )); then
                    mask+="."
                fi
            done
            echo "$mask"
        }

        # Debian (ifupdown) 方式：/etc/network/interfaces
        staticip_debian() {
            echo "备份原文件 /etc/network/interfaces"
            cp /etc/network/interfaces /etc/network/interfaces.bak."$datevar" 2>/dev/null || true

            ens=$(getnetcard)
            until [[ -n "$ipaddresses" ]]; do
                read -ep "请输入ip地址+网络号 (x.x.x.x/x): " ipaddresses
            done
            ip=${ipaddresses%%/*}
            cidr=${ipaddresses#*/}
            netmask=$(cidr2mask "$cidr")

            until [[ -n "$gateway" ]]; do
                read -ep "请输入网关(x.x.x.x): " gateway
            done
            until [[ -n "$nameservers" ]]; do
                read -ep "请输入DNS(多个空格分隔): " nameservers
            done

            _red "请仔细检查配置是否正确!"
            echo "网卡: $ens"
            echo "地址: $ip"
            echo "CIDR: /$cidr  netmask: $netmask"
            echo "网关: $gateway"
            echo "DNS: $nameservers"
            waitinput

            cat <<EOF >/etc/network/interfaces
# This file is auto-generated by script (backup at /etc/network/interfaces.bak.*)
auto lo
iface lo inet loopback

auto $ens
iface $ens inet static
    address $ip
    netmask $netmask
    gateway $gateway
    dns-nameservers $nameservers
EOF

            if command -v systemctl &>/dev/null; then
                systemctl restart networking || true
            fi
            ifdown "$ens" 2>/dev/null || true
            ifup "$ens" 2>/dev/null || true

            echo "配置已写入 /etc/network/interfaces ，请验证网络连接（若 SSH 中断，使用新 IP 登录）"
        }

        dhcpip_debian() {
            echo "备份原文件 /etc/network/interfaces"
            cp /etc/network/interfaces /etc/network/interfaces.bak."$datevar" 2>/dev/null || true

            ens=$(getnetcard)
            _red "请仔细检查配置是否正确!"
            echo "网卡: $ens"
            waitinput

            cat <<EOF >/etc/network/interfaces
# This file is auto-generated by script (backup at /etc/network/interfaces.bak.*)
auto lo
iface lo inet loopback

auto $ens
iface $ens inet dhcp
EOF

            if command -v systemctl &>/dev/null; then
                systemctl restart networking || true
            fi
            ifdown "$ens" 2>/dev/null || true
            ifup "$ens" 2>/dev/null || true

            echo "DHCP 配置已写入"
        }

        # netplan (Ubuntu 等) 保持原有实现
        staticip_netplan() {
            echo "备份原文件 /etc/netplan/00-installer-config.yaml"
            cp /etc/netplan/00-installer-config.yaml /etc/netplan/00-installer-config.yaml.bak."$datevar" 2>/dev/null || true
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
            echo "网卡为 $ens"
            echo "网络地址为 $ipaddresses"
            echo "网关为 $gateway"
            echo "DNS地址为 $nameservers"
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
            echo "配置信息成功写入,若ssh断开,请使用设置的ip重新登录"
            netplan apply
            echo "ok"
        }

        dhcpip_netplan() {
            echo "开始配置DHCP (netplan)"
            echo "备份原文件 /etc/netplan/00-installer-config.yaml"
            cp /etc/netplan/00-installer-config.yaml /etc/netplan/00-installer-config.yaml.bak."$datevar" 2>/dev/null || true
            ens=$(getnetcard)
            _red "请仔细检查配置是否正确!"
            echo "网卡为 $ens"
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

        if [[ -f /etc/os-release ]]; then
            . /etc/os-release
            ID_LC="${ID,,}"
            IDLIKE_LC="${ID_LIKE,,}"
        else
            ID_LC=""
            IDLIKE_LC=""
        fi

        if [[ "$ID_LC" == "debian" || "$IDLIKE_LC" =~ debian ]]; then
            menuname='首页/网络/配置局域网ip (Debian)'
            options=("配置静态ip (Debian)" staticip_debian "配置dhcp (Debian)" dhcpip_debian)
        else
            menuname='首页/网络/配置局域网ip'
            options=("配置静态ip" staticip_netplan "配置dhcp" dhcpip_netplan)
        fi

        menu "${options[@]}"

    }

    # 临时代理
    http_proxy() {
        _blue '配置后仅当前窗口生效,需手动执行'
        echo 'export http_proxy=http://x.x.x.x:x'
    }

    # 系统网络配置优化
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
        check_and_install socat
        # 启动端口转发
        start_port_forward() {

            read -p "请输入监听端口: " listen_port
            read -p "请输入目标 IP:  " target_addr
            read -p "请输入目标端口: " target_port

            service_name="port-forwarding-$listen_port"

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

            systemctl daemon-reload

            systemctl start $service_name
            _blue "服务 $service_name 已启动。"

            systemctl enable $service_name
            _green "服务 $service_name 已设置为开机自启。"

        }
        # 停止端口转发
        stop_port_forward() {
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
        # 检查端口转发状态
        list_port_forward() {
            _blue "列出所有端口转发："
            pgrep -f "socat TCP-LISTEN:" | xargs -I {} ps -p {} -o pid,cmd

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
        menuname='首页/网络/端口转发服务'
        options=("开启转发" start_port_forward "终止转发" stop_port_forward "列出所有转发" list_port_forward)

        menu "${options[@]}"
    }

    # 测试端口延迟
    testport(){
        read -p "请输入目标 IP 地址: " ip
        read -p "请输入目标端口号: " port

        start_time=$(date +%s%N)

        nc -z -w 2 $ip $port
        result=$?

        end_time=$(date +%s%N)

        latency=$(( (end_time - start_time) / 1000000 ))

        if [ $result -eq 0 ]; then
            echo "端口 $port 在 $ip 上开放，延迟约为 $latency 毫秒。"
        else
            echo "端口 $port 在 $ip 上未开放或连接超时，延迟计算失败。"
        fi

    }

    # 切换TCP拥塞控制
    switchTCPctrl(){
        tcpcc=$(sysctl net.ipv4.tcp_congestion_control | awk -F ' ' '{print $3}')

        beforeMenu(){
            _blue "> ---  当前目录: [ $(pwd) ] ---- < v:$selfversion"
            echo
            _yellow "当前菜单: $menuname "
            echo
            _green "当前TCP CC: $tcpcc" 
            echo
        }

        tcpccbbr() {
            [[ $EUID -ne 0 ]] && { echo "错误：需要root权限，请使用sudo执行"; return 1; }
            if grep -q "^net.core.default_qdisc" /etc/sysctl.conf; then
                sed -i 's/^net.core.default_qdisc=.*/net.core.default_qdisc=fq/' /etc/sysctl.conf
            else
                echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
            fi
            if grep -q "^net.ipv4.tcp_congestion_control" /etc/sysctl.conf; then
                sed -i 's/^net.ipv4.tcp_congestion_control=.*/net.ipv4.tcp_congestion_control=bbr/' /etc/sysctl.conf
            else
                echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
            fi
            sysctl -p
            _blue "已设置TCP拥塞控制为BBR"
        }

        tcpcccubic() {
            [[ $EUID -ne 0 ]] && { echo "错误：需要root权限，请使用sudo执行"; return 1; }
            if grep -q "^net.core.default_qdisc" /etc/sysctl.conf; then
                sed -i 's/^net.core.default_qdisc=.*/net.core.default_qdisc=fq/' /etc/sysctl.conf
            else
                echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
            fi
            if grep -q "^net.ipv4.tcp_congestion_control" /etc/sysctl.conf; then
                sed -i 's/^net.ipv4.tcp_congestion_control=.*/net.ipv4.tcp_congestion_control=cubic/' /etc/sysctl.conf
            else
                echo "net.ipv4.tcp_congestion_control=cubic" >> /etc/sysctl.conf
            fi
            sysctl -p
            _blue "已设置TCP拥塞控制为CUBIC"
        }

        menuname='首页/网络/切换TCP拥塞控制'
        options=("切换成bbr" tcpccbbr "切换成cubic" tcpcccubic )
        menu "${options[@]}"
    }

    iptablesfun() {
        [[ $EUID -ne 0 ]] && { _red "错误：iptables 管理需要 root 权限，请使用 sudo 执行"; return 1; }
        command -v iptables &>/dev/null || { _red "错误：系统未安装 iptables"; return 1; }

        _ipt_ok() { _green "$1"; }
        _ipt_fail() { _red "错误：$1 执行失败，请检查权限或模块支持"; return 1; }
        _ipt_port() { [[ "$1" =~ ^[0-9]+$ ]] && (( 10#$1 >= 1 && 10#$1 <= 65535 )); }

        iptshow() {
            echo
            _blue "===== iptables INPUT 规则 ====="
            echo
            iptables -L INPUT -n -v --line-numbers 2>/dev/null || _ipt_fail "查看 INPUT"
            echo
            _blue "===== iptables FORWARD 规则 ====="
            echo
            iptables -L FORWARD -n -v --line-numbers 2>/dev/null || _ipt_fail "查看 FORWARD"
            echo
            _blue "===== iptables NAT 规则 ====="
            echo
            iptables -t nat -L -n -v --line-numbers 2>/dev/null || _ipt_fail "查看 NAT"
        }

        iptallowport() {
            read -ep "请输入放行端口: " port
            [[ -z "$port" ]] && { _yellow "已取消"; return; }
            _ipt_port "$port" || { _red "无效端口"; return; }
            echo "协议: 1)tcp  2)udp  3)tcp+udp"
            read -ep "请选择 (默认1): " proto
            case "$proto" in
                2) iptables -I INPUT -p udp --dport "$port" -j ACCEPT || { _ipt_fail "放行 UDP $port"; return 1; }
                   _ipt_ok "已放行 UDP $port" ;;
                3) if iptables -I INPUT -p tcp --dport "$port" -j ACCEPT &&
                      iptables -I INPUT -p udp --dport "$port" -j ACCEPT; then
                       _ipt_ok "已放行 TCP+UDP $port"
                   else
                       _ipt_fail "放行 TCP+UDP $port"
                   fi ;;
                *) iptables -I INPUT -p tcp --dport "$port" -j ACCEPT || { _ipt_fail "放行 TCP $port"; return 1; }
                   _ipt_ok "已放行 TCP $port" ;;
            esac
        }

        iptblockport() {
            read -ep "请输入拦截端口: " port
            [[ -z "$port" ]] && { _yellow "已取消"; return; }
            _ipt_port "$port" || { _red "无效端口"; return; }
            if iptables -I INPUT -p tcp --dport "$port" -j DROP &&
               iptables -I INPUT -p udp --dport "$port" -j DROP; then
                _ipt_ok "已拦截 TCP+UDP $port"
            else
                _ipt_fail "拦截 $port"
            fi
        }

        iptblockip() {
            read -ep "请输入要封禁的IP: " ip
            [[ -z "$ip" ]] && { _yellow "已取消"; return; }
            iptables -I INPUT -s "$ip" -j DROP || { _ipt_fail "封禁 $ip"; return 1; }
            _ipt_ok "已封禁 $ip"
        }

        iptallowip() {
            read -ep "请输入要放行的IP: " ip
            [[ -z "$ip" ]] && { _yellow "已取消"; return; }
            iptables -I INPUT -s "$ip" -j ACCEPT || { _ipt_fail "放行 $ip"; return 1; }
            _ipt_ok "已放行 $ip"
        }

        iptdelrule() {
            echo
            _blue "当前 INPUT 规则:"
            iptables -L INPUT -n --line-numbers || { _ipt_fail "查看规则"; return 1; }
            echo
            read -ep "请输入要删除的规则序号: " rulenum
            [[ -z "$rulenum" ]] && { _yellow "已取消"; return; }
            if ! [[ "$rulenum" =~ ^[0-9]+$ ]]; then
                _red "无效序号"
                return
            fi
            iptables -D INPUT "$rulenum" || { _ipt_fail "删除规则 #$rulenum"; return 1; }
            _ipt_ok "已删除规则 #$rulenum"
            echo
            _blue "当前 INPUT 规则:"
            iptables -L INPUT -n --line-numbers
        }

        iptflush() {
            _red "警告: 将清空所有规则，并把默认策略重置为 ACCEPT（操作本身不会断连）"
            read -ep "确认清空? (y/n, 默认n): " confirm
            [[ "$confirm" != "y" ]] && { _yellow "已取消"; return; }
            # 先把默认策略设为 ACCEPT，防止原策略为 DROP 时 -F 清掉放行规则后把自己锁在外面
            iptables -P INPUT ACCEPT || { _ipt_fail "重置 INPUT 策略"; return 1; }
            iptables -P FORWARD ACCEPT || { _ipt_fail "重置 FORWARD 策略"; return 1; }
            iptables -P OUTPUT ACCEPT || { _ipt_fail "重置 OUTPUT 策略"; return 1; }
            if iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X && iptables -t nat -X; then
                _ipt_ok "已清空所有规则，默认策略已重置为 ACCEPT"
            else
                _ipt_fail "清空规则"
            fi
        }

        iptexportrules() {
            local savefile
            read -ep "导出文件路径 (默认 /root/iptables-rules.bak.时间戳): " savefile
            savefile=${savefile:-/root/iptables-rules.bak.$(date +%Y%m%d%H%M%S)}
            command -v iptables-save &>/dev/null || { _red "错误：未找到 iptables-save"; return 1; }
            if iptables-save > "$savefile" 2>/dev/null && [[ -s "$savefile" ]]; then
                _ipt_ok "规则已导出到 $savefile"
            else
                rm -f "$savefile"
                _ipt_fail "导出规则"
            fi
        }

        iptimportrules() {
            command -v iptables-restore &>/dev/null || { _red "错误：未找到 iptables-restore"; return 1; }
            echo
            _blue "可导入的规则文件:"
            local files=()
            local f
            for f in /root/iptables-rules.bak.*; do
                [[ -f "$f" ]] && files+=("$f")
            done
            (( ${#files[@]} == 0 )) && { _yellow "没有找到可导入的规则文件"; return; }

            local i
            for i in "${!files[@]}"; do
                printf "  %d) %s\n" "$((i+1))" "${files[$i]}"
            done
            read -ep "或直接输入完整路径 (回车则从上面选择): " custom
            local target=""
            if [[ -n "$custom" ]]; then
                [[ -f "$custom" && -s "$custom" ]] || { _red "文件不存在或为空: $custom"; return; }
                target="$custom"
            else
                read -ep "请选择要导入的文件序号: " choice
                if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#files[@]} )); then
                    target="${files[$((choice-1))]}"
                else
                    _red "无效序号"
                    return
                fi
            fi

            _red "警告：导入将替换当前所有规则！"
            read -ep "确认导入? (y/n, 默认n): " confirm
            [[ "$confirm" != "y" ]] && { _yellow "已取消"; return; }
            if iptables-restore < "$target" 2>/dev/null; then
                _ipt_ok "规则已从 $target 导入"
            else
                _ipt_fail "导入规则（文件格式可能不兼容）"
            fi
        }

        iptdefaultdeny() {
            _red "将设置默认策略: INPUT DROP, FORWARD DROP, OUTPUT ACCEPT"
            read -ep "确认? (y/n, 默认n): " confirm
            [[ "$confirm" != "y" ]] && { _yellow "已取消"; return; }

            local sshport
            sshport=$(awk '$1=="Port" && $2 ~ /^[0-9]+$/ {print $2; exit}' /etc/ssh/sshd_config 2>/dev/null)
            sshport=${sshport:-22}
            _blue "自动放行 SSH 端口 $sshport、回环和已建立连接，防止断连"
            iptables -I INPUT -i lo -j ACCEPT || { _ipt_fail "放行回环"; return 1; }
            iptables -I INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT || { _ipt_fail "放行已建立连接"; return 1; }
            iptables -I INPUT -p tcp --dport "$sshport" -j ACCEPT || { _ipt_fail "放行 SSH 端口"; return 1; }
            iptables -P INPUT DROP || { _ipt_fail "设置 INPUT 策略"; return 1; }
            iptables -P FORWARD DROP || { _ipt_fail "设置 FORWARD 策略"; return 1; }
            iptables -P OUTPUT ACCEPT || { _ipt_fail "设置 OUTPUT 策略"; return 1; }
            _ipt_ok "默认策略已设置 (SSH:$sshport / lo / 已建立连接 已放行)"
        }

        iptsshguard() {
            echo
            read -ep "SSH端口 (默认22): " sshport
            sshport=${sshport:-22}
            _ipt_port "$sshport" || { _red "无效端口"; return; }
            read -ep "最大尝试次数 (默认5): " maxretry
            maxretry=${maxretry:-5}
            read -ep "封禁时间秒数 (默认3600): " bantime
            bantime=${bantime:-3600}
            [[ "$maxretry" =~ ^[0-9]+$ && "$bantime" =~ ^[0-9]+$ ]] || { _red "尝试次数和封禁时间必须为正整数"; return; }

            if iptables -I INPUT -p tcp --dport "$sshport" -m conntrack --ctstate NEW -m recent --set --name SSH &&
               iptables -I INPUT -p tcp --dport "$sshport" -m conntrack --ctstate NEW -m recent --update --seconds "$bantime" --hitcount "$maxretry" --name SSH -j DROP; then
                _ipt_ok "SSH防暴力破解已启用 (端口:$sshport ${maxretry}次/${bantime}秒)"
            else
                _ipt_fail "设置 SSH 防暴力破解"
            fi
        }

        iptconnectionlimit() {
            read -ep "请输入限制的端口: " port
            [[ -z "$port" ]] && { _yellow "已取消"; return; }
            _ipt_port "$port" || { _red "无效端口"; return; }
            read -ep "最大并发连接数 (默认100): " maxconn
            maxconn=${maxconn:-100}
            [[ "$maxconn" =~ ^[0-9]+$ ]] && (( maxconn > 0 )) || { _red "无效并发数"; return; }
            iptables -I INPUT -p tcp --dport "$port" -m connlimit --connlimit-above "$maxconn" -j REJECT || { _ipt_fail "设置并发限制"; return 1; }
            _ipt_ok "端口 $port 并发连接限制为 $maxconn"
        }

        menuname='首页/网络/iptables管理'
        options=("查看全部规则" iptshow "放行端口" iptallowport "拦截端口" iptblockport "放行IP" iptallowip "封禁IP" iptblockip "删除规则(序号)" iptdelrule "SSH防暴力破解" iptsshguard "端口并发限制" iptconnectionlimit "默认策略(白名单模式)" iptdefaultdeny "导出规则" iptexportrules "导入规则" iptimportrules "清空所有规则" iptflush)
        menu "${options[@]}"
        unset -f _ipt_ok _ipt_fail _ipt_port
    }

    # DNS 查询枚举 (基于 dnsrecon)
    dnsreconfun() {
        check_and_install dnsrecon

        dnsstd() {
            read -rp "请输入目标域名 (例如 example.com): " target
            [[ -z "$target" ]] && { _yellow "已取消"; return 1; }
            _blue "正在执行标准 DNS 枚举: dnsrecon -d $target -t std"
            dnsrecon -d "$target" -t std
        }

        dnsrev() {
            read -rp "请输入目标域名 (例如 example.com): " target
            [[ -z "$target" ]] && { _yellow "已取消"; return 1; }
            _blue "正在执行反向查询: dnsrecon -d $target -t rev"
            dnsrecon -d "$target" -t rev
        }

        dnsbrt() {
            read -rp "请输入目标域名 (例如 example.com): " target
            [[ -z "$target" ]] && { _yellow "已取消"; return 1; }
            _blue "正在执行暴力破解: dnsrecon -d $target -t brt"
            dnsrecon -d "$target" -t brt
        }

        dnsaxfr() {
            read -rp "请输入目标域名 (例如 example.com): " target
            [[ -z "$target" ]] && { _yellow "已取消"; return 1; }
            _blue "正在执行区域传输: dnsrecon -d $target -t axfr"
            dnsrecon -d "$target" -t axfr
        }

        dnssrv() {
            read -rp "请输入目标域名 (例如 example.com): " target
            [[ -z "$target" ]] && { _yellow "已取消"; return 1; }
            _blue "正在查询 SRV 记录: dnsrecon -d $target -t srv"
            dnsrecon -d "$target" -t srv
        }

        dnszone() {
            read -rp "请输入目标域名 (例如 example.com): " target
            [[ -z "$target" ]] && { _yellow "已取消"; return 1; }
            _blue "正在执行区域传送: dnsrecon -d $target -t zone"
            dnsrecon -d "$target" -t zone
        }

        menuname='首页/网络/DNS查询'
        options=("标准枚举 (std)" dnsstd "反向查询 (rev)" dnsrev "暴力破解 (brt)" dnsbrt "区域传输 (axfr)" dnsaxfr "SRV记录查询 (srv)" dnssrv "区域传送 (zone)" dnszone)
        menu "${options[@]}"
    }

    menuname='首页/网络'
    echo "networkfun" >$installdir/config/lastfun
    options=("网络信息" netinfo "实时网速" Realtimenetworkspeedfun "外网测速" publicnettest "iperf3打流" iperftest "临时http代理" http_proxy  "配置局域网ip" lanfun "nmap扫描" nmapfun "ufw" ufwfun "fail2ban" fail2banfun  "系统网络配置优化" system_best "端口转发服务" portforward "测试端口延迟" testport "切换TCP拥塞控制" switchTCPctrl "iptables管理" iptablesfun "DNS查询" dnsreconfun)

    menu "${options[@]}"

    }
