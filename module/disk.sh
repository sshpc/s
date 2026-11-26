diskfun() {
    beforeMenu(){
    _blue "> ---  当前目录: [ $(pwd) ] ---- < v:$selfversion"
    echo
    _yellow "当前菜单: $menuname "
    echo
    }

    # apt 上 growpart 的真实包名是 cloud-guest-utils
    ensure_growpart() {
        if ! command -v growpart >/dev/null 2>&1; then
            check_and_install cloud-guest-utils || check_and_install cloud-utils-growpart
        fi
    }

    # 列出 swap 分区设备（排除 swapfile），输出形如 /dev/sda3
    list_swap_parts() {
        {
            blkid -t TYPE=swap -o device 2>/dev/null
            awk 'NR>1 && $1 ~ /^\/dev\// {print $1}' /proc/swaps 2>/dev/null
        } | sort -u | grep '^/dev/' || true
    }

    # 分区操作通用辅助
    cmd_pkg() {
        case "$1" in
            mkfs.xfs|xfs_growfs|xfs_repair|xfs_info) echo xfsprogs;;
            mkfs.ext4|mkfs.ext3|mkfs.ext2|resize2fs|e2fsck|tune2fs|dumpe2fs) echo e2fsprogs;;
            sgdisk) echo gdisk;;
            parted) echo parted;;
            growpart|partprobe) echo cloud-guest-utils;;
            lsblk|findmnt|blkid|mount|umount|partx|sfdisk) echo util-linux;;
            *) echo "$1";;
        esac
    }

    # 检查命令是否存在
    need_cmd() {
        local c="$1" pkg
        if command -v "$c" >/dev/null 2>&1; then
            return 0
        fi
        pkg=$(cmd_pkg "$c")
        _yellow "缺少工具：$c，正在自动安装依赖包：$pkg ..."
        if [ "$c" = "growpart" ]; then
            ensure_growpart
        else
            check_and_install "$pkg"
        fi
        if command -v "$c" >/dev/null 2>&1; then
            _green "工具 $c 已就绪。"
            return 0
        fi
        _red "安装后仍找不到 $c，请手动检查依赖安装是否成功。"
        return 1
    }

    # 二次确认：必须输入 yes
    confirm_yes() {
        local prompt="${1:-确认继续？请输入 yes: }" ans
        read -r -p "$prompt" ans
        [[ "$ans" == "yes" ]]
    }

    # 取根磁盘（完整路径 /dev/sdX），沿持有者链解析，兼容 NVMe/LVM/RAID
    get_root_disk() {
        local src dev pk _
        src=$(findmnt -n -o SOURCE / 2>/dev/null)
        [ -z "$src" ] && return 1
        dev=$(readlink -f "$src" 2>/dev/null || echo "$src")
        for _ in 1 2 3; do
            pk=$(lsblk -no PKNAME "$dev" 2>/dev/null | head -1)
            [ -z "$pk" ] && break
            dev="/dev/$pk"
        done
        lsblk -no NAME -dp "$dev" 2>/dev/null | head -1
    }

    # 磁盘是否包含 LVM 结构
    disk_has_lvm() {
        lsblk -n -o TYPE,FSTYPE "$1" 2>/dev/null | grep -qi 'lvm' && return 0
        return 1
    }

    # 分区号：直接从设备名尾部数字提取，不依赖 PKNAME（部分系统 lsblk 不输出 PKNAME
    part_number() {
        local p
        p=$(basename "$1")
        [[ "$p" =~ ([0-9]+)$ ]] && printf '%s' "${BASH_REMATCH[1]}"
    }

    part_fstype() { blkid -s TYPE -o value "$1" 2>/dev/null; }
    part_mountpoint() { findmnt -n -o TARGET "$1" 2>/dev/null | head -1; }

    # 校验挂载路径：必须绝对路径，禁 ..，禁系统目录
    validate_mount_path() {
        local p="$1"
        [[ -z "$p" || "$p" != /* ]] && { _red "挂载点必须是绝对路径。"; return 1; }
        [[ "$p" == *..* ]] && { _red "挂载点不能包含 .."; return 1; }
        case "$p" in
            /|/bin|/sbin|/usr|/lib|/lib64|/etc|/proc|/sys|/dev|/boot|/boot/efi)
                _red "不能挂载到系统目录：$p"; return 1;;
        esac
        return 0
    }

    # 等待分区设备节点出现（udevadm settle + 最多 5 次轮询）
    wait_for_part() {
        local dev="$1" i
        for i in 1 2 3 4 5; do
            [ -b "$dev" ] && return 0
            udevadm settle >/dev/null 2>&1 || true
            sleep 1
        done
        [ -b "$dev" ]
    }

    # 大小字符串转字节：支持 10G/500M/50%/纯字节
    parse_size_bytes() {
        local s cur n u
        s=$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')
        cur="$2"
        if [[ "$s" =~ ^([0-9]+)([KMGT]?)$ ]]; then
            n="${BASH_REMATCH[1]}"; u="${BASH_REMATCH[2]}"
            case "$u" in
                K) echo $(( n * 1024 ));;
                M) echo $(( n * 1024 * 1024 ));;
                G) echo $(( n * 1024 * 1024 * 1024 ));;
                T) echo $(( n * 1024 * 1024 * 1024 * 1024 ));;
                *) echo "$n";;
            esac
        elif [[ "$s" =~ ^([0-9]+)%$ ]]; then
            echo $(( cur * ${BASH_REMATCH[1]} / 100 ))
        else
            return 1
        fi
    }

    # parted 机器格式取分区起止字节（输出 "start end"）
    part_bounds() {
        local disk="$1" num="$2" s e
        read -r s e <<< "$(parted -m -s "$disk" unit B print 2>/dev/null | awk -F: -v n="$num" '$1==n {print $2, $3}')"
        s=${s%B}; e=${e%B}
        printf '%s %s' "$s" "$e"
    }

    # 分区表类型 gpt / msdos
    disk_table_type() {
        parted -m -s "$1" print 2>/dev/null | sed -n '2p' | awk -F: '{print $6}'
    }

    # parted 防卡交互：给足确认回答后用 q 退出假终端交互循环
    safe_parted() {
        local out rc
        out=$(printf 'Yes\nFix\nq\n' | parted ---pretend-input-tty "$@" 2>&1); rc=$?
        [ "$rc" -eq 141 ] && rc=0
        [ -n "$out" ] && printf '%s\n' "$out"
        return "$rc"
    }

    # 磁盘详细信息
    diskinfo() {
        echo
        _blue "==== 磁盘详细信息 ===="

        root_dev=$(df / | awk 'NR==2 {print $1}')
        fs_type=$(df -Th / | awk 'NR==2 {print $2}')
        if lsblk -no TYPE "$root_dev" 2>/dev/null | grep -q "lvm"; then
            is_lvm="yes"
        else
            is_lvm="no"
        fi

        _green "根设备:        $root_dev"
        _green "文件系统类型:  $fs_type"
        _green "是否为 LVM:    $is_lvm"

        _blue "\n根分区使用率"
        read -r dev size used avail pcent _ <<< "$(df -h --output=source,size,used,avail,pcent / | tail -n1)"
        usage=$(echo "$pcent" | tr -d '%')
        bar_len=25
        filled=$(( usage * bar_len / 100 ))
        empty=$(( bar_len - filled ))
        if (( usage >= 90 )); then
            color="\e[1;31m"
        elif (( usage >= 75 )); then
            color="\e[1;33m"
        else
            color="\e[1;32m"
        fi
        if (( filled > 0 )); then filled_bar=$(printf '█%.0s' $(seq 1 "$filled")); else filled_bar=""; fi
        if (( empty > 0 )); then empty_bar=$(printf '░%.0s' $(seq 1 "$empty")); else empty_bar=""; fi
        echo -e "  ${color}${filled_bar}${empty_bar}\e[0m  ${pcent}  ($used/$size)"

        _blue "\n=== 所有挂载的文件系统（含其他磁盘）==="
        echo "  文件系统          总量    已用    可用  使用率  挂载点"
        while read -r fs size used avail pcent mount; do
            [[ "$mount" == "Mounted" ]] && continue
            [[ -z "$mount" ]] && continue
            [[ "$fs" == /dev/loop* ]] && continue
            usage=$(echo "$pcent" | tr -d '%')
            bar_len=20
            filled=$(( usage * bar_len / 100 ))
            empty=$(( bar_len - filled ))
            if (( usage >= 90 )); then
                mcolor=$'\e[1;31m'
            elif (( usage >= 75 )); then
                mcolor=$'\e[1;33m'
            else
                mcolor=$'\e[1;32m'
            fi
            reset=$'\e[0m'
            if (( filled > 0 )); then filled_bar=$(printf '█%.0s' $(seq 1 "$filled")); else filled_bar=""; fi
            if (( empty > 0 )); then empty_bar=$(printf '░%.0s' $(seq 1 "$empty")); else empty_bar=""; fi
            printf "  %-16s %-7s %-7s %-7s %-8s  %s%s%s%s  %s\n" \
                "$fs" "$size" "$used" "$avail" "$pcent" \
                "$mcolor" "${filled_bar}${empty_bar}" "$reset" "$pcent" "$mount"
        done < <(df -h --output=source,size,used,avail,pcent,target | tail -n +2)

        _blue "\n=== 所有物理磁盘 ==="
        echo "  磁盘设备           型号                      容量      使用率"
        while IFS='|' read -r name model size; do
            [[ -z "$name" ]] && continue
            if [[ -z "$size" ]]; then
                size=$(lsblk -b -n -o SIZE,TYPE "/dev/$name" 2>/dev/null | awk '$2=="part"{s+=$1} END {if (s>0) printf "%.1fG", s/1024/1024/1024}')
            fi
            total_size=0
            total_used=0
            while read -r mp; do
                [[ -z "$mp" ]] && continue
                read -r psize pused <<< "$(df -m "$mp" 2>/dev/null | awk 'NR==2 {print $2, $3}')"
                [[ -z "$psize" ]] && continue
                total_size=$((total_size + psize))
                total_used=$((total_used + pused))
            done < <(lsblk -n -o MOUNTPOINT "/dev/$name" 2>/dev/null | grep -v '^$' | sort -u)
            if (( total_size > 0 )); then
                usage=$(( total_used * 100 / total_size ))
            else
                usage=0
            fi
            bar_len=20
            filled=$(( usage * bar_len / 100 ))
            empty=$(( bar_len - filled ))
            if (( usage >= 90 )); then dcolor=$'\e[1;31m'
            elif (( usage >= 75 )); then dcolor=$'\e[1;33m'
            else dcolor=$'\e[1;32m'; fi
            if (( filled > 0 )); then filled_bar=$(printf '█%.0s' $(seq 1 "$filled")); else filled_bar=""; fi
            if (( empty > 0 )); then empty_bar=$(printf '░%.0s' $(seq 1 "$empty")); else empty_bar=""; fi
            printf "  /dev/%-14s %-24s %-10s " "$name" "${model:-未知}" "$size"
            echo -e "${dcolor}${filled_bar}${empty_bar}\e[0m ${usage}%"
        done < <(lsblk -d -n -o NAME,MODEL,SIZE --pairs 2>/dev/null | sed 's/^NAME="//; s/" MODEL="/|/; s/" SIZE="/|/; s/"$//' | grep -E '^(sd|nvme|hd|vd|mmcblk)')

    }
    # 磁盘占用扫描
    diskscan(){
        check_and_install gdu
        gdu /
    }


    disksmartinfo(){

        SMART_TEMP_WARN=${SMART_TEMP_WARN:-50}

        # 从 smartctl -A 提取属性值
        smart_attr() {
            local dev="$1" key="$2"
            smartctl -A "$dev" 2>/dev/null | awk -v k="$key" '
                BEGIN { ks = k; gsub(/_/, " ", k) }
                # SATA: 属性名在第 2 列，原始值在第 10 列
                $2 == ks {
                    if ($10 ~ /^[0-9]+$/) { print $10; exit }
                    for (i = 10; i <= NF; i++) if ($i ~ /^[0-9]+$/) { print $i; exit }
                }
                # NVMe: "Key Name: value" 形式（下划线与空格视为等价）
                {
                    line = $0
                    gsub(/_/, " ", line)
                    if (line ~ "^" k "[[:space:]]*:") {
                        for (i = 2; i <= NF; i++) if ($i ~ /^[0-9]+$/) { print $i; exit }
                    }
                }
            '
        }

        if [ "$(id -u)" -ne 0 ]; then
            echo "错误：需要root权限，请用sudo运行"
            return 1
        fi

        if ! command -v smartctl &> /dev/null; then
            check_and_install smartmontools
        fi

        disks=$(lsblk -d -n -o NAME | grep -E '^sd|^nvme|^hd|^vd')
        if [ -z "$disks" ]; then
            echo "未检测到磁盘设备"
            return 0
        fi

        total=0
        healthy=0
        warning=0
        error=0
        unsupported=0

        echo "===== 开始磁盘SMART检查 ====="
        echo "检测到磁盘数：$(echo "$disks" | wc -l)"

        for disk in $disks; do
            total=$((total + 1))
            device="/dev/$disk"
            echo -e "\n----- 检查磁盘：$device -----"

            smart_info=$(smartctl -i "$device" 2>/dev/null)
            if echo "$smart_info" | grep -q "SMART support is: Unavailable"; then
                echo "不支持SMART功能"
                unsupported=$((unsupported + 1))
                continue
            fi

            if echo "$smart_info" | grep -q "SMART support is: Disabled"; then
                echo "SMART未启用，尝试开启..."
                if smartctl -s on "$device" > /dev/null 2>&1; then
                    echo "SMART已启用"
                else
                    echo "开启SMART失败"
                    error=$((error + 1))
                    continue
                fi
            fi

            health=$(smartctl -H "$device" 2>/dev/null | grep "test result")
            if echo "$health" | grep -q "PASSED"; then
                echo "健康状态：正常（PASSED）"
                current_status="健康"
            else
                echo "健康状态：异常（FAILED）"
                current_status="异常"
                error=$((error + 1))
            fi

            temp=$(smart_attr "$device" Temperature_Celsius)
            [ -z "$temp" ] && temp=$(smart_attr "$device" Temperature)
            realloc=$(smart_attr "$device" Reallocated_Sector_Ct)
            [ -z "$realloc" ] && realloc=$(smart_attr "$device" Reallocated_NAND_Blk_Ct)
            power_on=$(smart_attr "$device" Power_On_Hours)
            [ -z "$power_on" ] && power_on=$(smart_attr "$device" Power-On_Hours)

            echo "温度：${temp:-未知}°C $( [ -n "$temp" ] && [ "$temp" -ge "$SMART_TEMP_WARN" ] && echo "(警告：偏高)" )"
            echo "重新分配扇区数：${realloc:-0} $( [ -n "$realloc" ] && [ "$realloc" -gt 0 ] && echo "(警告：存在坏道)" )"
            echo "累计通电时间：${power_on:-0}小时"

            if [ "$current_status" = "健康" ]; then
                if ( [ -n "$temp" ] && [ "$temp" -ge "$SMART_TEMP_WARN" ] ) || ( [ -n "$realloc" ] && [ "$realloc" -gt 0 ] ); then
                    warning=$((warning + 1))
                else
                    healthy=$((healthy + 1))
                fi
            fi
        done

        echo -e "\n===== 检查完成 ====="
        echo "总磁盘数：$total"
        echo "健康：$healthy 个"
        echo "警告（温度高/坏道）：$warning 个"
        echo "错误（健康异常/开启失败）：$error 个"
        echo "不支持SMART：$unsupported 个"

        if [ $error -gt 0 ]; then
            echo "警告：存在异常磁盘，建议备份数据并检查硬件"
        elif [ $warning -gt 0 ]; then
            echo "提示：存在警告磁盘，建议关注状态变化"
        else
            echo "所有磁盘状态正常"
        fi
    }

    diskspeedtest() {
        IO_TEST_BLOCKS=${IO_TEST_BLOCKS:-2048}
        IO_TEST_RUNS=${IO_TEST_RUNS:-3}

        local target_dir="."
        _blue "=== 选择测速磁盘 ==="
        local -a mp_list=()
        while read -r src mp; do
            [[ -z "$mp" || "$src" == "Filesystem" ]] && continue
            [[ "$src" == /dev/loop* || "$src" == tmpfs* ]] && continue
            [[ "$mp" == / || "$mp" == /boot || "$mp" == /boot/efi ]] && continue
            mp_list+=("$src|$mp")
        done < <(df -h --output=source,target 2>/dev/null | tail -n +2)
        mp_list+=("root|/")

        local i=1 item src mp
        for item in "${mp_list[@]}"; do
            src=${item%%|*}; mp=${item#*|}
            printf "  %d) %-24s 挂载于 %s\n" "$i" "$src" "$mp"
            ((i++))
        done
        read -p "请选择磁盘编号（直接回车测当前目录）: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#mp_list[@]} )); then
            item=${mp_list[$((choice-1))]}
            mp=${item#*|}
            target_dir="$mp"
        fi
        _blue "测速目录: $target_dir"

        # io测试：mktemp + trap 保证 dd 失败或中断也不留 benchtest_* 残留
        io_test() {
            local tmpfile result
            tmpfile=$(mktemp "$target_dir/benchtest.XXXXXX") || { echo "0 MB/s"; return 1; }
            trap 'rm -f "$tmpfile"' RETURN
            result=$(dd if=/dev/zero of="$tmpfile" bs=512k count="$1" conv=fdatasync 2>&1 | awk -F, '{io=$NF} END { print io}' | sed 's/^[ \t]*//;s/[ \t]*$//')
            rm -f "$tmpfile"
            trap - RETURN
            echo "${result:-0 MB/s}"
        }
        _blue "正在进行磁盘测速..."
        echo
        freespace=$(df -m "$target_dir" | awk 'NR==2 {print $4}')
        if [ -z "${freespace}" ]; then
            freespace=$(df -m "$target_dir" | awk 'NR==3 {print $3}')
        fi
        if [ ${freespace} -gt 1024 ]; then
            local n io ioraw ioall=0 ioavg
            for ((n = 1; n <= IO_TEST_RUNS; n++)); do
                io=$(io_test "$IO_TEST_BLOCKS")
                echo " I/O Speed(run #$n) : $(_yellow "$io")"
                ioraw=$(echo "$io" | awk 'NR==1 {print $1}')
                [ "$(echo "$io" | awk 'NR==1 {print $2}')" == "GB/s" ] && ioraw=$(awk -v v="$ioraw" 'BEGIN{print v * 1024}')
                ioall=$(awk -v a="$ioall" -v b="$ioraw" 'BEGIN{print a + b}')
            done
            ioavg=$(awk -v n="$IO_TEST_RUNS" -v all="$ioall" 'BEGIN{printf "%.1f", all / n}')
            echo " I/O Speed(average) : $(_yellow "$ioavg MB/s")"
        else
            echo " $(_red "Not enough space for I/O Speed test!")"
        fi
    }

    # 扩容根分区
    expandroot(){
        (
        set -euo pipefail
        
        resolve_dev() { readlink -f "$1"; }
        
        echo "=== 检测根分区与环境 ==="
        ROOT_SRC=$(findmnt -n -o SOURCE /)
        if [ -z "$ROOT_SRC" ]; then
            echo "无法确定根分区设备，退出。"
            exit 1
        fi
        ROOT_DEV=$(resolve_dev "$ROOT_SRC")
        FSTYPE=$(findmnt -n -o FSTYPE / || echo "")
        echo "根设备: $ROOT_SRC -> $ROOT_DEV"
        echo "文件系统类型: $FSTYPE"

        local _swap_parts
        _swap_parts=$(list_swap_parts)
        if [ -n "$_swap_parts" ]; then
            echo
            _yellow "提示：检测到 swap 分区：$(echo "$_swap_parts" | tr '\n' ' ')"
            _yellow "      swap 分区位于根磁盘尾部时，即使 growpart 成功，根分区也可能无法扩张。"
            _yellow "      可先用菜单的 “swap分区转swapfile” 功能删除 swap 分区并以 swapfile 替代，再回来扩容。"
        fi
        
        cmds=()
        
        if echo "$ROOT_DEV" | grep -qE '^/dev/mapper/|^/dev/VolGroup|^/dev/.*/.*$'; then
            is_lvm=1
        else
            is_lvm=0
        fi
        echo "是否为 LVM: $([ "$is_lvm" -eq 1 ] && echo yes || echo no)"
        
        if [ "$is_lvm" -eq 1 ]; then
            echo
            echo "== LVM 根分区流程: 解析 VG/LV/PV =="
            if ! command -v lvs >/dev/null 2>&1; then
                echo "[*] 需要安装 lvm2"
                check_and_install lvm2
            fi
            
            VG_NAME=$(lvs --noheadings -o vg_name --units '' --nosuffix "$ROOT_DEV" 2>/dev/null | awk '{print $1}' || true)
            LV_NAME=$(lvs --noheadings -o lv_name --units '' --nosuffix "$ROOT_DEV" 2>/dev/null | awk '{print $1}' || true)
            if [ -z "$VG_NAME" ] || [ -z "$LV_NAME" ]; then
                VG_NAME=$(lvdisplay "$ROOT_DEV" 2>/dev/null | awk -F': ' '/VG Name/{print $2; exit}' || true)
                LV_NAME=$(lvdisplay "$ROOT_DEV" 2>/dev/null | awk -F': ' '/LV Name/{print $2; exit}' || true)
            fi
            if [ -z "$VG_NAME" ] || [ -z "$LV_NAME" ]; then
                echo "无法解析 VG/LV 名称：VG='$VG_NAME' LV='$LV_NAME'，请手动检查。"
                exit 1
            fi
            LV_PATH="$ROOT_DEV"
            echo "VG: $VG_NAME  LV: $LV_NAME  LV_PATH: $LV_PATH"
            
            PVS=$(pvs --noheadings -o pv_name,vg_name --units '' --nosuffix 2>/dev/null | awk -v vg="$VG_NAME" '$2==vg{print $1}' | tr -d ' ' || true)
            if [ -z "$PVS" ]; then
                echo "未找到 VG 的 PV 列表，请检查：pvs 输出为空。"
                exit 1
            fi
            PV0=$(echo "$PVS" | head -n1)
            PV0_DEV=$(resolve_dev "$PV0")
            echo "选择 PV: $PV0 -> $PV0_DEV"
            
            PKNAME=$(lsblk -no PKNAME "$PV0_DEV" || true)
            if [ -z "$PKNAME" ]; then
                echo "无法解析 PV 的父磁盘（可能是整盘 PV 或特殊情况），PV: $PV0_DEV"
                echo "PV 不是分区（或无法解析）。请手动检查并处理。"
                exit 1
            fi
            DISK="/dev/$PKNAME"
            PARTNUM=$(basename "$PV0_DEV" | sed "s/^$PKNAME//")
            if [ -z "$PARTNUM" ]; then
                PARTNUM=$(echo "$PV0_DEV" | grep -oE '[0-9]+$' || true)
            fi
            if [ -z "$PARTNUM" ]; then
                echo "无法解析 PV 的分区号，手动检查：PV0_DEV=$PV0_DEV"
                exit 1
            fi
            
            echo "PV 所在磁盘: $DISK 分区号: $PARTNUM"
            
            ensure_growpart
            check_and_install parted lvm2
            
            if [ "$FSTYPE" = "xfs" ]; then
                check_and_install xfsprogs
            else
                check_and_install e2fsprogs
            fi
            
            cmds+=("growpart $DISK $PARTNUM")
            cmds+=("partprobe $DISK || partx -u $DISK")
            cmds+=("pvresize $PV0_DEV")
            cmds+=("lvextend -l +100%FREE $LV_PATH")
            if [ "$FSTYPE" = "xfs" ]; then
                cmds+=("xfs_growfs /")
            else
                cmds+=("resize2fs $LV_PATH")
            fi
            
        else
            echo
            echo "== 非 LVM 根分区流程 =="
            PKNAME=$(lsblk -no PKNAME "$ROOT_DEV" || true)
            if [ -z "$PKNAME" ]; then
                echo "无法解析根分区的父磁盘，退出。"
                exit 1
            fi
            DISK="/dev/$PKNAME"
            PARTNUM=$(basename "$ROOT_DEV" | sed "s/^$PKNAME//")
            if [ -z "$PARTNUM" ]; then
                PARTNUM=$(echo "$ROOT_DEV" | grep -oE '[0-9]+$' || true)
            fi
            if [ -z "$PARTNUM" ]; then
                echo "无法确定分区号，请手动检查：ROOT_DEV=$ROOT_DEV"
                exit 1
            fi
            echo "根分区所在磁盘: $DISK 分区号: $PARTNUM"
            
            ensure_growpart
            check_and_install parted
            
            if [ "$FSTYPE" = "xfs" ]; then
                check_and_install xfsprogs
            else
                check_and_install e2fsprogs
            fi
            
            cmds+=("growpart $DISK $PARTNUM")
            cmds+=("partprobe $DISK || partx -u $DISK")
            if [ "$FSTYPE" = "xfs" ]; then
                cmds+=("xfs_growfs /")
            else
                cmds+=("resize2fs $ROOT_DEV")
            fi
        fi
        
        echo
        echo "!!! 警告: 以下命令将修改分区表/卷组/文件系统，操作有数据丢失风险，请确保已备份或已创建快照。"
        echo "=== 将要执行的命令（按顺序） ==="
        idx=1
        for c in "${cmds[@]}"; do
            printf "%2d) %s\n" "$idx" "$c"
            idx=$((idx+1))
        done
        echo "===================================="
        read -r -p "确认按以上顺序执行这些命令？（输入 y 执行，其他任意键取消）: " confirm
        if [ "$confirm" != "y" ]; then
            echo "已取消，未做任何更改。"
            exit 0
        fi
        
        echo
        echo "开始按顺序执行命令..."
        i=1
        for c in "${cmds[@]}"; do
            echo "----- 执行第 $i 条命令: $c -----"
            if cmdout=$(bash -c "$c" 2>&1); then
                [ -n "$cmdout" ] && echo "$cmdout"
                echo "第 $i 条命令成功。"
            else
                rc=$?
                [ -n "$cmdout" ] && echo "$cmdout"
                if [[ "$c" == growpart* ]] && echo "$cmdout" | grep -q 'NOCHANGE'; then
                    echo "第 $i 条命令：分区无法再扩容（NOCHANGE），继续执行后续命令。"
                    _sp=$(list_swap_parts)
                    [ -n "$_sp" ] && _yellow "提示：检测到 swap 分区 $_sp，可能挡在根分区后面；可用“swap分区转swapfile”处理。"
                    _yellow "提示：若磁盘本身无未分配空间，growpart 报 NOCHANGE 属正常情况。"
                else
                    echo "第 $i 条命令失败（退出码 $rc），停止执行。请手动检查或恢复备份。"
                    exit 1
                fi
            fi
            i=$((i+1))
        done
        
        echo
        df -h /
        )
        return $?
    }

    formatotherdisks(){
        echo "正在扫描未挂载磁盘..."

        ROOT_SRC=$(findmnt -n -o SOURCE / 2>/dev/null)
        ROOT_DISK=""
        if [ -n "$ROOT_SRC" ]; then
            ROOT_DEV=$(readlink -f "$ROOT_SRC" 2>/dev/null || echo "$ROOT_SRC")
            for _ in 1 2 3; do
                _pk=$(lsblk -no PKNAME "$ROOT_DEV" 2>/dev/null | head -1)
                [ -z "$_pk" ] && break
                ROOT_DEV="/dev/$_pk"
            done
            ROOT_DISK=$(lsblk -no NAME -dp "$ROOT_DEV" 2>/dev/null | head -1)
        fi
        if [ -z "$ROOT_DISK" ]; then
            _red "无法确定根磁盘，为安全起见禁止格式化。"
            return 1
        fi
        echo "根磁盘：$ROOT_DISK（将被强制排除）"

        ALL_DISKS=($(lsblk -dpno NAME,TYPE | awk '$2=="disk"{print $1}'))
        UNUSED_DISKS=()
        for d in "${ALL_DISKS[@]}"; do
            [[ "$d" == "$ROOT_DISK" ]] && continue
            if lsblk -ln -o MOUNTPOINT "$d" 2>/dev/null | grep -q .; then
                continue
            fi
            UNUSED_DISKS+=("$d")
        done

        if [[ ${#UNUSED_DISKS[@]} -eq 0 ]]; then
        echo "未发现未使用的磁盘。"
        return 0
        fi

        echo "可用磁盘列表："
        i=1
        for d in "${UNUSED_DISKS[@]}"; do
        size=$(lsblk -dnbo SIZE "$d" | awk '{printf "%.1f GiB", $1/1024/1024/1024}')
        echo "$i) $d: $size"
        ((i++))
        done

        read -p "请输入要格式化的磁盘编号: " choice
        if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#UNUSED_DISKS[@]} )); then
        echo "无效选择。"
        return 1
        fi

        DISK=${UNUSED_DISKS[$((choice-1))]}
        _blue "已选择磁盘: $DISK"

        _red "警告：即将完全清除磁盘 $DISK 上的所有数据，此操作不可撤销！"
        read -p "请再次输入 yes 确认格式化: " confirm
        if [[ "$confirm" != "yes" ]]; then
            echo "已取消。"
            return 0
        fi

        check_and_install parted
        ensure_growpart
        check_and_install e2fsprogs

        PART="${DISK}1"
        [[ "$DISK" =~ nvme[0-9]+n[0-9]+$ ]] && PART="${DISK}p1"
        if ! ls ${PART} &>/dev/null; then
        _yellow "磁盘 $DISK 没有分区，正在创建新分区..."
        parted -s "$DISK" mklabel gpt
        parted -s "$DISK" mkpart primary ext4 0% 100%
        partprobe "$DISK"
        sleep 2
        fi

        if command -v growpart &>/dev/null; then
        echo "扩展分区..."
        growpart "$DISK" 1 || true
        else
        echo "未找到 growpart，跳过分区扩展。"
        fi

        _yellow "正在格式化分区 $PART ..."
        mkfs.ext4 -F "$PART"

        DISK_NAME=$(basename "$DISK")

        read -p "请输入挂载点路径（默认 /mnt/$DISK_NAME）: " MOUNT_POINT
        MOUNT_POINT=${MOUNT_POINT:-/mnt/$DISK_NAME}

        mkdir -p "$MOUNT_POINT"
        mount "$PART" "$MOUNT_POINT"

        echo "挂载成功：$PART -> $MOUNT_POINT"

        UUID=$(blkid -s UUID -o value "$PART")
        if ! grep -q "$UUID" /etc/fstab; then
        cp -a /etc/fstab /etc/fstab.bak.$(date +%s)
        echo "UUID=$UUID $MOUNT_POINT ext4 defaults 0 2" >> /etc/fstab
        _blue "已添加到 /etc/fstab（原文件已备份），重启后将自动挂载。"
        fi

        _green "操作完成！当前挂载："
        df -h | grep "$MOUNT_POINT"

        
    }

    # 将 swap 分区替换为 swapfile，以便根分区能完整扩张
    swap_to_swapfile(){
        echo "=== swap 分区转 swapfile ==="

        local swap_parts
        swap_parts=$(list_swap_parts)
        if [ -z "$swap_parts" ]; then
            _green "未检测到 swap 分区（可能已是 swapfile 或没有 swap），无需转换。"
            return 0
        fi
        echo "检测到 swap 分区："
        echo "$swap_parts" | sed 's/^/  /'

        local swapsize_kb swapsize_m swapfile_size
        swapsize_kb=$(awk '/SwapTotal:/{print $2}' /proc/meminfo 2>/dev/null)
        swapsize_m=$(( swapsize_kb / 1024 ))
        [ "$swapsize_m" -lt 1 ] && swapsize_m=1024
        swapfile_size=${SWAPFILE_SIZE_M:-$swapsize_m}
        echo "原 swap 容量约 ${swapsize_m}M，新 swapfile 大小: ${swapfile_size}M"

        _red "警告：此操作将删除 swap 分区并修改分区表与 /etc/fstab，有数据丢失风险，请先备份。"
        read -p "确认继续？（输入 yes）: " confirm
        [ "$confirm" != "yes" ] && { echo "已取消。"; return 0; }

        local root_src root_dev swap_dev swap_disk root_disk
        root_src=$(findmnt -n -o SOURCE / 2>/dev/null)
        root_dev=$(readlink -f "$root_src" 2>/dev/null || echo "$root_src")
        swap_dev=$(echo "$swap_parts" | head -n1)

        root_disk=$(lsblk -no PKNAME "$root_dev" 2>/dev/null | head -n1)
        swap_disk=$(lsblk -no PKNAME "$swap_dev" 2>/dev/null | head -n1)
        [ -z "$root_disk" ] && root_disk=$(basename "$root_dev")
        [ -z "$swap_disk" ] && swap_disk=$(basename "$swap_dev")

        if [ "$root_disk" != "$swap_disk" ]; then
            _yellow "注意：swap 分区不在根磁盘上（$swap_dev 在 /dev/$swap_disk，根盘 /dev/$root_disk），本功能主要针对同盘情况。"
        fi
        echo "根盘: /dev/$root_disk  swap 分区: $swap_dev (磁盘 /dev/$swap_disk)"

        swapoff "$swap_dev" 2>/dev/null || true
        cp -a /etc/fstab "/etc/fstab.bak.$(date +%s)"

        local swapfile="/swapfile"
        echo "正在创建 swapfile: $swapfile ($swapfile_size M) ..."
        if ! fallocate -l "${swapfile_size}M" "$swapfile" 2>/dev/null; then
            dd if=/dev/zero of="$swapfile" bs=1M count="$swapfile_size" status=none
        fi
        chmod 600 "$swapfile"
        mkswap "$swapfile" >/dev/null
        swapon "$swapfile"

        if grep -q "$swap_dev" /etc/fstab; then
            sed -i "\|^[[:space:]]*$swap_dev|d" /etc/fstab
        fi
        if ! grep -q "^[[:space:]]*$swapfile" /etc/fstab; then
            echo "$swapfile none swap sw 0 0" >> /etc/fstab
        fi
        _green "swapfile 已启用并写入 /etc/fstab（原 fstab 已备份）。"

        local root_partnum swap_partnum
        root_partnum=$(basename "$root_dev" | grep -oE '[0-9]+$')
        swap_partnum=$(basename "$swap_dev" | grep -oE '[0-9]+$')
        if [ "$root_disk" = "$swap_disk" ] && [ -n "$root_partnum" ] && [ -n "$swap_partnum" ] \
            && [ "$swap_partnum" -gt "$root_partnum" ] 2>/dev/null; then
            echo "正在删除 swap 分区 $swap_dev ..."
            if command -v parted >/dev/null 2>&1 || check_and_install parted; then
                parted -s "/dev/$swap_disk" rm "$swap_partnum"
                partprobe "/dev/$swap_disk" 2>/dev/null || true
                echo "swap 分区已删除，正在扩展根分区..."
                ensure_growpart
                growpart "/dev/$root_disk" "$root_partnum" || true
                partprobe "/dev/$root_disk" 2>/dev/null || true
                case "$(findmnt -n -o FSTYPE / 2>/dev/null)" in
                    xfs) xfs_growfs / 2>/dev/null || true ;;
                    *) resize2fs "$root_dev" 2>/dev/null || true ;;
                esac
                echo "分区表变更完成，建议重启后再确认 swapfile 生效。"
            else
                _yellow "parted 不可用，跳过删除分区，仅保留 swapfile。"
            fi
        else
            _yellow "swap 分区不在根盘尾部或分区号异常，未删除分区；swapfile 已可用，请手动处理旧 swap 分区。"
        fi

        _green "操作完成。当前 swap 状态："
        swapon --show 2>/dev/null || cat /proc/swaps
    }

    # 选择物理磁盘 → 磁盘详情 → 分区详情
    disk_manager() {
        local d sz model name lvmflag mp c rootmark diskmaj
        local -a pdisks=()
        while true; do
            echo
            _blue "===== 选择物理磁盘（仅真实物理设备，loop 已过滤）====="
            pdisks=()
            while IFS='|' read -r d sz model maj; do
                [ -z "$d" ] && continue
                diskmaj=${maj%%:*}
                case "$diskmaj" in 8|9|179|180|189|202|208|253|254|259) ;; *) continue;; esac
                name=$(basename "$d")
                lvmflag=""
                disk_has_lvm "$d" && lvmflag=" [LVM-暂不支持]"
                rootmark=""
                [ "$d" = "$(get_root_disk 2>/dev/null)" ] && rootmark=" [根盘]"
                mp=$(lsblk -n -o MOUNTPOINT "$d" 2>/dev/null | grep -v '^$' | sort -u | paste -sd, -)
                pdisks+=("$d")
                printf "  %2d) %-16s %-10s %-24s%s%s\n" "${#pdisks[@]}" "$name" "$sz" "${model:-未知}" "$rootmark" "$lvmflag"
                [ -n "$mp" ] && printf "      已挂载: %s\n" "$mp"
            done < <(lsblk -dpn -o NAME,SIZE,MODEL,MAJ:MIN --pairs 2>/dev/null | sed 's/^NAME="//; s/" SIZE="/|/; s/" MODEL="/|/; s/" MAJ:MIN="/|/; s/"$//')
            if [ ${#pdisks[@]} -eq 0 ]; then
                _yellow "没有可操作的物理磁盘。"
                return 0
            fi
            echo
            echo "  0/b) 返回上级菜单   n) 重新扫描"
            read -ep "请选择磁盘编号: " c
            case "$c" in
                0|b|B) return 0;;
                n|N) continue;;
                ""|*[!0-9]*) _red "无效输入。"; continue;;
            esac
            if (( c < 1 || c > ${#pdisks[@]} )); then
                _red "超出范围。"; continue
            fi
            d=${pdisks[$((c-1))]}
            if disk_has_lvm "$d"; then
                _yellow "该磁盘包含 LVM 结构，暂不支持分区操作。"
                continue
            fi
            disk_detail_menu "$d"
        done
    }

    disk_detail_menu() {
        local disk="$1" c c2 pn pt i fst sz mp
        local -a parts=()
        while true; do
            echo
            _blue "===== 磁盘详情：$disk ====="
            echo "  编号 分区           文件系统       大小       挂载点"
            parts=()
            while read -r pn pt; do
                [ "$pt" = "part" ] && parts+=("$pn")
            done < <(lsblk -rpno NAME,TYPE "$disk" 2>/dev/null)
            i=1
            for pn in "${parts[@]}"; do
                fst=$(part_fstype "$pn"); [ -z "$fst" ] && fst="未格式化"
                sz=$(lsblk -n -o SIZE "$pn" 2>/dev/null | head -1)
                mp=$(part_mountpoint "$pn"); [ -z "$mp" ] && mp="-"
                printf "  %2d)  %-14s %-12s %-10s %s\n" "$i" "$(basename "$pn")" "$fst" "$sz" "$mp"
                ((i++))
            done
            [ ${#parts[@]} -eq 0 ] && _yellow "  （没有分区）"
            echo
            echo "  直接输入分区编号进入分区操作"
            echo "  n) 新建分区   g) 转换分区表(MBR/GPT)   f) 格式化整盘并挂载   b) 返回选盘"
            read -ep "请选择: " c
            case "$c" in
                b|B|0) return 0;;
                n|N) create_part "$disk"; continue;;
                g|G) convert_partition_table "$disk"; continue;;
                f|F) wipe_and_format_disk "$disk"; continue;;
                ""|*[!0-9]*) _red "无效输入。"; continue;;
            esac
            if (( c >= 1 && c <= ${#parts[@]} )); then
                part_detail_menu "$disk" "${parts[$((c-1))]}"
            else
                _red "超出范围。"
            fi
        done
    }

    part_detail_menu() {
        local disk="$1" part="$2" c mp fst sz
        while true; do
            echo
            _blue "===== 分区操作：$(basename "$part") ($disk) ====="
            mp=$(part_mountpoint "$part"); fst=$(part_fstype "$part"); sz=$(lsblk -n -o SIZE "$part" 2>/dev/null | head -1)
            echo "  文件系统: ${fst:-未格式化}   大小: $sz   挂载点: ${mp:-未挂载}"
            echo "  1) 挂载分区"
            echo "  2) 卸载分区"
            echo "  3) 扩容分区（把紧随其后的空闲空间给本分区）"
            echo "  4) 压缩分区（缩小，腾出空间）"
            echo "  5) 删除分区"
            echo "  6) 格式化 / 重建文件系统（清空数据）"
            echo "  7) 转换文件系统（ext2 → ext3/ext4，保留数据）"
            echo "  b) 返回磁盘详情"
            read -ep "请选择: " c
            case "$c" in
                1) mount_part "$part";;
                2) unmount_part "$part";;
                3) expand_part "$disk" "$part";;
                4) shrink_part "$disk" "$part";;
                5) delete_part "$disk" "$part"; return 0;;
                6) format_part "$part";;
                7) convert_fs "$part";;
                b|B|0) return 0;;
                *) _red "无效输入。";;
            esac
        done
    }

    mount_part() {
        local part="$1" mp uuid
        need_cmd mount || return 1
        mp=$(part_mountpoint "$part")
        if [ -n "$mp" ]; then _yellow "已挂载于 $mp"; return 0; fi
        read -ep "请输入挂载点（如 /mnt/data）: " mp
        validate_mount_path "$mp" || return 1
        mkdir -p "$mp" || { _red "创建挂载目录失败。"; return 1; }
        if ! mount "$part" "$mp"; then _red "挂载失败。"; return 1; fi
        _green "已挂载：$part -> $mp"
        if confirm_yes "是否写入 /etc/fstab 开机自动挂载？（输入 yes 写入）: "; then
            uuid=$(blkid -s UUID -o value "$part")
            if [ -n "$uuid" ] && ! grep -q "$uuid" /etc/fstab; then
                cp -a /etc/fstab /etc/fstab.bak.$(date +%s)
                echo "UUID=$uuid $mp $(part_fstype "$part") defaults 0 2" >> /etc/fstab
                _green "已写入 fstab（原文件已备份）。"
            else
                _yellow "未写入（UUID 为空或条目已存在）。"
            fi
        fi
    }

    unmount_part() {
        local part="$1" mp uuid
        mp=$(part_mountpoint "$part")
        if [ -z "$mp" ]; then _yellow "该分区未挂载。"; return 0; fi
        need_cmd umount || return 1
        if ! umount "$part"; then _red "卸载失败（可能被占用）。"; return 1; fi
        _green "已卸载：$part"
        if confirm_yes "是否同时从 /etc/fstab 移除该分区条目？（输入 yes 移除）: "; then
            uuid=$(blkid -s UUID -o value "$part")
            if [ -n "$uuid" ] && grep -q "$uuid" /etc/fstab; then
                cp -a /etc/fstab /etc/fstab.bak.$(date +%s)
                sed -i "\|UUID=$uuid|d" /etc/fstab
                _green "已从 fstab 移除（原文件已备份）。"
            else
                _yellow "fstab 中没有该分区条目。"
            fi
        fi
    }

    expand_part() {
        local disk="$1" part="$2" num mp fst out
        num=$(part_number "$part")
        if [ -z "$num" ]; then _red "无法解析分区号。"; return 1; fi
        need_cmd growpart || return 1
        need_cmd parted || return 1
        mp=$(part_mountpoint "$part")
        fst=$(part_fstype "$part")
        _yellow "将把 $disk 上分区 $num 扩展到紧随其后的空闲空间。"
        confirm_yes "确认继续？（输入 yes）: " || { echo "已取消。"; return 0; }
        echo "执行 growpart..."
        if out=$(growpart "$disk" "$num" 2>&1); then
            [ -n "$out" ] && echo "$out"
        else
            echo "$out"
            if echo "$out" | grep -q 'NOCHANGE'; then
                _yellow "分区已到磁盘末尾或后方无空闲空间（NOCHANGE），继续尝试扩展文件系统。"
            else
                _red "growpart 失败，停止。"; return 1
            fi
        fi
        partprobe "$disk" 2>/dev/null || partx -u "$disk" 2>/dev/null || true
        case "$fst" in
            ext2|ext3|ext4)
                need_cmd resize2fs || return 1
                resize2fs "$part" || { _red "resize2fs 失败。"; return 1; };;
            xfs)
                need_cmd xfs_growfs || return 1
                if [ -z "$mp" ]; then _yellow "xfs 扩容需要已挂载，请先挂载该分区。"; return 1; fi
                xfs_growfs "$mp" || { _red "xfs_growfs 失败。"; return 1; };;
            *)
                _yellow "未知文件系统 ${fst:-空}，仅调整了分区表，未调整文件系统。";;
        esac
        _green "操作完成。当前大小：$(lsblk -n -o SIZE "$part" 2>/dev/null | head -1)"
    }

    shrink_part() {
        local disk="$1" part="$2" num mp fst start end cur target target_b aligned end_new
        local -a parts=()
        mp=$(part_mountpoint "$part")
        [ -n "$mp" ] && { _red "请先卸载该分区再压缩（当前挂载于 $mp）。"; return 1; }
        fst=$(part_fstype "$part")
        case "$fst" in
            ext2|ext3|ext4) ;;
            *) _red "压缩仅支持 ext2/3/4，当前为 ${fst:-未知}（xfs 不支持缩容）。"; return 1;;
        esac
        need_cmd e2fsck || return 1
        need_cmd resize2fs || return 1
        need_cmd parted || return 1
        num=$(part_number "$part")
        read -r start end <<< "$(part_bounds "$disk" "$num")"
        [ -z "$start" ] && { _red "无法读取分区边界。"; return 1; }
        cur=$(( end - start ))
        echo "当前分区大小：$(( cur / 1024 / 1024 )) MiB"
        read -ep "请输入目标大小（如 20G / 500M / 50%）: " target
        target_b=$(parse_size_bytes "$target" "$cur") || { _red "大小格式无效。"; return 1; }
        (( target_b < 16777216 )) && target_b=16777216
        aligned=$(( target_b / 65536 * 65536 ))
        (( aligned >= cur )) && { _red "目标大小必须小于当前分区大小。"; return 1; }
        _red "警告：压缩分区会修改分区表，操作前请备份重要数据。"
        confirm_yes "确认继续？（输入 yes）: " || { echo "已取消。"; return 0; }
        echo "检查文件系统..."
        e2fsck -f -y "$part" || { _red "e2fsck 失败，停止。"; return 1; }
        echo "缩小文件系统..."
        resize2fs "$part" "$(( aligned / 1024 ))K" || { _red "resize2fs 失败，停止。"; return 1; }
        echo "缩小分区..."
        end_new=$(( start + aligned + 1048576 ))
        safe_parted "$disk" unit B resizepart "$num" "${end_new}B" || { _red "resizepart 失败，请手动检查。"; return 1; }
        partprobe "$disk" 2>/dev/null || true
        _green "压缩完成。当前大小：$(lsblk -n -o SIZE "$part" 2>/dev/null | head -1)"
        while read -r pn pt; do [ "$pt" = "part" ] && parts+=("$pn"); done < <(lsblk -rpno NAME,TYPE "$disk" 2>/dev/null)
        _yellow "腾出的空闲空间位于 $(basename "$part") 之后。"
        _yellow "说明：parted 无法移动分区起始位置，空闲空间不能直接并入后方分区；"
        _yellow "      如需利用，请在磁盘详情中用“新建分区”在空隙中创建新分区。"
        if confirm_yes "现在就去该磁盘创建分区使用这些空闲空间？（输入 yes 继续）: "; then
            create_part "$disk"
        fi
    }

    delete_part() {
        local disk="$1" part="$2" mp num uuid
        mp=$(part_mountpoint "$part")
        [ -n "$mp" ] && { _red "请先卸载该分区（当前挂载于 $mp）。"; return 1; }
        need_cmd parted || return 1
        num=$(part_number "$part")
        uuid=$(blkid -s UUID -o value "$part" 2>/dev/null)
        _red "警告：删除分区 $(basename "$part") 将丢失其上所有数据，不可撤销！"
        confirm_yes "确认删除？（输入 yes）: " || { echo "已取消。"; return 0; }
        if ! safe_parted "$disk" rm "$num"; then _red "删除失败。"; return 1; fi
        partprobe "$disk" 2>/dev/null || true
        _green "分区已删除。"
        if [ -n "$uuid" ] && confirm_yes "是否清理 /etc/fstab 中该分区条目？（输入 yes 清理）: "; then
            if grep -q "$uuid" /etc/fstab; then
                cp -a /etc/fstab /etc/fstab.bak.$(date +%s)
                sed -i "\|UUID=$uuid|d" /etc/fstab
                _green "已清理（原文件已备份）。"
            fi
        fi
    }

    format_part() {
        local part="$1" mp fst choice fs uuid mp2
        mp=$(part_mountpoint "$part")
        [ -n "$mp" ] && { _red "请先卸载该分区再格式化（当前挂载于 $mp）。"; return 1; }
        echo "  1) ext4   2) xfs   3) ext3   4) ext2   b) 取消"
        read -ep "选择目标文件系统: " choice
        case "$choice" in
            1) fs=ext4;; 2) fs=xfs;; 3) fs=ext3;; 4) fs=ext2;; b|B) return 0;;
            *) _red "无效选择。"; return 1;;
        esac
        need_cmd "mkfs.$fs" || return 1
        fst=$(part_fstype "$part")
        _red "警告：格式化会清空 $(basename "$part") 的全部数据${fst:+（当前文件系统：$fst）}！"
        confirm_yes "确认格式化为 $fs？（输入 yes）: " || { echo "已取消。"; return 0; }
        case "$fs" in
            xfs)  mkfs.xfs -f "$part" ;;
            *)    mkfs -t "$fs" -F "$part" ;;
        esac
        if [ $? -ne 0 ]; then _red "格式化失败。"; return 1; fi
        _green "已格式化为 $fs。"
        if confirm_yes "是否挂载并写入 fstab？（输入 yes 继续）: "; then
            read -ep "挂载点（如 /mnt/data）: " mp2
            validate_mount_path "$mp2" || return 1
            mkdir -p "$mp2" && mount "$part" "$mp2" || { _red "挂载失败。"; return 1; }
            uuid=$(blkid -s UUID -o value "$part")
            if [ -n "$uuid" ] && ! grep -q "$uuid" /etc/fstab; then
                cp -a /etc/fstab /etc/fstab.bak.$(date +%s)
                echo "UUID=$uuid $mp2 $fs defaults 0 2" >> /etc/fstab
            fi
            _green "完成：$part -> $mp2"
        fi
    }

    convert_fs() {
        local part="$1" fst mp target rc
        mp=$(part_mountpoint "$part")
        fst=$(part_fstype "$part")
        if [ "$fst" != "ext2" ]; then
            _yellow "仅支持 ext2 → ext3/ext4 的无损转换；当前为 ${fst:-未知}。跨文件系统请用“格式化/重建”（会清空数据）。"
            return 0
        fi
        [ -n "$mp" ] && { _red "请先卸载该分区再转换（当前挂载于 $mp）。"; return 1; }
        need_cmd tune2fs || return 1
        need_cmd e2fsck || return 1
        echo "  1) 转为 ext3   2) 转为 ext4"
        read -ep "选择: " target
        case "$target" in
            1) tune2fs -j "$part" && e2fsck -f -y "$part";;
            2) tune2fs -O extents,uninit_bg,dir_index "$part" && e2fsck -f -y "$part";;
            *) _red "无效选择。"; return 1;;
        esac
        rc=$?
        [ "$rc" -eq 0 ] && _green "转换完成，当前文件系统：$(part_fstype "$part")" || _red "转换失败。"
    }

    create_part() {
        local disk="$1" sel target start end gap size_b newpart tbl
        local s e i
        local -a starts=() ends=()
        need_cmd parted || return 1
        echo "=== 磁盘 $disk 上的空闲空间 ==="
        while read -r s e; do
            (( e - s <= 1048576 )) && continue
            starts+=("$s"); ends+=("$e")
            printf "  %2d) %d MiB ~ %d MiB（可用 %d MiB）\n" "${#starts[@]}" $(( s/1048576 )) $(( e/1048576 )) $(( (e-s)/1048576 ))
        done < <(parted -m -s "$disk" unit B print free 2>/dev/null | awk -F: '{
                    line=$0; gsub(/;/,"",line); n=split(line,f,":")
                    s=f[2]; e=f[3]; gsub(/B/,"",s); gsub(/B/,"",e)
                    if ((f[6]=="free" || f[5]=="free") && s ~ /^[0-9]+$/ && e ~ /^[0-9]+$/) print s, e
                 }')
        if [ ${#starts[@]} -eq 0 ]; then
            _yellow "parted 未识别到空闲空间，可能是全新磁盘（无分区表）。"
            if confirm_yes "是否创建全新 GPT 分区表并把整盘分为一个分区？（输入 yes）: "; then
                if ! safe_parted "$disk" mklabel gpt; then _red "创建分区表失败。"; return 1; fi
                if ! safe_parted "$disk" mkpart primary ext4 1MiB 100%; then _red "创建分区失败。"; return 1; fi
                partprobe "$disk" 2>/dev/null || true
                newpart="${disk}1"; [[ "$disk" =~ nvme[0-9]+n[0-9]+$ || "$disk" =~ mmcblk[0-9]+$ ]] && newpart="${disk}p1"
                if wait_for_part "$newpart"; then
                    _green "新分区已创建：$newpart"
                    if confirm_yes "是否立即格式化并挂载？（输入 yes 继续）: "; then format_part "$newpart"; fi
                else
                    _yellow "新分区设备节点未及时出现，请手动检查。"
                fi
            fi
            return 0
        fi
        read -ep "选择空闲空间编号（输入 yes 使用最大块，b 取消）: " sel
        [ "$sel" = "b" -o "$sel" = "B" ] && return 0
        if [ "$sel" = "yes" ]; then
            sel=1
            for ((i=2; i<=${#starts[@]}; i++)); do
                (( ends[$((i-1))] - starts[$((i-1))] > ends[$((sel-1))] - starts[$((sel-1))] )) && sel=$i
            done
        fi
        [[ "$sel" =~ ^[0-9]+$ ]] && (( sel>=1 && sel<=${#starts[@]} )) || { _red "无效选择。"; return 1; }
        start=${starts[$((sel-1))]}; gap=$(( ends[$((sel-1))] - start ))
        read -ep "新分区大小（如 10G / 500M / 50%，回车用全部）: " target
        [ -z "$target" ] && target="$gap"
        size_b=$(parse_size_bytes "$target" "$gap") || { _red "大小格式无效。"; return 1; }
        (( size_b > gap )) && size_b=$gap
        end=$(( start + size_b - 1 ))
        _red "警告：即将在 $disk 上创建分区（$(( size_b/1048576 )) MiB），请确认数据已备份。"
        confirm_yes "确认创建？（输入 yes）: " || { echo "已取消。"; return 0; }
        if ! safe_parted "$disk" mkpart primary ext4 "${start}B" "${end}B"; then
            _red "创建分区失败。"; return 1
        fi
        partprobe "$disk" 2>/dev/null || true
        newpart=$(parted -m -s "$disk" unit B print 2>/dev/null | awk -F: '$1 ~ /^[0-9]+$/ {last=$1} END{print last}')
        if [ -z "$newpart" ]; then
            _yellow "无法确定新分区号，请手动检查。"
            return 1
        fi
        if [[ "$disk" =~ nvme[0-9]+n[0-9]+$ || "$disk" =~ mmcblk[0-9]+$ ]]; then
            newpart="${disk}p${newpart}"
        else
            newpart="${disk}${newpart}"
        fi
        wait_for_part "$newpart" || { _yellow "新分区设备节点未及时出现，请手动检查。"; return 1; }
        _green "新分区已创建：$newpart"
        if confirm_yes "是否立即格式化并挂载？（输入 yes 继续）: "; then
            format_part "$newpart"
        fi
    }

    convert_partition_table() {
        local disk="$1" cur c newtype
        need_cmd parted || return 1
        need_cmd sgdisk || return 1
        cur=$(disk_table_type "$disk")
        [ -z "$cur" ] && { _red "无法识别当前分区表类型。"; return 1; }
        if lsblk -n -o MOUNTPOINT "$disk" 2>/dev/null | grep -q .; then
            _red "该磁盘有已挂载分区，请先卸载后再转换。"
            return 1
        fi
        echo "当前分区表类型：$cur"
        _red "警告：转换分区表会清空磁盘上所有分区和数据，不可撤销！"
        confirm_yes "确认清空所有分区并转换？（输入 yes）: " || { echo "已取消。"; return 0; }
        if [ "$cur" = "gpt" ]; then
            command -v sgdisk >/dev/null 2>&1 && sgdisk -b "/root/$(basename "$disk").sgdisk.bak.$(date +%s)" "$disk" >/dev/null 2>&1 || true
        else
            command -v sfdisk >/dev/null 2>&1 && sfdisk -d "$disk" > "/root/$(basename "$disk").sfdisk.bak.$(date +%s)" 2>/dev/null || true
        fi
        sgdisk -Z "$disk" || { _red "清空分区表失败。"; return 1; }
        if [ "$cur" = "gpt" ]; then
            safe_parted "$disk" mklabel msdos; newtype="MBR(msdos)"
        else
            safe_parted "$disk" mklabel gpt; newtype="GPT"
        fi
        partprobe "$disk" 2>/dev/null || true
        _green "分区表已转换为 $newtype（分区表备份在 /root/）。请用“新建分区”重新创建分区。"
    }

    wipe_and_format_disk() {
        local disk="$1" part
        if lsblk -n -o MOUNTPOINT "$disk" 2>/dev/null | grep -q .; then
            _red "该磁盘有已挂载分区，请先卸载后再格式化整盘。"
            return 1
        fi
        need_cmd parted || return 1
        _red "警告：将清空磁盘 $disk 上的全部数据，不可撤销！"
        confirm_yes "确认继续？（输入 yes）: " || { echo "已取消。"; return 0; }
        safe_parted "$disk" mklabel gpt || { _red "创建分区表失败。"; return 1; }
        safe_parted "$disk" mkpart primary ext4 1MiB 100% || { _red "创建分区失败。"; return 1; }
        partprobe "$disk" 2>/dev/null || true
        part="${disk}1"
        [[ "$disk" =~ nvme[0-9]+n[0-9]+$ || "$disk" =~ mmcblk[0-9]+$ ]] && part="${disk}p1"
        wait_for_part "$part" || { _red "新分区未出现，请手动检查。"; return 1; }
        format_part "$part"
    }

    menuname='首页/磁盘管理'
    echo "diskfun" >$installdir/config/lastfun
    options=("磁盘信息" diskinfo "磁盘占用扫描" diskscan "查看磁盘SMART信息" disksmartinfo "磁盘测速" diskspeedtest "扩容根分区" expandroot "swap分区转swapfile" swap_to_swapfile "磁盘分区" disk_manager "一键格式化磁盘并挂载" formatotherdisks)

    menu "${options[@]}"

}
