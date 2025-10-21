systemfun() {
    beforeMenu(){
    _blue "> ---  当前目录: [ $(pwd) ] ---- < v:${branch}-$selfversion"
    echo
    _yellow "当前菜单: $menuname "
    echo
    }

    sysinfo() {
        # 计算大小并转换单位（修正单位传递）
        calc_size() {
            local raw=$1 num=1 unit="KB"
            [[ ! $raw =~ ^[0-9]+$ ]] && { echo ""; return; }
            if (( raw >= 1073741824 )); then
                num=1073741824; unit="TB"
            elif (( raw >= 1048576 )); then
                num=1048576; unit="GB"
            elif (( raw >= 1024 )); then
                num=1024; unit="MB"
            elif (( raw == 0 )); then
                echo "0"; return
            fi
            #awk -v r="$raw" -v n="$num" -v u="$unit" 'BEGIN{printf "%.1f %s", r/n, u}'
            total_size=$(awk 'BEGIN{printf "%.1f", '"$raw"' / '$num'}')
            echo "${total_size} ${unit}"
        }

        # 转换为KiB
        to_kibyte() {
            awk -v r="$1" 'BEGIN{printf "%.0f", r / 1024}'
        }

        # 计算数组总和
        calc_sum() {
            local s=0 i
            for i in "$@"; do ((s += i)); done
            echo "$s"
        }

        # 获取操作系统信息
        get_opsy() {
            [[ -f /etc/redhat-release ]] && cat /etc/redhat-release && return
            if [[ -f /etc/os-release ]]; then
                awk -F'[= "]' '/PRETTY_NAME/{print $3,$4,$5}' /etc/os-release && return
            fi
            [[ -f /etc/lsb-release ]] && awk -F'[="]+' '/DESCRIPTION/{print $2}' /etc/lsb-release && return
        }

        # 获取电源模式
        get_power_mode() {
            local mode=""
            if command -v powerprofilesctl &>/dev/null; then
                mode=$(powerprofilesctl get 2>/dev/null)
            elif [[ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]]; then
                mode=$(cat "$_" 2>/dev/null)
            elif command -v cpupower &>/dev/null; then
                mode=$(cpupower frequency-info --policy 2>/dev/null | awk -F': ' '/current policy/ {print $2}' | awk '{print $1}')
            fi

            case "$mode" in
                performance) echo "performance";;
                balanced|ondemand|schedutil) echo "ondemand";;
                power-saver|powersave) echo "powersave";;
                *) echo "";;
            esac
        }

        # CPU信息
        cname=$(awk -F: '/model name/ {name=$2} END {gsub(/^[ \t]+|[ \t]+$/, "", name); print name}' /proc/cpuinfo)
        cores=$(awk '/^processor/ {core++} END {print core}' /proc/cpuinfo)
        freq=$(awk '/cpu MHz/ {print $4; exit}' /proc/cpuinfo)
        ccache=$(awk -F: '/cache size/ {cache=$2} END {print cache}' /proc/cpuinfo | sed 's/^[ \t]*//;s/[ \t]*$//')
        cpu_aes=$(grep -i 'aes' /proc/cpuinfo)
        cpu_virt=$(grep -Ei 'vmx|svm' /proc/cpuinfo)

        # 内存信息（精确匹配Mem/Swap行，拆分KB变量）
        free_out=$(free)
        totalram_kb=$(echo "$free_out" | awk '/^Mem:/ {print $2}')
        totalram=$(calc_size "$totalram_kb")
        useram_kb=$(echo "$free_out" | awk '/^Mem:/ {print $3}')
        useram=$(calc_size "$useram_kb")
        swap_total_kb=$(echo "$free_out" | awk '/^Swap:/ {print $2}')
        swap=$(calc_size "$swap_total_kb")
        uswap_kb=$(echo "$free_out" | awk '/^Swap:/ {print $3}')
        uswap=$(calc_size "$uswap_kb")

        # 系统运行时间
        up=$(awk '{a=$1/86400; b=($1%86400)/3600; c=($1%3600)/60} {printf "%d days, %d hour %d min\n", a, b, c}' /proc/uptime)

        # 系统基本信息
        opsy=$(get_opsy)
        arch=$(uname -m)
        power_mode=$(get_power_mode)
        lbit=$(command -v getconf &>/dev/null && getconf LONG_BIT || (echo "$arch" | grep -q "64" && echo 64 || echo 32))
        kern=$(uname -r)

        # 磁盘信息（精确匹配df total行，容错zpool输出）
        df_total=$(df -t simfs -t ext2 -t ext3 -t ext4 -t btrfs -t xfs -t vfat -t ntfs --total 2>/dev/null | grep '^total')
        in_kernel_total_kb=$(echo "$df_total" | awk '{print $2}')
        in_kernel_used_kb=$(echo "$df_total" | awk '{print $3}')
        zfs_total_kb=$(to_kibyte "$(calc_sum "$(zpool list -o size -Hp 2>/dev/null || echo 0)")")
        zfs_used_kb=$(to_kibyte "$(calc_sum "$(zpool list -o allocated -Hp 2>/dev/null || echo 0)")")
        disk_total=$(calc_size $((swap_total_kb + in_kernel_total_kb + zfs_total_kb)))
        disk_used=$(calc_size $((uswap_kb + in_kernel_used_kb + zfs_used_kb)))

        # 网络与虚拟化
        tcpctrl=$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}')
        [[ -x "$(command -v dmesg)" ]] && virtualx=$(dmesg 2>/dev/null)
        if command -v dmidecode &>/dev/null; then
            sys_manu=$(dmidecode -s system-manufacturer 2>/dev/null)
            sys_product=$(dmidecode -s system-product-name 2>/dev/null)
            sys_ver=$(dmidecode -s system-version 2>/dev/null)
        fi

        # 虚拟化检测
        if grep -qa docker /proc/1/cgroup; then
            virt="Docker"
        elif grep -qa lxc /proc/1/cgroup || grep -qa container=lxc /proc/1/environ; then
            virt="LXC"
        elif [[ -f /proc/user_beancounters ]]; then
            virt="OpenVZ"
        elif [[ "$virtualx" == *kvm-clock* || "$sys_product" == *KVM* || "$cname" == *KVM* || "$cname" == *QEMU* ]]; then
            virt="KVM"
        elif [[ "$virtualx" == *"VMware Virtual Platform"* || "$sys_product" == *"VMware Virtual Platform"* ]]; then
            virt="VMware"
        elif [[ "$virtualx" == *"Parallels Software International"* ]]; then
            virt="Parallels"
        elif [[ "$virtualx" == *VirtualBox* ]]; then
            virt="VirtualBox"
        elif [[ -e /proc/xen ]]; then
            grep -q "control_d" /proc/xen/capabilities 2>/dev/null && virt="Xen-Dom0" || virt="Xen-DomU"
        elif [[ -f /sys/hypervisor/type && "$(cat /sys/hypervisor/type)" == *xen* ]]; then
            virt="Xen"
        elif [[ "$sys_manu" == *"Microsoft Corporation"* && "$sys_product" == *"Virtual Machine"* ]]; then
            [[ "$sys_ver" == *"7.0"* || "$sys_ver" == *"Hyper-V" ]] && virt="Hyper-V" || virt="Microsoft Virtual Machine"
        else
            virt="Dedicated"
        fi

        # 输出信息（确保所有变量带单位）
        echo
        echo " CPU Model          : $(_blue "${cname:-CPU model not detected}")"
        echo " CPU Cores          : $(_blue "${cores}${freq:+ @ $freq MHz}")"
        [[ -n "$ccache" ]] && echo " CPU Cache          : $(_blue "$(calc_size $ccache)")"
        echo " AES-NI             : $([[ -n "$cpu_aes" ]] && _green "Enabled" || _red "Disabled")"
        echo " VM-x/AMD-V         : $([[ -n "$cpu_virt" ]] && _green "Enabled" || _red "Disabled")"
        echo " Total Disk         : $(_yellow "$disk_total") $(_blue "($disk_used Used)")"
        echo " Total Mem          : $(_yellow "$totalram") $(_blue "($useram Used)")"
        [[ "$swap" != "0" ]] && echo " Total Swap         : $(_blue "$swap ($uswap Used)")"
        echo " System uptime      : $(_blue "$up")"
        echo " OS                 : $(_blue "$opsy")"
        echo " Arch               : $(_blue "$arch ($lbit Bit)")"
        echo " Kernel             : $(_blue "$kern")"
        echo " TCP CC             : $(_yellow "$tcpctrl")"
        echo " Virtualization     : $(_blue "$virt")"
        [[ -n "$power_mode" ]] && echo " Power Mode         : $(_blue "$power_mode")"
    }

    #同步时间
    synchronization_time() {
                echo "同步前的时间: $(date -R)"
        echo "同步为上海时间? (y/n)"
        read -r confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            # 先备份原时区文件
            if [ -f "/etc/localtime" ]; then
                cp -a /etc/localtime /etc/localtime.bak."$(date +%Y%m%d%H%M%S)"
            fi
            # 使用符号链接而非直接复制，避免文件系统问题
            ln -snf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
            timedatectl set-timezone Asia/Shanghai
            timedatectl set-local-rtc 0
            # 检查ntpd服务是否存在，不存在则安装
            if ! command -v ntpd &> /dev/null; then
                echo "正在安装ntp服务..."
                apt-get update &> /dev/null && apt-get install -y ntp &> /dev/null
            fi
            timedatectl set-ntp yes
            hwclock -w
            # 检查服务是否存在再重启
            for service in rsyslog cron; do
                if systemctl is-active --quiet "$service"; then
                    systemctl restart "$service"
                fi
            done
            echo "当前系统时间: $(date -R)"
            echo "时间同步完成"
        else
            echo "已取消时间同步"
        fi
    }
    #配置仅秘钥rootssh登录
    sshpubonly() {
        echo "备份原文件Back up the sshd_config"
        cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak."$datevar"
        echo "port 22" >>/etc/ssh/sshd_config
        echo "PermitRootLogin yes" >>/etc/ssh/sshd_config
        echo "PasswordAuthentication no" >>/etc/ssh/sshd_config
        _blue "重启服务Restart service"
        service sshd restart
        _blue "ok"
    }
    #生成ssh密钥对
    sshgetpub() {
        _blue "默认使用 ed25519 加密算法"
        read -ep "请输入email 仅做注释(可选): " email
        ssh-keygen -t ed25519 -C "$email"
        echo
        echo "ssh秘钥生成成功"
        echo
        echo "公钥："
        cat ~/.ssh/id_ed25519.pub
    }
    #往authorized_keys写入公钥
    sshsetpub() {
        echo "请填入ssh公钥 (Write into /root/.ssh/authorized_keys)"
        read -ep "请粘贴至命令行回车(Please paste and enter): " sshpub
        echo -e $sshpub >>/root/.ssh/authorized_keys
        echo
        echo "ssh公钥写入成功Write success"
        echo
    }
    #查看本机authorized_keys
    catkeys() {

        cat /root/.ssh/authorized_keys

        nextrun
    }
    
    
    #系统检查
    systemcheck() {
        echo "正常登录到本机30天内的所有用户的历史记录:"
        last | head -n 30
        echo "系统中关键文件修改时间:"
        ls -ltr /bin/ls /bin/login /etc/passwd /bin/ps /etc/shadow | awk '{print ">>>文件名："$9"  ""最后修改时间："$6" "$7" "$8}'
        echo
        _blue '开机启动的服务'
        systemctl list-unit-files | grep enabled
        _blue '/etc/rc.local 和开机启动脚本'
        cat /etc/rc.local
        echo "僵尸进程:"
        ps -ef | grep zombie | grep -v grep
        if [ $? == 1 ]; then
            echo ">>>无僵尸进程"
        else
            echo ">>>有僵尸进程------warning"
        fi
        next
        echo "耗CPU最多的进程:"
        ps auxf | sort -nr -k 3 | head -5
        next
        echo "耗内存最多的进程:"
        ps auxf | sort -nr -k 4 | head -5
        next
        echo "环境变量:"
        env
        next
        echo "当前建立的连接:"
        netstat -n | awk '/^tcp/ {++S[$NF]} END {for(a in S) print a, S[a]}'

        more /etc/login.defs | grep -E "PASS_MAX_DAYS" | grep -v "#" | awk -F' ' '{if($2!=90){print ">>>密码过期天数是"$2"天,请管理员改成90天------warning"}}'
        next
        grep -i "^auth.*required.*pam_tally2.so.*$" /etc/pam.d/sshd >/dev/null
        if [ $? == 0 ]; then
            echo ">>>登入失败处理:已开启"
        else
            echo ">>>登入失败处理:未开启----------warning"
        fi
        echo
        echo "系统中存在以下非系统默认用户:"
        more /etc/passwd | awk -F ":" '{if($3>500){print ">>>/etc/passwd里面的"$1 "的UID为"$3",该账户非系统默认账户,请管理员确认是否为可疑账户--------warning"}}'
        next
        echo "系统特权用户:"
        awk -F: '$3==0 {print $1}' /etc/passwd
        next
        echo "系统中空口令账户:"
        awk -F: '($2=="!!") {print $1"该账户为空口令账户,请管理员确认是否为新增账户,如果为新建账户,请配置密码-------warning"}' /etc/shadow
        echo
        echo "查看syslog日志审计服务是否开启:"
        if service rsyslog status | egrep " active \(running"; then
            echo ">>>经分析,syslog服务已开启"
        else
            echo ">>>经分析,syslog服务未开启,建议通过service rsyslog start开启日志审计功能---------warning"
        fi
        next
        echo "查看syslog日志是否开启外发:"
        if more /etc/rsyslog.conf | egrep "@...\.|@..\.|@.\.|\*.\* @...\.|\*\.\* @..\.|\*\.\* @.\."; then
            echo ">>>经分析,客户端syslog日志已开启外发--------warning"
        else
            echo ">>>经分析,客户端syslog日志未开启外发---------ok"
        fi
        next
        echo "审计的要素和审计日志:"
        more /etc/rsyslog.conf | grep -v "^[$|#]" | grep -v "^$"
        next

        echo "检查重要日志文件是否存在:"
        for i in /var/log/secure /var/log/messages /var/log/cron /var/log/boot.log /var/log/dmesg; do
            if [ -e "$i" ]; then
                echo ">>>$i日志文件存在"
            else
                echo ">>>$i日志文件不存在------warning"
            fi
        done
        next
        echo "系统入侵行为:"
        more /var/log/secure | grep refused
        if [ $? == 0 ]; then
            echo "有入侵行为,请分析处理--------warning"
        else
            echo ">>>无入侵行为"
        fi
        next
        echo "用户错误登入列表:"
        lastb | head >/dev/null
        if [ $? == 1 ]; then
            echo ">>>无用户错误登入列表"
        else
            echo ">>>用户错误登入--------warning"
            lastb | head
        fi
        next
        echo "ssh暴力登入信息:"
        more /var/log/secure | grep "Failed" >/dev/null
        if [ $? == 1 ]; then
            echo ">>>无ssh暴力登入信息"
        else
            more /var/log/secure | awk '/Failed/{print $(NF-3)}' | sort | uniq -c | awk '{print ">>>登入失败的IP和尝试次数: "$2"="$1"次---------warning";}'
        fi
        echo
        echo "查看是否开启了ssh服务:"
        if service sshd status | grep -E "listening on|active \(running\)"; then
            echo ">>>SSH服务已开启"
        else
            echo ">>>SSH服务未开启--------warning"
        fi
        next
        echo "查看是否开启了Telnet-Server服务:"
        if more /etc/xinetd.d/telnetd 2>&1 | grep -E "disable=no"; then
            echo ">>>Telnet-Server服务已开启"
        else
            echo ">>>Telnet-Server服务未开启--------ok"
        fi
        next
        ps axu | grep iptables | grep -v grep || ps axu | grep firewalld | grep -v grep
        if [ $? == 0 ]; then
            echo ">>>防火墙已启用--------ok"
            iptables -nvL --line-numbers
        else
            echo ">>>防火墙未启用--------warning"
        fi
        next
        echo "查看系统SSH远程访问设置策略(host.deny拒绝列表):"
        if more /etc/hosts.deny | grep -E "sshd"; then
            echo ">>>远程访问策略已设置--------warning"
        else
            echo ">>>远程访问策略未设置--------ok"
        fi
        next
        echo "查看系统SSH远程访问设置策略(hosts.allow允许列表):"
        if more /etc/hosts.allow | grep -E "sshd"; then
            echo ">>>远程访问策略已设置--------warning"
        else
            echo ">>>远程访问策略未设置--------ok"
        fi
        nextrun
    }
    #ps进程搜索
    pssearch() {
        read -rp "ps -aux | grep ? <- :" -e name
        if [[ "$name" = "" ]]; then
            ps -aux

        else
            ps -aux | grep $name

        fi

        nextrun
    }
    #性能测试
    performancetest() {
        stresscputest() {
            echo "检查安装stress"
            apt install stress -y
            echo "默认单核60s测速 手动测试命令: stress -c 2 -t 100  #2代表核数 测试时间100s"
            waitinput
            stress -c 1 -t 60
        }
        sysbenchcputest() {
            echo "检查安装sysbench"
            apt install sysbench -y
            waitinput
            sysbench cpu run
        }
        

        FastBenchfun() {
            wget -N http://raw.githubusercontent.com/sshpc/FastBench/main/FastBench.sh && chmod +x FastBench.sh && sudo ./FastBench.sh
        }

        ecstest() {
            curl -L https://github.com/spiritLHLS/ecs/raw/main/ecs.sh -o ecs.sh && chmod +x ecs.sh && bash ecs.sh
        }
        mysqlBenchfun(){
            wget -N  http://raw.githubusercontent.com/sshpc/mysql-bench/main/mysql-bench.sh && chmod +x mysql-bench.sh && sudo ./mysql-bench.sh
        }

        menuname='首页/系统/性能测试'
        options=("sysbench-cpu测试" sysbenchcputest "stress-cpu压测" cputest  "机器跑分" FastBenchfun "融合怪测试" ecstest "mysql跑分测试" mysqlBenchfun)

        menu "${options[@]}"

    }

    
    #计划任务crontab
    crontabfun() {
        crontab -e
        service cron reload

    }
    #配置开机运行脚本 rc.local
    rclocalfun() {
        _blue '添加类似  nohup ... >> xxx.log 2>&1 &  最后行加 exit 0 '
        waitinput
        vim /etc/rc.local
    }

    # 配置自定义服务
    customservicefun() {

        #sysvinit
        sysvinitfun() {

            serviceadd() {

                _yellow "service 服务名称 stop/start"
                echo
                read -ep "请输入服务名称: " servicename
                service $servicename status >/dev/null
                if [ $? != 4 ]; then
                    _red '服务已存在'
                    exit
                fi

                echo '例子:'
                _yellow "xxx.sh nohup bash /root/xxx.sh  >> /root/servicename.log 2>&1 &"
                _yellow "nohup openvpn --config xxx.ovpn >> /root/openvpn.log 2>&1 &"
                echo
                read -ep "请输入执行程序: " execcmd
                echo
                echo '例子:'
                _yellow "pkill -f xxx(进程名)  or pkill -9 -f xxx"

                echo
                read -ep "请输入终止程序(默认取服务名): " stopcmd

                if [[ "$stopcmd" = "" ]]; then
                    stopcmd="pkill -f $servicename"
                fi
                echo
                next
                _green "服务名称: $servicename"
                echo
                _green "执行程序: $execcmd"
                echo
                _green "终止程序: $stopcmd"
                next
                echo
                waitinput
                _blue '开始配置'
                echo

                touch /etc/init.d/$servicename
                echo "#!/bin/sh" >>/etc/init.d/$servicename
                echo " " >>/etc/init.d/$servicename
                echo "### BEGIN INIT INFO" >>/etc/init.d/$servicename
                echo "# Provides: $servicename" >>/etc/init.d/$servicename
                echo '# Required-Start: $network $remote_fs $local_fs' >>/etc/init.d/$servicename
                echo '# Required-Stop: $network $remote_fs $local_fs' >>/etc/init.d/$servicename
                echo "# Default-Start: 2 3 4 5" >>/etc/init.d/$servicename
                echo "# Default-Stop: 0 1 6" >>/etc/init.d/$servicename
                echo "# Short-Description: $servicename" >>/etc/init.d/$servicename
                echo "# Description: $servicename" >>/etc/init.d/$servicename
                echo "### END INIT INFO" >>/etc/init.d/$servicename
                echo " " >>/etc/init.d/$servicename
                echo "start() {" >>/etc/init.d/$servicename
                echo "$execcmd" >>/etc/init.d/$servicename
                echo "}" >>/etc/init.d/$servicename
                echo "stop() {" >>/etc/init.d/$servicename
                echo "$stopcmd" >>/etc/init.d/$servicename
                echo "}" >>/etc/init.d/$servicename
                echo 'case "$1" in' >>/etc/init.d/$servicename
                echo "  start)" >>/etc/init.d/$servicename
                echo " start" >>/etc/init.d/$servicename
                echo " ;;" >>/etc/init.d/$servicename
                echo "  stop)" >>/etc/init.d/$servicename
                echo "  stop" >>/etc/init.d/$servicename
                echo " ;;" >>/etc/init.d/$servicename
                echo " *)" >>/etc/init.d/$servicename
                echo " exit 1" >>/etc/init.d/$servicename
                echo " ;;" >>/etc/init.d/$servicename
                echo "esac" >>/etc/init.d/$servicename
                echo " " >>/etc/init.d/$servicename
                echo "exit 0" >>/etc/init.d/$servicename
                chmod +x /etc/init.d/$servicename
                _blue "配置开机自启"
                update-rc.d $servicename defaults
                echo
                _blue "操作完成,写入日志"
                #写入日志
                slog set service "add-service | $servicename | $datevar"
                _blue "开启服务"
                service $servicename start
                service $servicename status
                echo
                _green "文件位置 /etc/init.d/$servicename "
                echo
                _blue "现在可以使用service $servicename  start/stop/status"

            }

            servicedel() {

                #读取日志
                slog get service
                echo
                read -ep "请输入删除的服务名称: " servicename
                service $servicename status >/dev/null
                if [ $? == 4 ]; then
                    _red '服务不存在'
                    exit
                fi
                _red "停止服务"
                echo
                service $servicename stop
                _red "移除开机自启"
                echo
                update-rc.d -f $servicename remove

                echo
                _red "删除服务文件"
                echo
                rm -rf /etc/init.d/$servicename
                #重新加载 systemd 配置
                systemctl daemon-reload
                #写入日志
                slog set service "del-service | $servicename | $datevar"
                _blue "操作完成"
                echo

            }

            menuname='首页/系统/自定义服务/sysvinit'
            options=("添加服务" serviceadd "删除服务" servicedel)

            menu "${options[@]}"
        }

        #systemd
        systemdfun() {

            serviceadd() {

                _yellow "systemctl stop/start 服务名称"
                echo
                read -ep "请输入服务名称: " systemdname
                service $systemdname status >/dev/null
                if [ $? != 4 ]; then
                    _red '服务已存在'
                    exit
                fi
                echo '例子:'
                _yellow "xxx.sh  bash /root/xxx.sh  >> /root/systemdname.log 2>&1"
                _yellow "openvpn --config xxx.ovpn >> /root/openvpn.log 2>&1"
                echo
                read -ep "请输入执行程序: " execcmd
                echo
                echo '例子:'
                _yellow "pkill -f xxx(进程名)  or pkill -9 -f xxx"

                echo
                read -ep "请输入终止程序(默认取服务名): " stopcmd

                if [[ "$stopcmd" = "" ]]; then
                    stopcmd="pkill -f $systemdname"
                fi
                echo
                next
                _green "服务名称: $systemdname"
                echo
                _green "执行程序: $execcmd"
                echo
                _green "终止程序: $stopcmd"
                next
                echo
                waitinput
                _blue '开始配置'
                echo

                touch /usr/lib/systemd/system/$systemdname.service
                echo "[Unit]" >>/usr/lib/systemd/system/$systemdname.service
                echo "Description=$systemdname Service" >>/usr/lib/systemd/system/$systemdname.service
                echo "After=network.target" >>/usr/lib/systemd/system/$systemdname.service
                echo " " >>/usr/lib/systemd/system/$systemdname.service
                echo "[Service]" >>/usr/lib/systemd/system/$systemdname.service
                echo "ExecStart=$execcmd" >>/usr/lib/systemd/system/$systemdname.service
                echo "ExecStop=$stopcmd" >>/usr/lib/systemd/system/$systemdname.service
                echo " " >>/usr/lib/systemd/system/$systemdname.service
                echo "[Install]" >>/usr/lib/systemd/system/$systemdname.service
                echo "WantedBy=multi-user.target" >>/usr/lib/systemd/system/$systemdname.service
                echo

                _blue "配置开机自启"
                systemctl enable $systemdname
                echo
                _blue "操作完成,写入日志"
                #写入日志
                slog set systemctl "add-systemctl | $systemdname | $datevar"
                _blue "开启服务"
                systemctl start $systemdname
                systemctl status $systemdname
                echo
                echo "文件位置"
                echo "/usr/lib/systemd/system/$systemdname.service"
                echo "/etc/systemd/system/multi-user.target.wants/$systemdname.service"
                echo
                _blue "现在可以使用systemctl start/stop/status $systemdname"

            }

            servicedel() {

                #读取日志
                slog get systemctl
                echo
                read -ep "请输入删除的服务名称: " systemdname
                service $servicename status >/dev/null
                if [ $? == 4 ]; then
                    _red '服务不存在'
                    exit
                fi
                _red "停止服务"
                echo
                systemctl stop $systemdname
                _red "移除开机自启"
                echo
                systemctl disable $systemdname

                echo
                _red "删除服务文件"
                echo
                rm -rf /usr/lib/systemd/system/$systemdname.service
                rm -rf /etc/systemd/system/multi-user.target.wants/$systemdname.service
                #重新加载 systemd 配置
                systemctl daemon-reload
                #写入日志
                slog set systemctl "del-systemctl | $systemdname | $datevar"
                _blue "操作完成"
                echo

            }
            menuname='首页/系统/自定义服务/systemd'
            options=("添加服务" serviceadd "删除服务" servicedel)

            menu "${options[@]}"
        }

        #服务配置日志
        servicelogfun() {
            _yellow service
            echo
            #读取日志
            slog get service

            _yellow systemctl
            echo
            #读取日志
            slog get systemctl
            nextrun
        }

        menuname='首页/系统/自定义服务'
        options=("sysvinit" sysvinitfun "systemd" systemdfun "服务配置日志" servicelogfun)

        menu "${options[@]}"

    }

    swapfun() {
        if [[ $EUID -ne 0 ]]; then
            _red "Error:This script must be run as root"
            exit 1
        fi

        add_swap() {
            _green "请输入需要添加的swap,建议为内存的2倍"
            read -p "请输入swap数值:(纯数字 M)" swapsize

            #检查是否存在swapfile
            grep -q "swapfile" /etc/fstab

            #如果不存在将为其创建swap
            if [ $? -ne 0 ]; then
                fallocate -l ${swapsize}M /swapfile
                chmod 600 /swapfile
                mkswap /swapfile
                swapon /swapfile
                echo '/swapfile none swap defaults 0 0' >>/etc/fstab
                _blue "swap创建成功，并查看信息："
                cat /proc/swaps
                cat /proc/meminfo | grep Swap
            else
                _red "swapfile已存在，swap设置失败，请先运行脚本删除swap后重新设置！"
            fi
        }

        del_swap() {
            #检查是否存在swapfile
            grep -q "swapfile" /etc/fstab

            #如果存在就将其移除
            if [ $? -eq 0 ]; then
                _green "swapfile已发现，正在将其移除..."
                sed -i '/swapfile/d' /etc/fstab
                echo "3" >/proc/sys/vm/drop_caches
                swapoff -a
                rm -f /swapfile
                _green "swap已删除！"
            else
                _red "swapfile未发现，swap删除失败！"
            fi
        }

        menuname='首页/系统/swap管理'
        options=("添加swap" add_swap "删除swap" del_swap)

        menu "${options[@]}"
    }

    

    menuname='首页/系统'
    echo "systemfun" >$installdir/config/lastfun
    options=("系统信息" sysinfo "ps进程搜索" pssearch "setauthorized_keys写入ssh公钥" sshsetpub "rootsshkeypubonly仅密钥root" sshpubonly "synctime同步时间" synchronization_time "sshgetpub生成密钥对" sshgetpub "catauthorized_keys查看公钥" catkeys "crontab计划任务" crontabfun "swap管理" swapfun "rclocal配置" rclocalfun "自定义服务" customservicefun "系统检查" systemcheck "性能测试" performancetest)

    menu "${options[@]}"

}
