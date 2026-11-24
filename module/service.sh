servicefun() {
    beforeMenu(){
    _blue "> ---  当前目录: [ $(pwd) ] ---- < v:$selfversion"
    echo
    _yellow "当前菜单: $menuname "
    echo
    }

    # ---------- 服务列表采集 ----------
    # 统一采集 systemd 服务：名称 | 运行状态 | 开机自启状态
    # 结果存放在全局数组 SVC_ROWS（元素格式 name|active|enabled），
    # 同时按需输出为 "name|state" 供后续动作函数使用。
    _svc_collect() {
        SVC_ROWS=()
        local -A seen_active=()
        local -A seen_enabled=()

        # 第一遍：已加载的 unit（含 inactive/failed），拿到真实运行状态
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            # failed 行以 "●" 开头，需要去掉，否则会被当成服务名
            line="${line/#●/}"
            line="${line## }"
            [[ -z "$line" ]] && continue
            local name load active
            name=$(echo "$line" | awk '{print $1}')
            load=$(echo "$line" | awk '{print $2}')
            active=$(echo "$line" | awk '{print $3}')
            [[ -z "$name" ]] && continue
            [[ "$name" == "UNIT" || "$name" == "0" ]] && continue
            # 只接受合法的 unit 名，过滤表头/说明等杂行
            [[ "$name" == *.service ]] || continue
            [[ "$load" == "not-found" ]] && continue
            [[ -n "${seen_active[$name]:-}" ]] && continue
            seen_active[$name]=1
            SVC_ROWS+=("$name|$active|")
        done < <(systemctl list-units --type=service --all --no-legend --no-pager 2>/dev/null)

        # 第二遍：磁盘上全部 unit 文件（含从未启动过的 inactive 服务）+ 自启状态
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            line="${line/#●/}"
            line="${line## }"
            [[ -z "$line" ]] && continue
            local name estate
            name=$(echo "$line" | awk '{print $1}')
            estate=$(echo "$line" | awk '{print $2}')
            [[ -z "$name" ]] && continue
            [[ "$name" == *.service ]] || continue
            [[ "$name" == "UNIT" || "$name" == "0" ]] && continue
            # masked 的服务无法启动，不列入
            [[ "$estate" == "masked" ]] && continue
            seen_enabled[$name]="$estate"
            if [[ -z "${seen_active[$name]:-}" ]]; then
                seen_active[$name]=1
                # 未加载过 = 未运行
                SVC_ROWS+=("$name|inactive|$estate")
            fi
        done < <(systemctl list-unit-files --type=service --no-legend --no-pager 2>/dev/null)

        # 回填自启状态
        local i row
        for i in "${!SVC_ROWS[@]}"; do
            row="${SVC_ROWS[$i]}"
            local nm="${row%%|*}"
            local rest="${row#*|}"
            local act="${rest%%|*}"
            if [[ -n "${seen_enabled[$nm]:-}" ]]; then
                SVC_ROWS[$i]="$nm|$act|${seen_enabled[$nm]}"
            else
                SVC_ROWS[$i]="$nm|$act|unknown"
            fi
        done
    }

    # ---------- 服务列表显示 ----------
    # $1 = running(仅运行中) | inactive/stopped(仅未运行) | enabled | disabled | all
    servicelistfun() {
        echo
        local filter="${1:-all}"
        local list_title="全部服务"

        case "$filter" in
            running)          list_title="运行中的服务" ;;
            inactive|stopped) list_title="未运行的服务" ;;
            enabled)          list_title="已开机自启的服务" ;;
            disabled)         list_title="未开机自启的服务" ;;
            *)                list_title="全部服务" ;;
        esac

        _svc_collect

        if [[ ${#SVC_ROWS[@]} -eq 0 ]]; then
            _yellow "没有找到服务"
            rm -f /tmp/.s_services_list
            return 1
        fi

        local services=()
        local row nm act en
        for row in "${SVC_ROWS[@]}"; do
            nm="${row%%|*}"
            act="${row#*|}"; act="${act%%|*}"
            en="${row##*|}"
            case "$filter" in
                running)  [[ "$act" == "active" ]] || continue ;;
                inactive|stopped)
                          [[ "$act" == "active" ]] && continue ;;
                enabled)  [[ "$en" == "enabled" ]] || continue ;;
                disabled) [[ "$en" == "disabled" ]] || continue ;;
            esac
            services+=("$nm|$act|$en")
        done

        _blue "服务列表: ${list_title}（共 ${#services[@]} 个）"
        echo

        if [[ ${#services[@]} -eq 0 ]]; then
            _yellow "${list_title}为空"
            rm -f /tmp/.s_services_list
            return 1
        fi

        printf "%-5s %-45s %-10s %-10s\n" "序号" "服务名" "状态" "自启"
        printf "%-5s %-45s %-10s %-10s\n" "-----" "---------------------------------------------" "----------" "----------"
        local i name color
        for i in "${!services[@]}"; do
            row="${services[$i]}"
            name="${row%%|*}"
            act="${row#*|}"; act="${act%%|*}"
            en="${row##*|}"
            if [[ "$act" == "active" ]]; then
                color="\033[32m"
            else
                color="\033[31m"
            fi
            printf "%-5d %-45s ${color}%-10s\033[0m %-10s\n" "$((i+1))" "$name" "$act" "$en"
        done

        echo
        # 动作函数读取此文件：name|状态
        : > /tmp/.s_services_list
        for row in "${services[@]}"; do
            nm="${row%%|*}"
            act="${row#*|}"; act="${act%%|*}"
            echo "${nm}|${act}" >> /tmp/.s_services_list
        done
        return 0
    }

    # $1=systemctl 动作  $2=中文说明  $3=列表过滤(running|inactive|enabled|disabled|all)
    serviceactionfun() {
        local action="$1"
        local action_cn="$2"
        local filter="${3:-all}"
        servicelistfun "$filter"
        [[ ! -s /tmp/.s_services_list ]] && { _yellow "没有可选服务"; return; }

        local services_arr=()
        local line
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            services_arr+=("$line")
        done < /tmp/.s_services_list
        rm -f /tmp/.s_services_list

        echo
        read -ep "请输入服务序号 (多个用空格分隔): " choices
        [[ -z "$choices" ]] && { _yellow "已取消"; return; }

        local c
        for c in $choices; do
            if [[ "$c" =~ ^[0-9]+$ ]] && (( c >= 1 && c <= ${#services_arr[@]} )); then
                local svc="${services_arr[$((c-1))]%%|*}"
                _blue "${action_cn}服务: $svc"
                systemctl "$action" "$svc" 2>&1
                if [[ $? -eq 0 ]]; then
                    _green "$svc ${action_cn}成功"
                else
                    _red "$svc ${action_cn}失败"
                fi
            else
                _red "无效序号: $c"
            fi
        done
    }

    servicedetailfun() {
        servicelistfun "running"
        [[ ! -s /tmp/.s_services_list ]] && { _yellow "没有运行中的服务"; return; }

        local services_arr=()
        local line
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            services_arr+=("$line")
        done < /tmp/.s_services_list
        rm -f /tmp/.s_services_list

        echo
        read -ep "请输入服务序号查看详细（仅运行中）: " choice
        [[ -z "$choice" ]] && return

        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#services_arr[@]} )); then
            local svc="${services_arr[$((choice-1))]%%|*}"
            echo
            systemctl status "$svc" --no-pager
        else
            _red "无效序号"
        fi
    }
    serviceenablesel() {
        serviceactionfun "enable" "启用自启" "disabled"
    }

    servicedisablesel() {
        serviceactionfun "disable" "禁用自启" "enabled"
    }

    runningservices() { servicelistfun "running"; }
    allservices() { servicelistfun "all"; }
    startservicesel() { serviceactionfun "start" "启动" "inactive"; }
    stopservicesel() { serviceactionfun "stop" "停止" "running"; }
    restartservicesel() { serviceactionfun "restart" "重启" "running"; }


    customservicefun() {

        serviceadd() {

            _yellow "systemctl stop/start 服务名称"
            echo
            read -ep "请输入服务名称: " systemdname
            # 检查服务是否已存在
            if systemctl list-unit-files | grep -q "^${systemdname}.service"; then
                _red "服务 ${systemdname} 已存在"
                return
            fi
            echo '例子:'
            _yellow "xxx.sh  bash /root/xxx.sh  >> /root/systemdname.log 2>&1"
            _yellow "openvpn --config xxx.ovpn >> /root/openvpn.log 2>&1"
            echo
            read -ep "请输入执行程序: " execcmd
            [[ -z "$execcmd" ]] && { _red "执行命令不能为空"; return; }
            echo
            _yellow "例子: /root 或 /usr/local/bin（留空则使用系统默认目录 /）"
            echo
            read -ep "请输入执行目录: " workdir
            # 空值处理：默认使用根目录 /
            [[ -z "$workdir" ]] && workdir="/"
            # 检查目录是否存在（可选，增强健壮性）
            if [[ ! -d "$workdir" ]]; then
                _red "警告：执行目录 ${workdir} 不存在，是否继续？(y/n)"
                read -r confirm
                [[ "$confirm" != "y" && "$confirm" != "Y" ]] && { _red "操作取消"; return; }
            fi

            echo '例子:'
            _yellow "pkill -f xxx(进程名)  or pkill -9 -f xxx"

            echo
            read -ep "请输入终止程序(默认 pkill -f $systemdname): " stopcmd
            [[ -z "$stopcmd" ]] && stopcmd="pkill -f $systemdname"
            echo
            next
            _green "服务名称: $systemdname"
            echo
            _green "执行程序: $execcmd"
            echo
            _green "执行目录: $workdir" 
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
            echo "WorkingDirectory=$workdir" >>/usr/lib/systemd/system/$systemdname.service
            echo "ExecStart=$execcmd" >>/usr/lib/systemd/system/$systemdname.service
            echo "ExecStop=$stopcmd" >>/usr/lib/systemd/system/$systemdname.service
            echo "RestartSec=5" >>/usr/lib/systemd/system/$systemdname.service
            echo " " >>/usr/lib/systemd/system/$systemdname.service
            echo "[Install]" >>/usr/lib/systemd/system/$systemdname.service
            echo "WantedBy=multi-user.target" >>/usr/lib/systemd/system/$systemdname.service
            echo

            _blue "配置开机自启"
            systemctl daemon-reload
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

        #服务配置日志
        servicelogfun() {
            _yellow systemctl
            echo
            #读取日志
            slog get systemctl
        }

        menuname='首页/服务/自定义服务'
        options=("添加服务" serviceadd "删除服务" servicedel "服务配置日志" servicelogfun)

        menu "${options[@]}"

    }


    upservicetime(){
       # 严格模式放进子 shell：函数返回时不会把 -euo pipefail 泄漏到全局 shell
       (
       set -euo pipefail

        # 临时文件存储服务信息
        temp_file=$(mktemp)

        # 函数：将运行时间字符串转换为总秒数（用于排序）
        convert_to_seconds() {
            local time_str="$1"
            local total_seconds=0

            # 匹配天（d/days）、时（h/hours）、分（min/minutes/m）、秒（s/seconds）
            if [[ $time_str =~ ([0-9]+)\ (d|days) ]]; then
                total_seconds=$(( ${BASH_REMATCH[1]} * 86400 ))  # 1天=86400秒
            fi
            if [[ $time_str =~ ([0-9]+)\ (h|hours) ]]; then
                total_seconds=$(( total_seconds + ${BASH_REMATCH[1]} * 3600 ))  # 1小时=3600秒
            fi
            if [[ $time_str =~ ([0-9]+)\ (min|minutes|m) ]]; then
                total_seconds=$(( total_seconds + ${BASH_REMATCH[1]} * 60 ))  # 1分钟=60秒
            fi
            if [[ $time_str =~ ([0-9]+)\ (s|seconds) ]]; then
                total_seconds=$(( total_seconds + ${BASH_REMATCH[1]} ))  # 秒
            fi

            echo $total_seconds
        }

        # 1. 获取所有运行中的服务（仅service类型，状态为running）
        running_services=$(systemctl list-units --type=service --state=running --no-legend | awk '{print $1}')

        # 2. 遍历每个服务，提取关键信息
        for service in $running_services; do
            # 提取服务运行时间（完整字符串，如"1 days"、"2h 30min"）
            status_output=$(systemctl status "$service" --no-pager)
            # 修正正则：匹配"since ...; "后的完整时间（直到" ago"结束）
            runtime_str=$(echo "$status_output" | grep -oP 'Active: active \(running\) since .*?; \K.*?(?= ago)' | sed 's/  */ /g')  # 合并多余空格

            # 提取服务主进程PID
            main_pid=$(systemctl show -p MainPID "$service" | cut -d= -f2)
            if [[ $main_pid -le 0 || -z $main_pid ]]; then
                continue
            fi

            # 验证PID是否存在
            if ! ps -p "$main_pid" >/dev/null 2>&1; then
                continue
            fi

            # 提取进程名（确保完整，避免被拆分）
            process_name=$(ps -p "$main_pid" -o comm= | tr -s ' ')  # 移除多余空格

            # 转换运行时间为总秒数（用于排序）
            runtime_seconds=$(convert_to_seconds "$runtime_str")

            # 写入临时文件（用分隔符"|"避免字段含空格导致拆分错误）
            echo "$service|$runtime_str|$runtime_seconds|$main_pid|$process_name" >> "$temp_file"
        done

        # 3. 按总秒数升序排序，取前10个，格式化输出
        echo "最新运行的10个服务（按运行时间升序）："
        echo "-----------------------------------------------------------------"
        printf "%-30s %-20s %-20s %-15s\n" "服务名" "运行时间" "进程名" "进程ID"
        echo "-----------------------------------------------------------------"
        # 用"|"分割字段，确保空格不影响列对齐
        sort -n -t'|' -k3 "$temp_file" | head -n 10 | awk -F'|' '{
            printf "%-30s %-20s %-20s %-15s\n", $1, $2, $5, $4
        }'

        # 清理临时文件
        rm -f "$temp_file"
       )
       return $?
    }


    menuname='首页/服务'
    echo "servicefun" >$installdir/config/lastfun
    options=("查看运行中的服务" runningservices "查看全部服务" allservices "启动服务" startservicesel "停止服务" stopservicesel "重启服务" restartservicesel "查看服务详情" servicedetailfun "设为开机自启" serviceenablesel "取消开机自启" servicedisablesel "自定义服务" customservicefun "最新10个启动的服务" upservicetime)

    menu "${options[@]}"

}
