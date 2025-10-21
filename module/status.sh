statusfun() {
    beforeMenu(){
    _blue "> ---  当前目录: [ $(pwd) ] ---- < v:${branch}-$selfversion"
    echo
    _yellow "当前菜单: $menuname "
    echo
    }

    #检测大小
    calc_size() {
        local raw=$1
        local total_size=0
        local num=1
        local unit="KB"
        if ! [[ ${raw} =~ ^[0-9]+$ ]]; then
            echo ""
            return
        fi
        if [ "${raw}" -ge 1073741824 ]; then
            num=1073741824
            unit="TB"
        elif [ "${raw}" -ge 1048576 ]; then
            num=1048576
            unit="GB"
        elif [ "${raw}" -ge 1024 ]; then
            num=1024
            unit="MB"
        elif [ "${raw}" -eq 0 ]; then
            echo "${total_size}"
            return
        fi
        total_size=$(awk 'BEGIN{printf "%.1f", '"$raw"' / '$num'}')
        echo "${total_size} ${unit}"
    }

    to_kibyte() {
        local raw=$1
        awk 'BEGIN{printf "%.0f", '"$raw"' / 1024}'
    }

    calc_sum() {
        local arr=("$@")
        local s
        s=0
        for i in "${arr[@]}"; do
            s=$((s + i))
        done
        echo ${s}
    }
    #获取操作系统的信息
    get_opsy() {
        [ -f /etc/redhat-release ] && awk '{print $0}' /etc/redhat-release && return
        [ -f /etc/os-release ] && awk -F'[= "]' '/PRETTY_NAME/{print $3,$4,$5}' /etc/os-release && return
        [ -f /etc/lsb-release ] && awk -F'[="]+' '/DESCRIPTION/{print $2}' /etc/lsb-release && return
    }

    get_power_mode() {
        local mode=""
        if command -v powerprofilesctl >/dev/null 2>&1; then
            # Fedora / Ubuntu 新系统
            mode=$(powerprofilesctl get 2>/dev/null)
        elif [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
            # 通用 CPU governor
            mode=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)
        elif command -v cpupower >/dev/null 2>&1; then
            mode=$(cpupower frequency-info --policy 2>/dev/null | awk -F: '/current policy/ {print $2}' | awk '{print $1}')
        fi

        case "$mode" in
            performance) echo "performance";;
            balanced|ondemand|schedutil) echo "ondemand";;
            power-saver|powersave) echo "powersave";;
            *) echo "";;
        esac
    }



    sysinfo() {
        cname=$(awk -F: '/model name/ {name=$2} END {print name}' /proc/cpuinfo | sed 's/^[ \t]*//;s/[ \t]*$//')
        cores=$(awk -F: '/^processor/ {core++} END {print core}' /proc/cpuinfo)
        freq=$(awk -F'[ :]' '/cpu MHz/ {print $4;exit}' /proc/cpuinfo)
        ccache=$(awk -F: '/cache size/ {cache=$2} END {print cache}' /proc/cpuinfo | sed 's/^[ \t]*//;s/[ \t]*$//')
        cpu_aes=$(grep -i 'aes' /proc/cpuinfo)
        cpu_virt=$(grep -Ei 'vmx|svm' /proc/cpuinfo)
        totalram=$(free | awk '/Mem/ {print $2}')
        totalram=$(calc_size "$totalram")
        useram=$(free | awk '/Mem/ {print $3}')
        useram=$(calc_size "$useram")
        swap=$(free | awk '/Swap/ {print $2}')
        swap=$(calc_size "$swap")
        uswap=$(free | awk '/Swap/ {print $3}')
        uswap=$(calc_size "$uswap")
        up=$(awk '{a=$1/86400;b=($1%86400)/3600;c=($1%3600)/60} {printf("%d days, %d hour %d min\n",a,b,c)}' /proc/uptime)
        opsy=$(get_opsy)
        arch=$(uname -m)
        power_mode=$(get_power_mode)
        if _exists "getconf"; then
            lbit=$(getconf LONG_BIT)
        else
            echo "${arch}" | grep -q "64" && lbit="64" || lbit="32"
        fi
        kern=$(uname -r)
        in_kernel_no_swap_total_size=$(

            df -t simfs -t ext2 -t ext3 -t ext4 -t btrfs -t xfs -t vfat -t ntfs --total 2>/dev/null | grep total | awk '{ print $2 }'
        )
        swap_total_size=$(free -k | grep Swap | awk '{print $2}')
        zfs_total_size=$(to_kibyte "$(calc_sum "$(zpool list -o size -Hp 2>/dev/null)")")
        disk_total_size=$(calc_size $((swap_total_size + in_kernel_no_swap_total_size + zfs_total_size)))
        in_kernel_no_swap_used_size=$(

            df -t simfs -t ext2 -t ext3 -t ext4 -t btrfs -t xfs -t vfat -t ntfs --total 2>/dev/null | grep total | awk '{ print $3 }'
        )
        swap_used_size=$(free -k | grep Swap | awk '{print $3}')
        zfs_used_size=$(to_kibyte "$(calc_sum "$(zpool list -o allocated -Hp 2>/dev/null)")")
        disk_used_size=$(calc_size $((swap_used_size + in_kernel_no_swap_used_size + zfs_used_size)))
        tcpctrl=$(sysctl net.ipv4.tcp_congestion_control | awk -F ' ' '{print $3}')

        _exists "dmesg" && virtualx="$(dmesg 2>/dev/null)"
        if _exists "dmidecode"; then
            sys_manu="$(dmidecode -s system-manufacturer 2>/dev/null)"
            sys_product="$(dmidecode -s system-product-name 2>/dev/null)"
            sys_ver="$(dmidecode -s system-version 2>/dev/null)"
        else
            sys_manu=""
            sys_product=""
            sys_ver=""
        fi
        if grep -qa docker /proc/1/cgroup; then
            virt="Docker"
        elif grep -qa lxc /proc/1/cgroup; then
            virt="LXC"
        elif grep -qa container=lxc /proc/1/environ; then
            virt="LXC"
        elif [[ -f /proc/user_beancounters ]]; then
            virt="OpenVZ"
        elif [[ "${virtualx}" == *kvm-clock* ]]; then
            virt="KVM"
        elif [[ "${sys_product}" == *KVM* ]]; then
            virt="KVM"
        elif [[ "${cname}" == *KVM* ]]; then
            virt="KVM"
        elif [[ "${cname}" == *QEMU* ]]; then
            virt="KVM"
        elif [[ "${virtualx}" == *"VMware Virtual Platform"* ]]; then
            virt="VMware"
        elif [[ "${sys_product}" == *"VMware Virtual Platform"* ]]; then
            virt="VMware"
        elif [[ "${virtualx}" == *"Parallels Software International"* ]]; then
            virt="Parallels"
        elif [[ "${virtualx}" == *VirtualBox* ]]; then
            virt="VirtualBox"
        elif [[ -e /proc/xen ]]; then
            if grep -q "control_d" "/proc/xen/capabilities" 2>/dev/null; then
                virt="Xen-Dom0"
            else
                virt="Xen-DomU"
            fi
        elif [ -f "/sys/hypervisor/type" ] && grep -q "xen" "/sys/hypervisor/type"; then
            virt="Xen"
        elif [[ "${sys_manu}" == *"Microsoft Corporation"* ]]; then
            if [[ "${sys_product}" == *"Virtual Machine"* ]]; then
                if [[ "${sys_ver}" == *"7.0"* || "${sys_ver}" == *"Hyper-V" ]]; then
                    virt="Hyper-V"
                else
                    virt="Microsoft Virtual Machine"
                fi
            fi
        else
            virt="Dedicated"
        fi

        echo
        if [ -n "$cname" ]; then
            echo " CPU Model          : $(_blue "$cname")"
        else
            echo " CPU Model          : $(_blue "CPU model not detected")"
        fi
        if [ -n "$freq" ]; then
            echo " CPU Cores          : $(_blue "$cores @ $freq MHz")"
        else
            echo " CPU Cores          : $(_blue "$cores")"
        fi
        if [ -n "$ccache" ]; then
            echo " CPU Cache          : $(_blue "$(calc_size $ccache)")"
        fi
        if [ -n "$cpu_aes" ]; then
            echo " AES-NI             : $(_green "Enabled")"
        else
            echo " AES-NI             : $(_red "Disabled")"
        fi
        if [ -n "$cpu_virt" ]; then
            echo " VM-x/AMD-V         : $(_green "Enabled")"
        else
            echo " VM-x/AMD-V         : $(_red "Disabled")"
        fi
        echo " Total Disk         : $(_yellow "$disk_total_size") $(_blue "($disk_used_size Used)")"
        echo " Total Mem          : $(_yellow "$totalram") $(_blue "($useram Used)")"
        if [ "$swap" != "0" ]; then
            echo " Total Swap         : $(_blue "$swap ($uswap Used)")"
        fi
        echo " System uptime      : $(_blue "$up")"
        echo " OS                 : $(_blue "$opsy")"
        echo " Arch               : $(_blue "$arch ($lbit Bit)")"
        echo " Kernel             : $(_blue "$kern")"
        echo " TCP CC             : $(_yellow "$tcpctrl")"
        echo " Virtualization     : $(_blue "$virt")"
        if [ -n "$power_mode" ]; then
        echo " Power Mode         : $(_blue "$power_mode")"
        fi
    }

    #磁盘详细信息
    diskinfo() {
        _blue "--fdisk信息--"
        fdisk -l
        _blue "--lsblk块设备信息--"
        lsblk
        _blue "--分区信息--"
        df -Th
        echo
    }

    #实时网速
    Realtimenetworkspeedfun() {
        if _exists 'bmon'; then
            bmon
        else
            echo "bmon 未安装,正在安装..."
            apt-get install bmon -y
            bmon
        fi
    }

    #网络信息
    netinfo() {
        echo
        _blue "--本机IP--" 
        ifconfig -a | grep "inet "

        _blue "--路由表--" 
        route -n
        _blue "--活动连接--"
        tcpcount=$(netstat -antp | grep ESTABLISHED | wc -l)
        udpcount=$(netstat -antp | grep -v ESTABLISHED | wc -l)
        #计算百分比
        
        #计算总连接数
        totalcount=$(($tcpcount + $udpcount))
        #计算百分比
        cent=$(echo "scale=2; $totalcount / 65535 * 100" | bc)
        #最低1%
        if [ $(echo "$cent < 1" | bc) -eq 1 ]; then
            cent=1
        fi
        #输出结果
        echo
        echo "TCP连接数: $tcpcount UDP连接数: $udpcount 总计：$totalcount /65535 ($cent%)"
        echo
        _blue "--监听端口--" 
        netstat -tunlp
        echo
        _blue "--公网IP--" 
        echo "From cip.cc:" $(curl cip.cc)
        echo
        echo "From ifconfig.me:" $(curl ifconfig.me)
        echo
        _blue "--ip地区--" 
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
        _blue "--IP连接数--" 
        waitinput
        echo '   数量 ip'
        netstat -na | grep ESTABLISHED | awk '{print$5}' | awk -F : '{print$1}' | sort | uniq -c | sort -r
        echo
        _blue "--ssh失败记录--" 
        waitinput
        lastb | grep root | awk '{print $3}' | sort | uniq
        echo
    }


    menuname='首页/状态'
    echo "statusfun" >$installdir/config/lastfun
    options=("系统信息" sysinfo "磁盘信息" diskinfo "网络信息" netinfo "实时网速" Realtimenetworkspeedfun )

    menu "${options[@]}"
}
