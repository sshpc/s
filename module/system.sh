systemfun() {
    beforeMenu(){
    _blue "> ---  当前目录: [ $(pwd) ] ---- < v:$selfversion"
    echo
    _yellow "当前菜单: $menuname "
    echo
    }

    # 获取系统安装时间
    get_system_install_time() {
        local install_time_raw=""
        local install_time="未知"

        if [[ -d /var/log/installer ]]; then
            install_time_raw=$(ls -ld /var/log/installer | awk '{print $6,$7,$8}')
            if [[ -n "$install_time_raw" ]]; then
                install_time=$(date -d "$install_time_raw" +%F 2>/dev/null)
                [[ -n "$install_time" ]] && echo "$install_time" && return 0
            fi
        elif [[ -f /root/anaconda-ks.cfg ]]; then
            install_time_raw=$(stat -c '%y' /root/anaconda-ks.cfg 2>/dev/null)
            if [[ -n "$install_time_raw" ]]; then
                install_time=$(date -d "$install_time_raw" +%F 2>/dev/null)
                [[ -n "$install_time" ]] && echo "$install_time" && return 0
            fi
        fi

        if [[ -d /lost+found ]]; then
            install_time_raw=$(stat -c '%w' /lost+found 2>/dev/null)
            if [[ "$install_time_raw" != "-" && -n "$install_time_raw" ]]; then
                install_time=$(date -d "$install_time_raw" +%F 2>/dev/null)
                [[ -n "$install_time" ]] && echo "$install_time" && return 0
            fi
        fi

        root_dev=$(df / | tail -1 | awk '{print $1}')
        if command -v tune2fs >/dev/null 2>&1; then
            install_time_raw=$(sudo tune2fs -l "$root_dev" 2>/dev/null | grep 'Filesystem created:' | head -1 | awk -F': ' '{print $2}')
            if [[ -n "$install_time_raw" ]]; then
                install_time=$(date -d "$install_time_raw" +%F 2>/dev/null)
                [[ -n "$install_time" ]] && echo "$install_time" && return 0
            fi
        fi

        install_time_raw=$(stat -c '%y' / 2>/dev/null)
        if [[ -n "$install_time_raw" ]]; then
            install_time=$(date -d "$install_time_raw" +%F 2>/dev/null)
            [[ -n "$install_time" ]] && echo "$install_time" && return 0
        fi

        echo "未知"
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

        cname=$(awk -F: '/model name/ {name=$2} END {gsub(/^[ \t]+|[ \t]+$/, "", name); print name}' /proc/cpuinfo)
        cores=$(awk '/^processor/ {core++} END {print core}' /proc/cpuinfo)
        freq=$(awk '/cpu MHz/ {print $4; exit}' /proc/cpuinfo)
        ccache=$(awk -F: '/cache size/ {cache=$2} END {print cache}' /proc/cpuinfo | sed 's/^[ \t]*//;s/[ \t]*$//')
        cpu_aes=$(grep -i 'aes' /proc/cpuinfo)
        cpu_virt=$(grep -Ei 'vmx|svm' /proc/cpuinfo)

        free_out=$(free)
        totalram_kb=$(echo "$free_out" | awk '/^Mem:/ {print $2}')
        totalram=$(calc_size "$totalram_kb")
        useram_kb=$(echo "$free_out" | awk '/^Mem:/ {print $3}')
        useram=$(calc_size "$useram_kb")
        swap_total_kb=$(echo "$free_out" | awk '/^Swap:/ {print $2}')
        swap=$(calc_size "$swap_total_kb")
        uswap_kb=$(echo "$free_out" | awk '/^Swap:/ {print $3}')
        uswap=$(calc_size "$uswap_kb")

        up=$(awk '{a=$1/86400; b=($1%86400)/3600; c=($1%3600)/60} {printf "%d days, %d hour %d min\n", a, b, c}' /proc/uptime)
        installtime=$(get_system_install_time)

        opsy=$(get_opsy)
        arch=$(uname -m)
        power_mode=$(get_power_mode)
        lbit=$(command -v getconf &>/dev/null && getconf LONG_BIT || (echo "$arch" | grep -q "64" && echo 64 || echo 32))
        kern=$(uname -r)

        df_total=$(df -t simfs -t ext2 -t ext3 -t ext4 -t btrfs -t xfs -t vfat -t ntfs --total 2>/dev/null | grep '^total')
        in_kernel_total_kb=$(echo "$df_total" | awk '{print $2}')
        in_kernel_used_kb=$(echo "$df_total" | awk '{print $3}')
        zfs_total_kb=$(to_kibyte "$(calc_sum "$(zpool list -o size -Hp 2>/dev/null || echo 0)")")
        zfs_used_kb=$(to_kibyte "$(calc_sum "$(zpool list -o allocated -Hp 2>/dev/null || echo 0)")")
        disk_total=$(calc_size $((swap_total_kb + in_kernel_total_kb + zfs_total_kb)))
        disk_used=$(calc_size $((uswap_kb + in_kernel_used_kb + zfs_used_kb)))

        tcpctrl=$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}')
        [[ -x "$(command -v dmesg)" ]] && virtualx=$(dmesg 2>/dev/null)
        if command -v dmidecode &>/dev/null; then
            sys_manu=$(dmidecode -s system-manufacturer 2>/dev/null)
            sys_product=$(dmidecode -s system-product-name 2>/dev/null)
            sys_ver=$(dmidecode -s system-version 2>/dev/null)
        fi

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
        echo " System InstallTime : $(_blue "$installtime")"
        echo " OS                 : $(_blue "$opsy")"
        echo " Arch               : $(_blue "$arch ($lbit Bit)")"
        echo " Kernel             : $(_blue "$kern")"
        echo " TCP CC             : $(_yellow "$tcpctrl")"
        echo " Virtualization     : $(_blue "$virt")"
        [[ -n "$power_mode" ]] && echo " Power Mode         : $(_blue "$power_mode")"
    }

    # 同步时间（多时区选择 + UTC 偏移标识 + NTP 自动同步）
    synchronization_time() {
        local _ts_label_fmt
        _ts_label_fmt() {
            local off=${1:-$(date +%z)} sign hh mm
            sign=${off:0:1}; hh=$((10#${off:1:2})); mm=$((10#${off:3:2}))
            if (( mm == 0 )); then
                printf 'UTC%c%d' "$sign" "$hh"
            else
                printf 'UTC%c%d:%02d' "$sign" "$hh" "$mm"
            fi
        }
        echo "同步前时间: $(date '+%Y-%m-%d %H:%M:%S') $(_ts_label_fmt) ($(date +%Z))"
        echo

        local tz_list=(
            "UTC+0|UTC|协调世界时"
            "UTC+0|Europe/London|伦敦"
            "UTC+1|Europe/Berlin|中欧(柏林)"
            "UTC+2|Europe/Helsinki|赫尔辛基"
            "UTC+3|Europe/Moscow|莫斯科"
            "UTC+4|Asia/Dubai|迪拜"
            "UTC+5:30|Asia/Kolkata|印度(新德里)"
            "UTC+7|Asia/Bangkok|曼谷"
            "UTC+8|Asia/Shanghai|北京/上海"
            "UTC+8|Asia/Hong_Kong|香港"
            "UTC+8|Asia/Singapore|新加坡"
            "UTC+9|Asia/Tokyo|东京"
            "UTC+9|Asia/Seoul|首尔"
            "UTC+10|Australia/Sydney|悉尼"
            "UTC+12|Pacific/Auckland|奥克兰"
            "UTC-5|America/New_York|纽约"
            "UTC-6|America/Chicago|芝加哥"
            "UTC-7|America/Denver|丹佛"
            "UTC-8|America/Los_Angeles|洛杉矶"
        )

        _blue "选择时区 (UTC 为标准时间偏移，夏令时期间实际偏移可能变化):"
        local i offset zone desc
        for i in "${!tz_list[@]}"; do
            IFS='|' read -r offset zone desc <<<"${tz_list[$i]}"
            printf ' %2d) %-9s %-24s %s\n' "$((i + 1))" "$offset" "$zone" "$desc"
        done
        echo "  0) 取消"
        echo "  m) 手动输入时区 (如 Asia/Tokyo)"
        echo
        read -ep "请选择 [1-${#tz_list[@]}]: " choice

        if [[ -z "$choice" || "$choice" == 0 || "$choice" =~ ^[Qq]$ ]]; then
            _yellow "已取消时间同步"
            unset -f _ts_label_fmt
            return
        fi

        local tz
        if [[ "$choice" =~ ^[Mm]$ ]]; then
            read -ep "请输入时区名 (如 Asia/Tokyo): " tz
        elif [[ "$choice" =~ ^[0-9]+$ ]] && (( 10#$choice >= 1 && 10#$choice <= ${#tz_list[@]} )); then
            IFS='|' read -r offset zone desc <<<"${tz_list[$((10#$choice - 1))]}"
            tz="$zone"
        else
            _red "无效选择"
            unset -f _ts_label_fmt
            return
        fi

        if [[ -z "$tz" || ! -e "/usr/share/zoneinfo/$tz" ]]; then
            _red "时区不存在: ${tz:-空}"
            unset -f _ts_label_fmt
            return
        fi

        if [ -f /etc/localtime ]; then
            cp -a /etc/localtime /etc/localtime.bak."$(date +%Y%m%d%H%M%S)"
        fi
        ln -snf "/usr/share/zoneinfo/$tz" /etc/localtime
        echo "$tz" >/etc/timezone 2>/dev/null || true
        command -v timedatectl &>/dev/null && timedatectl set-timezone "$tz" 2>/dev/null
        command -v timedatectl &>/dev/null && timedatectl set-local-rtc 0 2>/dev/null

        local ntp_ok=0
        if command -v timedatectl &>/dev/null && timedatectl set-ntp yes 2>/dev/null; then
            ntp_ok=1
            _green "已启用 systemd-timesyncd 自动同步"
        fi
        if (( ntp_ok == 0 )); then
            if ! command -v ntpdate &>/dev/null; then
                check_and_install ntpsec
                command -v ntpdate &>/dev/null || check_and_install ntp
            fi
            if command -v ntpdate &>/dev/null; then
                if ntpdate -u pool.ntp.org 2>/dev/null; then
                    ntp_ok=1
                    _green "ntpdate 同步完成"
                else
                    _yellow "ntpdate 同步失败，请检查网络"
                fi
            fi
        fi
        (( ntp_ok == 0 )) && _yellow "未能启用自动同步，请手动检查 NTP 服务"

        command -v hwclock &>/dev/null && hwclock -w 2>/dev/null || true
        for service in rsyslog cron; do
            systemctl is-active --quiet "$service" 2>/dev/null && systemctl restart "$service" 2>/dev/null
        done

        echo
        _green "同步后时间: $(date '+%Y-%m-%d %H:%M:%S') $(_ts_label_fmt) ($(date +%Z))"
        _green "时区已设为: $tz"
        echo "时间同步完成"
        unset -f _ts_label_fmt
    }
    # 仅秘钥rootssh登录
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
    # 生成ssh密钥对
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
    # 往authorized_keys写入公钥
    sshsetpub() {
        echo "请填入ssh公钥 (Write into /root/.ssh/authorized_keys)"
        read -ep "请粘贴至命令行回车(Please paste and enter): " sshpub
        echo -e $sshpub >>/root/.ssh/authorized_keys
        echo
        echo "ssh公钥写入成功Write success"
        echo
    }
    # 查看本机authorized_keys
    catkeys() {
        cat /root/.ssh/authorized_keys
    }
    
    
    # 系统检查（全面高危项，分组展示，问题优先）
    systemcheck() {
        local _issue=0 _totalrisk=0
        _sc_hdr() {
            (( _issue > 0 )) && printf '\n'
            _blue "▸ $1"
            _issue=0
        }
        _sc_risk() {
            printf '  \033[1;33m[!]\033[0m %s\n' "$1"
            _issue=$((_issue + 1)); _totalrisk=$((_totalrisk + 1))
        }
        _sc_ok() { printf '  \033[0;32m[OK]\033[0m %s\n' "$1"; }
        _sc_info() { printf '       %s\n' "$1"; }
        # 判断配置指令：取第一个有效（未注释）值
        _sc_cfgval() { awk -v k="$1" '$1==k && $0 !~ /^[[:space:]]*#/ {print $2; exit}' "$2" 2>/dev/null; }

        echo "════════════════ 系统安全全面检查 ════════════════"

        _sc_hdr "账号与口令策略"

        local maxdays mindays minlen warnage
        maxdays=$(_sc_cfgval PASS_MAX_DAYS /etc/login.defs)
        mindays=$(_sc_cfgval PASS_MIN_DAYS /etc/login.defs)
        minlen=$(_sc_cfgval PASS_MIN_LEN /etc/login.defs)
        warnage=$(_sc_cfgval PASS_WARN_AGE /etc/login.defs)
        [[ -n "$maxdays" ]] && (( maxdays > 90 )) && _sc_risk "密码最长有效期 ${maxdays} 天（建议 ≤90）"
        [[ -n "$mindays" ]] && (( mindays < 1 )) && _sc_risk "密码最小修改间隔 ${mindays} 天（建议 ≥1）"
        [[ -n "$minlen" ]] && (( minlen < 8 )) && _sc_risk "密码最小长度 ${minlen}（建议 ≥8）"
        [[ -n "$warnage" ]] && (( warnage < 7 )) && _sc_risk "密码过期提醒 ${warnage} 天（建议 ≥7）"

        local uid0 uid500 hollow locked
        uid0=$(awk -F: '$3==0 {print $1}' /etc/passwd 2>/dev/null | paste -sd, -)
        [[ "$uid0" != "root" && -n "$uid0" ]] && _sc_risk "存在非 root 的 UID=0 账号: $uid0"
        uid500=$(awk -F: '$3>=500 && $1!="nobody" {print $1"("$3")"}' /etc/passwd 2>/dev/null)
        [[ -n "$uid500" ]] && _sc_risk "普通/高 UID 账号需确认: $uid500"
        hollow=$(awk -F: '($2=="") {print $1}' /etc/shadow 2>/dev/null | paste -sd, -)
        [[ -n "$hollow" ]] && _sc_risk "空口令账号: $hollow"
        locked=$(awk -F: '($2=="!!" || $2=="!") {print $1}' /etc/shadow 2>/dev/null | wc -l)
        (( locked > 0 )) && _sc_info "锁定/未设密码账号共 $locked 个（多为系统账号，正常）"

        local stale
        stale=$(awk -F: -v now=$(( $(date +%s) / 86400 )) 'NR==FNR && $3>=500 {uid[$1]=1; next} uid[$1] && $2!="!!" && $2!="*" && $2!="" && (now-$3)>180 {print $1}' /etc/passwd /etc/shadow 2>/dev/null | paste -sd, -)
        [[ -n "$stale" ]] && _sc_info "密码超过 180 天未修改的账号: $stale"

        local tally=0
        if grep -Eiq '^[[:space:]]*auth[[:space:]].*pam_tally2\.so' /etc/pam.d/sshd 2>/dev/null ||
           grep -Eiq '^[[:space:]]*auth[[:space:]].*pam_faillock\.so' /etc/pam.d/system-auth /etc/pam.d/password-auth 2>/dev/null; then
            tally=1
        fi
        (( tally == 0 )) && _sc_risk "未启用登录失败锁定（pam_tally2/faillock）"

        _sc_hdr "SSH 服务加固"

        local sshd=/etc/ssh/sshd_config
        if [[ -r "$sshd" ]]; then
            local permitroot pwauth emptypass x11 forward
            permitroot=$(_sc_cfgval PermitRootLogin "$sshd")
            pwauth=$(_sc_cfgval PasswordAuthentication "$sshd")
            emptypass=$(_sc_cfgval PermitEmptyPasswords "$sshd")
            x11=$(_sc_cfgval X11Forwarding "$sshd")
            forward=$(_sc_cfgval AllowTcpForwarding "$sshd")
            [[ "$permitroot" == "yes" ]] && _sc_risk "PermitRootLogin=yes（允许 root 直接登录）"
            [[ "$pwauth" == "yes" ]] && _sc_risk "PasswordAuthentication=yes（建议仅密钥登录）"
            [[ "$emptypass" == "yes" ]] && _sc_risk "PermitEmptyPasswords=yes（允许空密码）"
            [[ "$x11" == "yes" ]] && _sc_risk "X11Forwarding=yes（存在隧道风险）"
            [[ "$forward" == "yes" ]] && _sc_info "AllowTcpForwarding=yes（按需确认）"
            local sshport
            sshport=$(_sc_cfgval Port "$sshd"); sshport=${sshport:-22}
            _sc_info "SSH 端口: $sshport / 协议: $(_sc_cfgval Protocol "$sshd")"
        else
            _sc_info "未找到 sshd_config，跳过 SSH 配置检查"
        fi

        local authlog=/var/log/secure
        [[ -e "$authlog" ]] || authlog=/var/log/auth.log
        [[ -r "$authlog" ]] || _sc_info "未找到认证日志（secure / auth.log）"

        _sc_hdr "暴力破解与登录异常"

        local fail
        fail=$(lastb 2>/dev/null | awk 'NF>2 && $1!="btmp" {print $3}' | sort | uniq -c | sort -rn | head -5)
        [[ -n "$fail" ]] && { _sc_risk "登录失败记录（来源 / 次数）:"; while IFS= read -r l; do _sc_info "$l"; done <<<"$fail"; } || _sc_ok "无 lastb 登录失败记录"

        if [[ -r "$authlog" ]]; then
            local brute
            brute=$(awk '/Failed password|Invalid user|authentication failure/ {
                for(i=1;i<=NF;i++) if($i=="from" || $i=="rhost") {print $(i+1); break}
            }' "$authlog" 2>/dev/null | sort | uniq -c | sort -rn | head -5)
            [[ -n "$brute" ]] && { _sc_risk "SSH 暴力破解迹象（来源 / 次数）:"; while IFS= read -r l; do _sc_info "$l"; done <<<"$brute"; } || _sc_ok "未发现 SSH 暴力破解记录"
            local inv
            inv=$(grep -c 'Invalid user' "$authlog" 2>/dev/null)
            (( inv > 0 )) && _sc_risk "无效用户名尝试 $inv 次"
        fi

        local recentroot
        recentroot=$(last -n 50 2>/dev/null | awk '$1=="root" && $NF ~ /^[0-9]+\.[0-9]+/ {print $NF}' | sort -u | paste -sd, -)
        [[ -n "$recentroot" ]] && _sc_info "近期 root 远程登录来源: $recentroot"

        _sc_hdr "网络与端口暴露"

        local telnet=0
        command -v systemctl &>/dev/null && systemctl is-active --quiet telnet.socket 2>/dev/null && telnet=1
        grep -Eiq '^[[:space:]]*disable[[:space:]]*=[[:space:]]*no' /etc/xinetd.d/telnet* 2>/dev/null && telnet=1
        (( telnet == 1 )) && _sc_risk "Telnet 服务已启用（明文传输，高危）"

        local fw=0
        command -v systemctl &>/dev/null && systemctl is-active --quiet firewalld 2>/dev/null && fw=1
        command -v iptables &>/dev/null && iptables -S 2>/dev/null | grep -qv '^-P .* ACCEPT' && fw=1
        command -v nft &>/dev/null && nft list ruleset 2>/dev/null | grep -q 'policy drop' && fw=1
        (( fw == 1 )) && _sc_ok "防火墙处于启用状态" || _sc_risk "防火墙未启用或未设置默认拒绝策略"

        local fwd rpfilter
        fwd=$(sysctl -n net.ipv4.ip_forward 2>/dev/null)
        rpfilter=$(sysctl -n net.ipv4.conf.all.rp_filter 2>/dev/null)
        [[ "$fwd" == "1" ]] && _sc_risk "IP 转发已开启，确认是否为网关用途"
        [[ "$rpfilter" == "0" ]] && _sc_risk "未启用反向路径过滤（rp_filter=0，易受欺骗）"

        local listen
        listen=$(ss -H -lntup 2>/dev/null | awk '{print $5, $7}' | grep -v '127.0.0.1\|::1' | head -10)
        [[ -n "$listen" ]] && { _sc_info "对外监听端口（前10）:"; while IFS= read -r l; do _sc_info "$l"; done <<<"$listen"; }

        local hostsdeny
        hostsdeny=$(grep -E '^[[:space:]]*(sshd|ALL)[[:space:]]*:' /etc/hosts.deny 2>/dev/null | grep -v '^#' | head -3)
        [[ -z "$hostsdeny" ]] && _sc_info "hosts.deny 未设置显式拒绝规则（依赖防火墙）"

        _sc_hdr "文件系统与权限"

        for f in /etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config; do
            [[ -e "$f" ]] || continue
            local mod
            mod=$(stat -c '%a' "$f" 2>/dev/null)
            case "$f" in
                /etc/passwd) [[ "$mod" != "644" && "$mod" != "655" ]] && _sc_risk "$f 权限异常($mod，建议 644)";;
                /etc/shadow) [[ "$mod" != "000" && "$mod" != "600" && "$mod" != "640" ]] && _sc_risk "$f 权限异常($mod，建议 600/000)";;
                /etc/sudoers) [[ "$mod" != "440" ]] && _sc_risk "$f 权限异常($mod，建议 440)";;
            esac
        done

        local sticky
        sticky=$(find /tmp /var/tmp -maxdepth 0 -type d ! -perm -1000 2>/dev/null | paste -sd, -)
        [[ -n "$sticky" ]] && _sc_risk "临时目录缺少 sticky 位: $sticky"

        local sroot
        sroot=$(find / -xdev -perm -4000 -user root -type f 2>/dev/null | head -5)
        [[ -n "$sroot" ]] && _sc_info "SUID root 文件（前5，确认必要性）:" && while IFS= read -r l; do _sc_info "$l"; done <<<"$sroot"

        _sc_hdr "进程与计划任务"

        local zombies
        zombies=$(ps -eo stat,comm 2>/dev/null | awk '$1 ~ /^Z/ {print $2}' | sort | uniq -c | sort -rn | head -5)
        [[ -n "$zombies" ]] && { _sc_risk "僵尸进程:"; while IFS= read -r l; do _sc_info "$l"; done <<<"$zombies"; } || _sc_ok "无僵尸进程"

        local usercron
        usercron=$(for u in $(awk -F: '$3>=500 {print $1}' /etc/passwd 2>/dev/null); do crontab -l -u "$u" 2>/dev/null | grep -qv '^#' && echo "$u"; done | paste -sd, -)
        [[ -n "$usercron" ]] && _sc_info "存在用户级 crontab 的账号: $usercron"

        local weirdcron
        weirdcron=$(grep -RE 'curl|wget|/dev/tcp|base64 -d' /etc/cron* /var/spool/cron 2>/dev/null | grep -v '^#' | head -5)
        [[ -n "$weirdcron" ]] && { _sc_risk "计划任务含可疑下载/反弹命令:"; while IFS= read -r l; do _sc_info "$l"; done <<<"$weirdcron"; }

        _sc_hdr "日志与审计"

        local logfiles="/var/log/secure /var/log/auth.log /var/log/messages /var/log/cron /var/log/boot.log /var/log/dmesg"
        local missing="" found=0
        for f in $logfiles; do [[ -e "$f" ]] && found=$((found+1)) || missing="$missing $f"; done
        (( found == 0 )) && _sc_risk "常见日志文件均缺失，审计可能未开启"
        [[ -n "$missing" ]] && _sc_info "不存在的日志(按发行版可能正常):$missing"

        command -v systemctl &>/dev/null && systemctl is-active --quiet rsyslog 2>/dev/null && _sc_ok "rsyslog 日志服务运行中" || _sc_info "rsyslog 未运行（可能使用 systemd-journald）"
        command -v auditctl &>/dev/null && { auditctl -s 2>/dev/null | grep -q 'enabled 1' && _sc_ok "auditd 审计已启用" || _sc_risk "auditd 已安装但未启用"; } || _sc_info "未安装 auditd（可选加固）"

        _sc_hdr "内核与系统加固"

        local aslr core
        aslr=$(sysctl -n kernel.randomize_va_space 2>/dev/null)
        [[ -n "$aslr" && "$aslr" != "2" ]] && _sc_risk "ASLR 未完全开启（randomize_va_space=$aslr，建议 2）"
        core=$(ulimit -c 2>/dev/null)
        [[ "$core" != "0" ]] && _sc_info "core dump 未禁用（ulimit -c=$core）"

        local keyfiles="/bin/ls /bin/login /etc/passwd /bin/ps /etc/shadow"
        for f in $keyfiles; do
            [[ -e "$f" ]] && _sc_info "$(stat -c '%y  %n' "$f" 2>/dev/null | cut -d. -f1)"
        done

        echo
        echo "════════════════ 检查结束 · 共发现 ${_totalrisk} 处风险 ════════════════"
        unset -f _sc_hdr _sc_risk _sc_ok _sc_info _sc_cfgval
    }

    
    processquery() {
        read -rp "请输入要搜索的进程名或服务关键词: " -e keyword
        echo

        declare -A seen_pids

        if [[ -z "$keyword" ]]; then
            pids=$(ps -e -o pid=)
        else
            pids=$(ps -eo pid,cmd --no-headers | grep -i "$keyword" | grep -v "grep" | awk '{print $1}')
            svc_pids=$(systemctl list-units --type=service --all --no-legend 2>/dev/null | grep -i "$keyword" | awk '{print $1}' | \
                while read svc; do
                    mainpid=$(systemctl show -p MainPID "$svc" 2>/dev/null | cut -d= -f2)
                    [[ "$mainpid" != "0" ]] && echo "$mainpid"
                done)
            pids=$(echo -e "$pids\n$svc_pids" | sort -u)
        fi

        [[ -z "$pids" ]] && { echo "未找到匹配的进程或服务。"; return 1; }

        for pid in $pids; do
            [[ ! -d "/proc/$pid" ]] && continue
            [[ -n "${seen_pids[$pid]}" ]] && continue
            seen_pids[$pid]=1

            service_name=$(systemctl list-units --type=service --all --no-legend 2>/dev/null | \
                awk '{print $1}' | while read svc; do
                    mainpid=$(systemctl show -p MainPID "$svc" 2>/dev/null | cut -d= -f2)
                    [[ "$mainpid" == "$pid" ]] && echo "$svc"
                done | head -n1)
            [[ -z "$service_name" ]] && service_name="非服务"

            cmd=$(cat /proc/$pid/cmdline 2>/dev/null | tr '\0' ' ')
            [[ -z "$cmd" ]] && cmd="未知"
            exe_path=$(readlink -f "/proc/$pid/exe" 2>/dev/null)
            [[ -z "$exe_path" ]] && exe_path="未知"
            ctime=$(stat -c "%y" "$exe_path" 2>/dev/null | cut -c1-7)
            [[ -z "$ctime" ]] && ctime="未知"

            ports=$(ss -tulnp 2>/dev/null | awk -v pid="$pid" '
                $0 ~ pid {
                    split($5,a,":"); print a[length(a)]
                }' | sort -u | tr '\n' ',' | sed 's/,$//')
            [[ -z "$ports" ]] && ports="无"

            if [[ "$service_name" != "非服务" ]]; then
                echo "服务名: $service_name"
                echo "主进程 PID: $pid"
            else
                echo "进程 PID: $pid"
            fi
            echo "命令: $cmd"
            _green "执行文件: $exe_path"
            echo "创建时间: $ctime"
            _yellow "监听端口: $ports"
            echo "------------------------------------------------------------"
        done
    }


    
    # 计划任务crontab
    crontabfun() {
        crontabview() {
            echo
            _blue "当前用户的 crontab 任务:"
            echo
            crontab -l 2>/dev/null || _yellow "(无任务)"
            echo
            _blue "系统级定时任务 (/etc/crontab):"
            echo
            grep -v '^#' /etc/crontab 2>/dev/null | grep -v '^$' || _yellow "(无)"
        }

        crontabadd() {
            echo
            _yellow "常用示例:"
            echo "  0 2 * * * /root/backup.sh        (每天凌晨2点)"
            echo "  */5 * * * * /root/check.sh        (每5分钟)"
            echo "  0 0 * * 0 /root/clean.sh          (每周日)"
            echo "  0 9 1 * * /root/report.sh         (每月1号9点)"
            echo
            read -ep "请输入完整的cron表达式和命令: " cronline
            [[ -z "$cronline" ]] && { _yellow "已取消"; return; }
            (crontab -l 2>/dev/null; echo "$cronline") | crontab -
            _green "已添加: $cronline"
            echo
            _blue "当前任务列表:"
            crontab -l
        }

        crontabdel() {
            echo
            local lines=()
            while IFS= read -r line; do
                lines+=("$line")
            done < <(crontab -l 2>/dev/null)

            if [[ ${#lines[@]} -eq 0 ]]; then
                _yellow "当前没有定时任务"
                return
            fi

            _blue "当前定时任务:"
            for i in "${!lines[@]}"; do
                printf "  %d) %s\n" "$((i+1))" "${lines[$i]}"
            done
            echo
            read -ep "请输入要删除的序号 (多个用空格分隔, 回车取消): " choices
            [[ -z "$choices" ]] && { _yellow "已取消"; return; }

            local to_delete=()
            for c in $choices; do
                if [[ "$c" =~ ^[0-9]+$ ]] && (( c >= 1 && c <= ${#lines[@]} )); then
                    to_delete+=("$((c-1))")
                else
                    _red "无效序号: $c"
                fi
            done

            if [[ ${#to_delete[@]} -eq 0 ]]; then
                _red "没有有效的删除项"
                return
            fi

            local new_crontab=()
            for i in "${!lines[@]}"; do
                local skip=0
                for d in "${to_delete[@]}"; do
                    [[ "$i" == "$d" ]] && skip=1 && break
                done
                [[ $skip -eq 0 ]] && new_crontab+=("${lines[$i]}")
            done

            printf '%s\n' "${new_crontab[@]}" | crontab -
            _green "已删除 ${#to_delete[@]} 条任务"
            echo
            _blue "剩余任务:"
            crontab -l 2>/dev/null || _yellow "(无)"
        }

        menuname='首页/系统/crontab管理'
        options=("查看定时任务" crontabview "添加定时任务" crontabadd "删除定时任务" crontabdel)
        menu "${options[@]}"
    }

    sshconfigfun() {
        sshshowconfig() {
            echo
            _blue "当前 SSH 配置:"
            echo
            local port=$(grep -E '^Port\s' /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
            local permit_root=$(grep -E '^PermitRootLogin\s' /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
            local pass_auth=$(grep -E '^PasswordAuthentication\s' /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
            local pubkey_auth=$(grep -E '^PubkeyAuthentication\s' /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')

            echo "  端口:           ${port:-22 (默认)}"
            echo "  允许Root登录:   ${permit_root:-yes (默认)}"
            echo "  密码认证:       ${pass_auth:-yes (默认)}"
            echo "  公钥认证:       ${pubkey_auth:-yes (默认)}"
            echo
            _blue "已配置的公钥数量: $(wc -l < /root/.ssh/authorized_keys 2>/dev/null || echo 0)"
        }

        sshchangeport() {
            read -ep "请输入新SSH端口 (1-65535): " newport
            [[ -z "$newport" ]] && { _yellow "已取消"; return; }
            if ! [[ "$newport" =~ ^[0-9]+$ ]] || (( newport < 1 || newport > 65535 )); then
                _red "无效端口"
                return
            fi
            cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak."$(date +%Y%m%d%H%M%S)"
            sed -i '/^Port /d' /etc/ssh/sshd_config
            echo "Port $newport" >> /etc/ssh/sshd_config
            systemctl restart sshd
            _green "SSH端口已修改为 $newport (已重启sshd)"
        }

        sshtoggleroot() {
            local current=$(grep -E '^PermitRootLogin\s' /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
            [[ "$current" == "no" ]] && local newval="yes" || local newval="no"
            cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak."$(date +%Y%m%d%H%M%S)"
            sed -i '/^PermitRootLogin /d' /etc/ssh/sshd_config
            echo "PermitRootLogin $newval" >> /etc/ssh/sshd_config
            systemctl restart sshd
            _green "Root登录已设置为: $newval"
        }

        sshtogglepass() {
            local current=$(grep -E '^PasswordAuthentication\s' /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
            [[ "$current" == "no" ]] && local newval="yes" || local newval="no"
            cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak."$(date +%Y%m%d%H%M%S)"
            sed -i '/^PasswordAuthentication /d' /etc/ssh/sshd_config
            echo "PasswordAuthentication $newval" >> /etc/ssh/sshd_config
            systemctl restart sshd
            _green "密码认证已设置为: $newval"
        }

        sshkeyonly() {
            _red "将启用仅密钥登录 (禁用密码+允许Root)"
            waitinput
            cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak."$(date +%Y%m%d%H%M%S)"
            sed -i '/^PermitRootLogin /d; /^PasswordAuthentication /d; /^PubkeyAuthentication /d' /etc/ssh/sshd_config
            echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
            echo "PasswordAuthentication no" >> /etc/ssh/sshd_config
            echo "PubkeyAuthentication yes" >> /etc/ssh/sshd_config
            systemctl restart sshd
            _green "已启用仅密钥登录模式"
            _yellow "请确保已配置公钥，否则将无法登录！"
        }

        menuname='首页/系统/SSH配置'
        options=("查看SSH配置" sshshowconfig "修改SSH端口" sshchangeport "切换Root登录" sshtoggleroot "切换密码认证" sshtogglepass "仅密钥登录(推荐)" sshkeyonly "生成密钥对" sshgetpub "写入公钥" sshsetpub "查看公钥" catkeys "仅密钥root(快捷)" sshpubonly)
        menu "${options[@]}"
    }

    usermanagefun() {
        userlist() {
            echo
            _blue "系统用户列表:"
            echo
            printf "%-15s %-8s %-25s %-20s\n" "用户名" "UID" "HOME" "SHELL"
            printf "%-15s %-8s %-25s %-20s\n" "---------------" "--------" "-------------------------" "--------------------"
            while IFS=: read -r user _ uid _ _ home shell; do
                if (( uid >= 1000 )) || [[ "$user" == "root" ]]; then
                    printf "%-15s %-8d %-25s %-20s\n" "$user" "$uid" "$home" "$shell"
                fi
            done < /etc/passwd
            echo
            _blue "有sudo权限的用户:"
            grep -E '^sudo:|^wheel:' /etc/group 2>/dev/null | awk -F: '{print "  " $4}'
        }

        useraddfun() {
            read -ep "请输入新用户名: " username
            [[ -z "$username" ]] && { _yellow "已取消"; return; }
            if id "$username" &>/dev/null; then
                _red "用户 $username 已存在"
                return
            fi
            read -ep "是否添加sudo权限? (y/n, 默认n): " withsudo
            useradd -m -s /bin/bash "$username"
            passwd "$username"
            if [[ "$withsudo" == "y" ]]; then
                usermod -aG sudo "$username" 2>/dev/null || usermod -aG wheel "$username" 2>/dev/null
                _green "用户 $username 已添加sudo权限"
            fi
            _green "用户 $username 创建成功"
        }

        userdelfun() {
            userlist
            echo
            read -ep "请输入要删除的用户名: " username
            [[ -z "$username" ]] && { _yellow "已取消"; return; }
            if [[ "$username" == "root" ]]; then
                _red "不能删除root用户"
                return
            fi
            if ! id "$username" &>/dev/null; then
                _red "用户 $username 不存在"
                return
            fi
            read -ep "是否同时删除家目录? (y/n, 默认y): " delhome
            if [[ "$delhome" != "n" ]]; then
                userdel -r "$username"
            else
                userdel "$username"
            fi
            _green "用户 $username 已删除"
        }

        userpassfun() {
            read -ep "请输入用户名: " username
            [[ -z "$username" ]] && { _yellow "已取消"; return; }
            if ! id "$username" &>/dev/null; then
                _red "用户 $username 不存在"
                return
            fi
            passwd "$username"
        }

        useraddsudo() {
            userlist
            echo
            read -ep "请输入要添加sudo权限的用户名: " username
            [[ -z "$username" ]] && { _yellow "已取消"; return; }
            usermod -aG sudo "$username" 2>/dev/null || usermod -aG wheel "$username" 2>/dev/null
            _green "已为 $username 添加sudo权限"
        }

        userdelsudo() {
            read -ep "请输入要移除sudo权限的用户名: " username
            [[ -z "$username" ]] && { _yellow "已取消"; return; }
            gpasswd -d "$username" sudo 2>/dev/null || gpasswd -d "$username" wheel 2>/dev/null
            _green "已移除 $username 的sudo权限"
        }

        menuname='首页/系统/用户管理'
        options=("查看用户列表" userlist "创建用户" useraddfun "删除用户" userdelfun "修改密码" userpassfun "添加sudo权限" useraddsudo "移除sudo权限" userdelsudo)
        menu "${options[@]}"
    }

    envmanagefun() {
        envshow() {
            echo
            _blue "当前 Shell 环境变量 (PATH):"
            echo "$PATH" | tr ':' '\n' | while read -r p; do
                [[ -n "$p" ]] && echo "  $p"
            done
            echo
            _blue "/etc/environment:"
            cat /etc/environment 2>/dev/null || _yellow "(文件不存在)"
            echo
            _blue "/etc/profile.d/*.sh 自定义环境变量:"
            ls /etc/profile.d/*.sh 2>/dev/null | while read -r f; do
                echo "  --- $f ---"
                grep -v '^#' "$f" | grep -v '^$' | sed 's/^/    /'
            done
        }

        envaddpath() {
            read -ep "请输入要添加到PATH的目录路径: " newpath
            [[ -z "$newpath" ]] && { _yellow "已取消"; return; }
            if [[ ! -d "$newpath" ]]; then
                _red "目录 $newpath 不存在"
                return
            fi
            if echo "$PATH" | grep -q "$newpath"; then
                _yellow "$newpath 已在PATH中"
                return
            fi
            echo "export PATH=\"$newpath:\$PATH\"" >> /etc/profile.d/custom-path.sh
            export PATH="$newpath:$PATH"
            _green "已添加 $newpath 到PATH (持久化到 /etc/profile.d/custom-path.sh)"
        }

        envaddvar() {
            read -ep "请输入变量名: " varname
            [[ -z "$varname" ]] && { _yellow "已取消"; return; }
            read -ep "请输入变量值: " varvalue
            echo "export $varname=\"$varvalue\"" >> /etc/profile.d/custom-env.sh
            export "$varname=$varvalue"
            _green "已添加环境变量 $varname=$varvalue"
        }

        envdelvar() {
            _blue "自定义环境变量文件:"
            echo "  1) /etc/profile.d/custom-path.sh"
            echo "  2) /etc/profile.d/custom-env.sh"
            echo
            read -ep "选择文件 (1/2): " fchoice
            local target=""
            [[ "$fchoice" == "1" ]] && target="/etc/profile.d/custom-path.sh"
            [[ "$fchoice" == "2" ]] && target="/etc/profile.d/custom-env.sh"
            [[ -z "$target" ]] && { _yellow "已取消"; return; }
            if [[ ! -f "$target" ]]; then
                _yellow "文件不存在"
                return
            fi
            echo
            local lines=()
            while IFS= read -r line; do
                lines+=("$line")
            done < "$target"

            if [[ ${#lines[@]} -eq 0 ]]; then
                _yellow "文件为空"
                return
            fi

            for i in "${!lines[@]}"; do
                printf "  %d) %s\n" "$((i+1))" "${lines[$i]}"
            done
            echo
            read -ep "请输入要删除的行序号: " delidx
            if [[ "$delidx" =~ ^[0-9]+$ ]] && (( delidx >= 1 && delidx <= ${#lines[@]} )); then
                unset 'lines['"$((delidx-1))"']'
                printf '%s\n' "${lines[@]}" > "$target"
                _green "已删除"
            else
                _red "无效序号"
            fi
        }

        menuname='首页/系统/环境变量'
        options=("查看环境变量" envshow "添加PATH路径" envaddpath "添加环境变量" envaddvar "删除环境变量" envdelvar)
        menu "${options[@]}"
    }

    # 开机运行脚本 rc.local
    rclocalfun() {
        _blue '添加类似  nohup ... >> xxx.log 2>&1 &  最后行加 exit 0 '
        waitinput
        vim /etc/rc.local
    }

    # 自定义服务
    swapfun() {
        if [[ $EUID -ne 0 ]]; then
            _red "Error:This script must be run as root"
            exit 1
        fi

        add_swap() {
            _green "请输入需要添加的swap,建议为内存的2倍"
            read -p "请输入swap数值:(纯数字 M)" swapsize

            grep -q "swapfile" /etc/fstab

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
            grep -q "swapfile" /etc/fstab

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

    cleansyslogs() {
        
        local before=$(df --output=avail / | tail -1)

        _blue "清理 systemd 日志..."
        sudo journalctl --rotate
        sudo journalctl --vacuum-time=1d
        sudo journalctl --vacuum-size=300M 

        _blue "清理 APT 日志..."
        sudo rm -f /var/log/apt/*.log* /var/log/apt/*gz 2>/dev/null

        _blue "清理系统日志..."
        sudo find /var/log -type f \( -name "*.log" -o -name "*.gz" -o -name "*.1" \) -exec truncate -s 0 {} \; 2>/dev/null

        _blue "清理崩溃日志..."
        sudo rm -rf /var/crash/* 2>/dev/null

        local after=$(df --output=avail / | tail -1)
        local freed_kb=$((after - before))

        local freed_human
        if (( freed_kb >= 1048576 )); then
            freed_human=$(awk "BEGIN {printf \"%.2f GB\", $freed_kb/1048576}")
        elif (( freed_kb >= 1024 )); then
            freed_human=$(awk "BEGIN {printf \"%.2f MB\", $freed_kb/1024}")
        else
            freed_human="${freed_kb} KB"
        fi

        _green "[OK] 清理完成，共释放空间：$freed_human"
    }


    updateservername(){
        (
        set -euo pipefail

        if [ "$(id -u)" -ne 0 ]; then
            echo "错误：请使用root权限运行（sudo ./change_hostname.sh）"
            exit 1
        fi

        current_hostname=$(hostnamectl --static)
        echo "当前主机名：$current_hostname"
        echo "-------------------------"

        read -p "请输入新主机名（仅支持字母、数字、连字符'-'，不能以'-'开头/结尾，长度≤63）：" new_hostname

        # 验证主机名合法性（符合Linux主机名规范）
        validate_hostname() {
            local hostname="$1"
            if [[ ! "$hostname" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]$ ]]; then
                echo "错误：主机名格式无效！请重新输入。"
                return 1
            fi
            return 0
        }

        while ! validate_hostname "$new_hostname"; do
            read -p "请重新输入新主机名：" new_hostname
        done

        echo -e "\n正在备份配置文件..."
        cp -a /etc/hostname "/etc/hostname.bak-$(date +%Y%m%d%H%M)"
        cp -a /etc/hosts "/etc/hosts.bak-$(date +%Y%m%d%H%M)"
        echo "备份完成（路径：/etc/hostname.bak-* 和 /etc/hosts.bak-*）"

        echo -e "\n正在修改主机名..."
        hostnamectl set-hostname "$new_hostname"

        echo "正在更新/etc/hosts文件..."
        sed -i "s/127.0.1.1.*/127.0.1.1\t$new_hostname/" /etc/hosts
        sed -i "s/$current_hostname/$new_hostname/g" /etc/hosts

        echo -e "\n-------------------------"
        echo "主机名修改完成！"
        echo "新主机名：$(hostnamectl --static)"
        echo "-------------------------"
        echo "提示："
        echo "1. 部分程序可能需要重启才能识别新主机名（如SSH服务：sudo systemctl restart sshd）"
        echo "2. 若需立即在当前终端生效，可执行：exec bash"
        )
        return $?
    }

    menuname='首页/系统'
    echo "systemfun" >$installdir/config/lastfun
    options=("系统信息" sysinfo "进程查询" processquery "SSH配置管理" sshconfigfun "用户管理" usermanagefun "环境变量管理" envmanagefun "synctime同步时间" synchronization_time "crontab管理" crontabfun "swap管理" swapfun "rclocal配置" rclocalfun "系统检查" systemcheck "修改主机名" updateservername "清理系统日志" cleansyslogs)

    menu "${options[@]}"

}
