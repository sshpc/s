diskfun() {
    beforeMenu(){
    _blue "> ---  当前目录: [ $(pwd) ] ---- < v:$selfversion"
    echo
    _yellow "当前菜单: $menuname "
    echo
    }

    # apt 上 growpart 的真实包名是 cloud-guest-utils；部分系统包名为 cloud-utils-growpart。
    # check_and_install 只接受包名，不能直接传 growpart/partprobe/lvs 等命令名。
    ensure_growpart() {
        if ! command -v growpart >/dev/null 2>&1; then
            check_and_install cloud-guest-utils || check_and_install cloud-utils-growpart
        fi
    }

    # 列出 swap 分区设备（排除 swapfile），输出形如 /dev/sda3
    list_swap_parts() {
        {
            # blkid 最直接：按文件系统类型找 swap 分区
            blkid -t TYPE=swap -o device 2>/dev/null
            # /proc/swaps 的第一列也包含已启用的 swap 设备，过滤出 /dev/ 项
            awk 'NR>1 && $1 ~ /^\/dev\// {print $1}' /proc/swaps 2>/dev/null
        } | sort -u | grep '^/dev/' || true
    }

    # 磁盘详细信息
    diskinfo() {
        echo
        _blue "==== 磁盘详细信息 ===="

        # 根设备信息
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

        # 根分区使用率条
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
        # seq 1 0 虽不产生参数，但 printf 的无参数格式仍会执行一次，导致 0% 时多画一格
        if (( filled > 0 )); then filled_bar=$(printf '█%.0s' $(seq 1 "$filled")); else filled_bar=""; fi
        if (( empty > 0 )); then empty_bar=$(printf '░%.0s' $(seq 1 "$empty")); else empty_bar=""; fi
        echo -e "  ${color}${filled_bar}${empty_bar}\e[0m  ${pcent}  ($used/$size)"

        # 扫描所有已挂载的文件系统（包括其他挂载的磁盘，排除 loop 设备）
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

        # 所有物理磁盘（包括未挂载的其他磁盘）
        # 容量优先用 lsblk 的设备 SIZE（内核报告的真实容量）；若为空，
        # 则回退为各分区 SIZE 之和；再不行就用分区块设备推算。
        _blue "\n=== 所有物理磁盘 ==="
        echo "  磁盘设备           型号                      容量      使用率"
        # 用不可见分隔符 | 分隔，避免型号里的空格（如 "VMware Virtual SATA..."）
        # 造成 read 字段错位，把型号后半段挤到容量列。
        while IFS='|' read -r name model size; do
            [[ -z "$name" ]] && continue
            if [[ -z "$size" ]]; then
                # 回退：只累加分区的容量（避免把磁盘自身重复算进去）
                size=$(lsblk -b -n -o SIZE,TYPE "/dev/$name" 2>/dev/null | awk '$2=="part"{s+=$1} END {if (s>0) printf "%.1fG", s/1024/1024/1024}')
            fi
            # 使用率 = 该磁盘所有已挂载分区的 used 之和 / size 之和（MB）
            # 直接按分区的挂载点取 df，比按设备名匹配 df 的 source 列更可靠。
            # 没有已挂载分区时 total_size 为 0，使用率记为 0。
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
    #磁盘占用扫描
    diskscan(){
        check_and_install gdu
        gdu /
    }


    disksmartinfo(){
        # 磁盘SMART状态自动检查与处理脚本

        # 温度告警阈值可配置：SMART_TEMP_WARN=55 s diskfun disksmartinfo
        SMART_TEMP_WARN=${SMART_TEMP_WARN:-50}

        # 从 smartctl -A 提取属性值；兼容 SATA（属性名在第 2 列）与 NVMe（Key: value 形式）。
        # 只输出纯数字，避免温度行带 "(Min/Max ...)" 时比较报错。
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

        # 检查root权限（这里必须用 return，exit 会直接干掉整个 s 脚本）
        if [ "$(id -u)" -ne 0 ]; then
            echo "错误：需要root权限，请用sudo运行"
            return 1
        fi

        # 检查并安装smartmontools
        if ! command -v smartctl &> /dev/null; then
            check_and_install smartmontools
        fi

        # 获取磁盘列表（排除分区）
        disks=$(lsblk -d -n -o NAME | grep -E '^sd|^nvme|^hd|^vd')
        if [ -z "$disks" ]; then
            echo "未检测到磁盘设备"
            return 0
        fi

        # 统计变量
        total=0
        healthy=0
        warning=0
        error=0
        unsupported=0

        echo "===== 开始磁盘SMART检查 ====="
        echo "检测到磁盘数：$(echo "$disks" | wc -l)"

        # 遍历磁盘检查
        for disk in $disks; do
            total=$((total + 1))
            device="/dev/$disk"
            echo -e "\n----- 检查磁盘：$device -----"

            # 检查SMART支持
            smart_info=$(smartctl -i "$device" 2>/dev/null)
            if echo "$smart_info" | grep -q "SMART support is: Unavailable"; then
                echo "不支持SMART功能"
                unsupported=$((unsupported + 1))
                continue
            fi

            # 启用SMART（若未启用）
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

            # 健康状态检查
            health=$(smartctl -H "$device" 2>/dev/null | grep "test result")
            if echo "$health" | grep -q "PASSED"; then
                echo "健康状态：正常（PASSED）"
                current_status="健康"
            else
                echo "健康状态：异常（FAILED）"
                current_status="异常"
                error=$((error + 1))
            fi

            # 关键指标提取（兼容 SATA/NVMe，只取纯数字）
            temp=$(smart_attr "$device" Temperature_Celsius)
            [ -z "$temp" ] && temp=$(smart_attr "$device" Temperature)
            realloc=$(smart_attr "$device" Reallocated_Sector_Ct)
            [ -z "$realloc" ] && realloc=$(smart_attr "$device" Reallocated_NAND_Blk_Ct)
            power_on=$(smart_attr "$device" Power_On_Hours)
            [ -z "$power_on" ] && power_on=$(smart_attr "$device" Power-On_Hours)

            # 显示指标
            echo "温度：${temp:-未知}°C $( [ -n "$temp" ] && [ "$temp" -ge "$SMART_TEMP_WARN" ] && echo "(警告：偏高)" )"
            echo "重新分配扇区数：${realloc:-0} $( [ -n "$realloc" ] && [ "$realloc" -gt 0 ] && echo "(警告：存在坏道)" )"
            echo "累计通电时间：${power_on:-0}小时"

            # 统计警告
            if [ "$current_status" = "健康" ]; then
                if ( [ -n "$temp" ] && [ "$temp" -ge "$SMART_TEMP_WARN" ] ) || ( [ -n "$realloc" ] && [ "$realloc" -gt 0 ] ); then
                    warning=$((warning + 1))
                else
                    healthy=$((healthy + 1))
                fi
            fi
        done

        # 汇总结果
        echo -e "\n===== 检查完成 ====="
        echo "总磁盘数：$total"
        echo "健康：$healthy 个"
        echo "警告（温度高/坏道）：$warning 个"
        echo "错误（健康异常/开启失败）：$error 个"
        echo "不支持SMART：$unsupported 个"

        # 异常提示
        if [ $error -gt 0 ]; then
            echo "警告：存在异常磁盘，建议备份数据并检查硬件"
        elif [ $warning -gt 0 ]; then
            echo "提示：存在警告磁盘，建议关注状态变化"
        else
            echo "所有磁盘状态正常"
        fi
    }

    diskspeedtest() {
        # 每次写入 512k × IO_TEST_BLOCKS（默认 1GB），测试 IO_TEST_RUNS 次（默认 3 次），
        # 可用环境变量覆盖，例如：IO_TEST_BLOCKS=512 IO_TEST_RUNS=2 s diskfun diskspeedtest
        IO_TEST_BLOCKS=${IO_TEST_BLOCKS:-2048}
        IO_TEST_RUNS=${IO_TEST_RUNS:-3}

        # 让用户选择测试哪块磁盘（在对应磁盘的挂载点写入；未挂载分区则跳过）
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

    #扩容根分区
    expandroot(){
        # 严格模式放进子 shell：函数返回时不会把 -euo pipefail 泄漏到全局 shell
        (
        set -euo pipefail
        
        # helpers
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

        # 检测 swap 分区：其存在会占用根磁盘尾部空间，导致 growpart 后根分区无法扩张。
        # 这里只做提示，不自动删除；需要一键处理请用菜单的 “swap分区转swapfile” 功能。
        local _swap_parts
        _swap_parts=$(list_swap_parts)
        if [ -n "$_swap_parts" ]; then
            echo
            _yellow "提示：检测到 swap 分区：$(echo "$_swap_parts" | tr '\n' ' ')"
            _yellow "      swap 分区位于根磁盘尾部时，即使 growpart 成功，根分区也可能无法扩张。"
            _yellow "      可先用菜单的 “swap分区转swapfile” 功能删除 swap 分区并以 swapfile 替代，再回来扩容。"
        fi
        
        cmds=()
        
        # detect LVM
        if echo "$ROOT_DEV" | grep -qE '^/dev/mapper/|^/dev/VolGroup|^/dev/.*/.*$'; then
            is_lvm=1
        else
            is_lvm=0
        fi
        echo "是否为 LVM: $([ "$is_lvm" -eq 1 ] && echo yes || echo no)"
        
        # prepare commands depending on LVM or not
        if [ "$is_lvm" -eq 1 ]; then
            echo
            echo "== LVM 根分区流程: 解析 VG/LV/PV =="
            # 获取 LV 路径、VG、LV 名称
            # ROOT_SRC 可能像 /dev/mapper/vg-lv 或 /dev/mapper/ubuntu--vg-root
            # 使用 lvs 获取 lv_name, vg_name
            if ! command -v lvs >/dev/null 2>&1; then
                echo "[*] 需要安装 lvm2"
                check_and_install lvm2
            fi
            
            VG_NAME=$(lvs --noheadings -o vg_name --units '' --nosuffix "$ROOT_DEV" 2>/dev/null | awk '{print $1}' || true)
            LV_NAME=$(lvs --noheadings -o lv_name --units '' --nosuffix "$ROOT_DEV" 2>/dev/null | awk '{print $1}' || true)
            if [ -z "$VG_NAME" ] || [ -z "$LV_NAME" ]; then
                # 尝试从 lvdisplay 解析
                VG_NAME=$(lvdisplay "$ROOT_DEV" 2>/dev/null | awk -F': ' '/VG Name/{print $2; exit}' || true)
                LV_NAME=$(lvdisplay "$ROOT_DEV" 2>/dev/null | awk -F': ' '/LV Name/{print $2; exit}' || true)
            fi
            if [ -z "$VG_NAME" ] || [ -z "$LV_NAME" ]; then
                echo "无法解析 VG/LV 名称：VG='$VG_NAME' LV='$LV_NAME'，请手动检查。"
                exit 1
            fi
            LV_PATH="$ROOT_DEV"
            echo "VG: $VG_NAME  LV: $LV_NAME  LV_PATH: $LV_PATH"
            
            # 找到属于该 VG 的 PV 列表（挑第一个 PV 作为扩容目标）
            PVS=$(pvs --noheadings -o pv_name,vg_name --units '' --nosuffix 2>/dev/null | awk -v vg="$VG_NAME" '$2==vg{print $1}' | tr -d ' ' || true)
            if [ -z "$PVS" ]; then
                echo "未找到 VG 的 PV 列表，请检查：pvs 输出为空。"
                exit 1
            fi
            PV0=$(echo "$PVS" | head -n1)
            PV0_DEV=$(resolve_dev "$PV0")
            echo "选择 PV: $PV0 -> $PV0_DEV"
            
            # 获取 PV 的父磁盘与分区号（例如 /dev/sda2）
            PKNAME=$(lsblk -no PKNAME "$PV0_DEV" || true)
            if [ -z "$PKNAME" ]; then
                echo "无法解析 PV 的父磁盘（可能是整盘 PV 或特殊情况），PV: $PV0_DEV"
                # 如果 PV 是整盘（/dev/sdb）而不是分区，则直接在整盘上扩展不常见，退出提示人工处理。
                echo "PV 不是分区（或无法解析）。请手动检查并处理。"
                exit 1
            fi
            DISK="/dev/$PKNAME"
            PARTNUM=$(basename "$PV0_DEV" | sed "s/^$PKNAME//")
            # handle pX naming (e.g. /dev/nvme0n1p2)
            if [ -z "$PARTNUM" ]; then
                # fallback: try extract digits at end
                PARTNUM=$(echo "$PV0_DEV" | grep -oE '[0-9]+$' || true)
            fi
            if [ -z "$PARTNUM" ]; then
                echo "无法解析 PV 的分区号，手动检查：PV0_DEV=$PV0_DEV"
                exit 1
            fi
            
            echo "PV 所在磁盘: $DISK 分区号: $PARTNUM"
            
            # ensure growpart / 分区与 LVM 工具存在（只传包名）
            ensure_growpart
            check_and_install parted lvm2
            
            # FS 工具
            if [ "$FSTYPE" = "xfs" ]; then
                check_and_install xfsprogs
            else
                check_and_install e2fsprogs
            fi
            
            # 构建命令序列（打印给用户确认）
            cmds+=("growpart $DISK $PARTNUM")
            cmds+=("partprobe $DISK || partx -u $DISK")
            cmds+=("pvresize $PV0_DEV")
            # LV_PATH 为已解析出的真实路径（如 /dev/mapper/ubuntu--vg-root），
            # 比拼接 /dev/$VG_NAME/$LV_NAME 更可靠。
            cmds+=("lvextend -l +100%FREE $LV_PATH")
            if [ "$FSTYPE" = "xfs" ]; then
                # xfs_growfs 需要传入 mountpoint（根为 /）
                cmds+=("xfs_growfs /")
            else
                cmds+=("resize2fs $LV_PATH")
            fi
            
        else
            echo
            echo "== 非 LVM 根分区流程 =="
            # ROOT_DEV 例如 /dev/sda2
            PKNAME=$(lsblk -no PKNAME "$ROOT_DEV" || true)
            if [ -z "$PKNAME" ]; then
                echo "无法解析根分区的父磁盘，退出。"
                exit 1
            fi
            DISK="/dev/$PKNAME"
            # extract partition number: root_dev minus disk prefix (handle nvme p2)
            PARTNUM=$(basename "$ROOT_DEV" | sed "s/^$PKNAME//")
            if [ -z "$PARTNUM" ]; then
                PARTNUM=$(echo "$ROOT_DEV" | grep -oE '[0-9]+$' || true)
            fi
            if [ -z "$PARTNUM" ]; then
                echo "无法确定分区号，请手动检查：ROOT_DEV=$ROOT_DEV"
                exit 1
            fi
            echo "根分区所在磁盘: $DISK 分区号: $PARTNUM"
            
            # ensure growpart & fs tools installed（只传包名）
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
        
        # print commands and confirm
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
        
        # execute
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
                # growpart 的 NOCHANGE 表示分区已到磁盘末尾、无法再扩张（磁盘无剩余空间，
                # 或后面有 swap 等分区挡着），属于正常的“无需扩容”，不应中止；
                # 后续 resize2fs/xfs_growfs 仍可能把文件系统扩到现有分区大小。
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

        # 找到根设备所属的物理磁盘（兼容 NVMe /dev/nvme0n1p1、LVM、普通分区）。
        # 简单 sed 去数字对 nvme0n1p1 只会得到 /dev/nvme0n1p，LVM 更完全无效，
        # 会导致根盘无法被排除、有误格式化风险。
        ROOT_SRC=$(findmnt -n -o SOURCE / 2>/dev/null)
        ROOT_DISK=""
        if [ -n "$ROOT_SRC" ]; then
            ROOT_DEV=$(readlink -f "$ROOT_SRC" 2>/dev/null || echo "$ROOT_SRC")
            # 沿持有者链向上找到真正的物理磁盘（LVM/RAID 情况）
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

        # 获取所有磁盘，排除根磁盘以及任何含已挂载分区的磁盘
        ALL_DISKS=($(lsblk -dpno NAME,TYPE | awk '$2=="disk"{print $1}'))
        UNUSED_DISKS=()
        for d in "${ALL_DISKS[@]}"; do
            [[ "$d" == "$ROOT_DISK" ]] && continue
            # 只要磁盘上任意一个分区被挂载（含 swap），就跳过，避免误清已有数据
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

        # 用户选择磁盘
        read -p "请输入要格式化的磁盘编号: " choice
        if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#UNUSED_DISKS[@]} )); then
        echo "无效选择。"
        return 1
        fi

        DISK=${UNUSED_DISKS[$((choice-1))]}
        _blue "已选择磁盘: $DISK"

        # 二次确认（破坏性操作必须显式确认）
        _red "警告：即将完全清除磁盘 $DISK 上的所有数据，此操作不可撤销！"
        read -p "请再次输入 yes 确认格式化: " confirm
        if [[ "$confirm" != "yes" ]]; then
            echo "已取消。"
            return 0
        fi

        # 确保所需工具已安装（check_and_install 只接受包名）
        check_and_install parted
        ensure_growpart
        check_and_install e2fsprogs

        # 分区名：NVMe 设备为 p1 后缀，普通磁盘为 1
        PART="${DISK}1"
        [[ "$DISK" =~ nvme[0-9]+n[0-9]+$ ]] && PART="${DISK}p1"
        if ! ls ${PART} &>/dev/null; then
        _yellow "磁盘 $DISK 没有分区，正在创建新分区..."
        parted -s "$DISK" mklabel gpt
        parted -s "$DISK" mkpart primary ext4 0% 100%
        partprobe "$DISK"
        sleep 2
        fi

        # 扩展分区以使用全部空间
        if command -v growpart &>/dev/null; then
        echo "扩展分区..."
        growpart "$DISK" 1 || true
        else
        echo "未找到 growpart，跳过分区扩展。"
        fi

        # 格式化为 ext4
        _yellow "正在格式化分区 $PART ..."
        mkfs.ext4 -F "$PART"

        # 获取磁盘名称（例如 sdb）
        DISK_NAME=$(basename "$DISK")

        # 提示挂载点
        read -p "请输入挂载点路径（默认 /mnt/$DISK_NAME）: " MOUNT_POINT
        MOUNT_POINT=${MOUNT_POINT:-/mnt/$DISK_NAME}

        mkdir -p "$MOUNT_POINT"
        mount "$PART" "$MOUNT_POINT"

        echo "挂载成功：$PART -> $MOUNT_POINT"

        # 写入 /etc/fstab（可选），先备份原文件
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

        # 1. 检测 swap 分区
        local swap_parts
        swap_parts=$(list_swap_parts)
        if [ -z "$swap_parts" ]; then
            _green "未检测到 swap 分区（可能已是 swapfile 或没有 swap），无需转换。"
            return 0
        fi
        echo "检测到 swap 分区："
        echo "$swap_parts" | sed 's/^/  /'

        # swapfile 大小：优先按原 swap 分区容量，可设置 SWAPFILE_SIZE_M 覆盖
        local swapsize_kb swapsize_m swapfile_size
        swapsize_kb=$(awk '/SwapTotal:/{print $2}' /proc/meminfo 2>/dev/null)
        swapsize_m=$(( swapsize_kb / 1024 ))
        [ "$swapsize_m" -lt 1 ] && swapsize_m=1024
        swapfile_size=${SWAPFILE_SIZE_M:-$swapsize_m}
        echo "原 swap 容量约 ${swapsize_m}M，新 swapfile 大小: ${swapfile_size}M"

        _red "警告：此操作将删除 swap 分区并修改分区表与 /etc/fstab，有数据丢失风险，请先备份。"
        read -p "确认继续？（输入 yes）: " confirm
        [ "$confirm" != "yes" ] && { echo "已取消。"; return 0; }

        # 2. 识别根磁盘与 swap 分区所在磁盘
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

        # 3. 关闭 swap 并备份 /etc/fstab
        swapoff "$swap_dev" 2>/dev/null || true
        cp -a /etc/fstab "/etc/fstab.bak.$(date +%s)"

        # 4. 创建 swapfile（fallocate 快，失败回退 dd）
        local swapfile="/swapfile"
        echo "正在创建 swapfile: $swapfile ($swapfile_size M) ..."
        if ! fallocate -l "${swapfile_size}M" "$swapfile" 2>/dev/null; then
            dd if=/dev/zero of="$swapfile" bs=1M count="$swapfile_size" status=none
        fi
        chmod 600 "$swapfile"
        mkswap "$swapfile" >/dev/null
        swapon "$swapfile"

        # 5. 更新 /etc/fstab：删除原 swap 分区条目，新增 swapfile 条目
        if grep -q "$swap_dev" /etc/fstab; then
            sed -i "\|^[[:space:]]*$swap_dev|d" /etc/fstab
        fi
        if ! grep -q "^[[:space:]]*$swapfile" /etc/fstab; then
            echo "$swapfile none swap sw 0 0" >> /etc/fstab
        fi
        _green "swapfile 已启用并写入 /etc/fstab（原 fstab 已备份）。"

        # 6. 删除 swap 分区并扩展根分区
        # 仅当 swap 分区与根分区在同一磁盘、且 swap 分区号大于根分区号时才可安全删除后 growpart
        local root_partnum swap_partnum
        root_partnum=$(basename "$root_dev" | grep -oE '[0-9]+$')
        swap_partnum=$(basename "$swap_dev" | grep -oE '[0-9]+$')
        if [ "$root_disk" = "$swap_disk" ] && [ -n "$root_partnum" ] && [ -n "$swap_partnum" ] \
            && [ "$swap_partnum" -gt "$root_partnum" ] 2>/dev/null; then
            echo "正在删除 swap 分区 $swap_dev ..."
            # 用 parted 删除分区（GPT/MBR 通用）
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

    menuname='首页/磁盘管理'
    echo "diskfun" >$installdir/config/lastfun
    options=("磁盘信息" diskinfo "磁盘占用扫描" diskscan "查看磁盘SMART信息" disksmartinfo "磁盘测速" diskspeedtest "扩容根分区" expandroot "swap分区转swapfile" swap_to_swapfile "格式化其他磁盘并挂载" formatotherdisks)

    menu "${options[@]}"

}