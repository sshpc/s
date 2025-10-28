diskfun() {
    beforeMenu(){
    _blue "> ---  当前目录: [ $(pwd) ] ---- < v:${branch}-$selfversion"
    echo
    _yellow "当前菜单: $menuname "
    echo
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

        echo -e "\n${_green}根设备:${_reset}        $root_dev"
        echo -e "${_green}文件系统类型:${_reset}  $fs_type"
        echo -e "${_green}是否为 LVM:${_reset}    $is_lvm"

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
        filled_bar=$(printf '█%.0s' $(seq 1 $filled))
        empty_bar=$(printf '░%.0s' $(seq 1 $empty))
        echo -e "  ${color}${filled_bar}${empty_bar}\e[0m  ${pcent}  ($used/$size)"

        
        # 仅展示物理磁盘型号和容量
        _blue "\n物理磁盘"
        fdisk -l 2>/dev/null | grep -E "Disk /dev|Disk model" | sed 's/^/  /'
    }


    disksmartinfo(){
        # 磁盘SMART状态自动检查与处理脚本

        # 检查root权限
        if [ "$(id -u)" -ne 0 ]; then
            echo "错误：需要root权限，请用sudo运行"
            exit 1
        fi

        # 检查并安装smartmontools
        if ! command -v smartctl &> /dev/null; then
            check_and_install smartmontools
        fi

        # 获取磁盘列表（排除分区）
        disks=$(lsblk -d -n -o NAME | grep -E '^sd|^nvme|^hd|^vd')
        if [ -z "$disks" ]; then
            echo "未检测到磁盘设备"
            exit 0
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

            # 关键指标提取
            temp=$(smartctl -A "$device" 2>/dev/null | grep -E 'Temperature_Celsius|Temperature' | awk '{print $10}')
            realloc=$(smartctl -A "$device" 2>/dev/null | grep -E 'Reallocated_Sector_Ct|Reallocated_NAND_Blk_Ct' | awk '{print $10}')
            power_on=$(smartctl -A "$device" 2>/dev/null | grep -E 'Power_On_Hours|Power-On_Hours' | awk '{print $10}')

            # 显示指标
            echo "温度：${temp:-未知}°C $( [ -n "$temp" ] && [ "$temp" -ge 50 ] && echo "(警告：偏高)" )"
            echo "重新分配扇区数：${realloc:-0} $( [ -n "$realloc" ] && [ "$realloc" -gt 0 ] && echo "(警告：存在坏道)" )"
            echo "累计通电时间：${power_on:-0}小时"

            # 统计警告
            if [ "$current_status" = "健康" ]; then
                if ( [ -n "$temp" ] && [ "$temp" -ge 50 ] ) || ( [ -n "$realloc" ] && [ "$realloc" -gt 0 ] ); then
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

    #磁盘测速
    diskspeedtest() {
        #io测试
        io_test() {
            (dd if=/dev/zero of=benchtest_$$ bs=512k count=$1 conv=fdatasync && rm -f benchtest_$$) 2>&1 | awk -F, '{io=$NF} END { print io}' | sed 's/^[ \t]*//;s/[ \t]*$//'
        }
        _blue "正在进行磁盘测速..."
        echo
        freespace=$(df -m . | awk 'NR==2 {print $4}')
        if [ -z "${freespace}" ]; then
            freespace=$(df -m . | awk 'NR==3 {print $3}')
        fi
        if [ ${freespace} -gt 1024 ]; then
            io1=$(io_test 2048)
            echo " I/O Speed(1st run) : $(_yellow "$io1")"
            io2=$(io_test 2048)
            echo " I/O Speed(2nd run) : $(_yellow "$io2")"
            io3=$(io_test 2048)
            echo " I/O Speed(3rd run) : $(_yellow "$io3")"
            ioraw1=$(echo $io1 | awk 'NR==1 {print $1}')
            [ "$(echo $io1 | awk 'NR==1 {print $2}')" == "GB/s" ] && ioraw1=$(awk 'BEGIN{print '$ioraw1' * 1024}')
            ioraw2=$(echo $io2 | awk 'NR==1 {print $1}')
            [ "$(echo $io2 | awk 'NR==1 {print $2}')" == "GB/s" ] && ioraw2=$(awk 'BEGIN{print '$ioraw2' * 1024}')
            ioraw3=$(echo $io3 | awk 'NR==1 {print $1}')
            [ "$(echo $io3 | awk 'NR==1 {print $2}')" == "GB/s" ] && ioraw3=$(awk 'BEGIN{print '$ioraw3' * 1024}')
            ioall=$(awk 'BEGIN{print '$ioraw1' + '$ioraw2' + '$ioraw3'}')
            ioavg=$(awk 'BEGIN{printf "%.1f", '$ioall' / 3}')
            echo " I/O Speed(average) : $(_yellow "$ioavg MB/s")"
        else
            echo " $(_red "Not enough space for I/O Speed test!")"
        fi
    }

    #扩容根分区
    expandroot(){
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
                check_and_install lvs lvm2
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
            
            # ensure growpart exists 
            check_and_install growpart cloud-guest-utils cloud-utils-growpart partprobe parted pvresize lvm2 lvextend
            
            # FS 工具
            if [ "$FSTYPE" = "xfs" ]; then
                check_and_install xfs_growfs xfsprogs
            else
                check_and_install resize2fs e2fsprogs
            fi
            
            # 构建命令序列（打印给用户确认）
            cmds+=("growpart $DISK $PARTNUM")
            cmds+=("partprobe $DISK || partx -u $DISK")
            cmds+=("pvresize $PV0_DEV")
            cmds+=("lvextend -l +100%FREE /dev/$VG_NAME/$LV_NAME")
            if [ "$FSTYPE" = "xfs" ]; then
                # xfs_growfs 需要传入 mountpoint（根为 /）
                cmds+=("xfs_growfs /")
            else
                cmds+=("resize2fs /dev/$VG_NAME/$LV_NAME")
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
            
            # ensure growpart & fs tools installed
            check_and_install growpart cloud-guest-utils cloud-utils-growpart partprobe parted
            
            if [ "$FSTYPE" = "xfs" ]; then
                check_and_install xfs_growfs xfsprogs
            else
                check_and_install resize2fs e2fsprogs
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
            if bash -c "$c"; then
                echo "第 $i 条命令成功。"
            else
                echo "第 $i 条命令失败，停止执行。请手动检查或恢复备份。"
                exit 1
            fi
            i=$((i+1))
        done
        
        echo
        df -h /
        
    }

    formatotherdisks(){
        echo "正在扫描未挂载磁盘..."

        # 获取根磁盘名（例如 /dev/sda）
        ROOT_DISK=$(df / | tail -1 | awk '{print $1}' | sed 's/[0-9]*$//')

        # 获取所有磁盘
        ALL_DISKS=($(lsblk -dpno NAME,TYPE | awk '$2=="disk"{print $1}'))

        # 过滤掉根磁盘
        UNUSED_DISKS=()
        for d in "${ALL_DISKS[@]}"; do
        if [[ "$d" != "$ROOT_DISK" ]]; then
            UNUSED_DISKS+=("$d")
        fi
        done

        if [[ ${#UNUSED_DISKS[@]} -eq 0 ]]; then
        echo "未发现未使用的磁盘。"
        exit 0
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
        exit 1
        fi

        DISK=${UNUSED_DISKS[$((choice-1))]}
        _blue "已选择磁盘: $DISK"

        # 检查是否已有分区
        PART="${DISK}1"
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

        # 写入 /etc/fstab（可选）
        UUID=$(blkid -s UUID -o value "$PART")
        if ! grep -q "$UUID" /etc/fstab; then
        echo "UUID=$UUID $MOUNT_POINT ext4 defaults 0 2" >> /etc/fstab
        _blue "已添加到 /etc/fstab，重启后将自动挂载。"
        fi

        _green "操作完成！当前挂载："
        df -h | grep "$MOUNT_POINT"

        
    }

    menuname='首页/磁盘管理'
    echo "diskfun" >$installdir/config/lastfun
    options=("磁盘信息" diskinfo "查看磁盘SMART信息" disksmartinfo "磁盘测速" diskspeedtest "扩容根分区" expandroot "格式化其他磁盘并挂载" formatotherdisks)

    menu "${options[@]}"

}