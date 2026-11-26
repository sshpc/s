dockerfun() {

    if [[ -z "${__DC_CMD+x}" ]]; then
        if docker compose version >/dev/null 2>&1; then
            __DC_CMD=(docker compose)
        elif command -v docker-compose >/dev/null 2>&1; then
            __DC_CMD=(docker-compose)
            _yellow "提示：检测到 v1 版 docker-compose（已停止维护），建议升级到 docker compose v2"
        else
            __DC_CMD=()
        fi
    fi

    # 统一调用入口：所有地方都用 dc 代替 docker-compose / docker compose
    dc() {
        if [[ ${#__DC_CMD[@]} -eq 0 ]]; then
            _red "未检测到 docker compose 或 docker-compose"
            return 1
        fi
        "${__DC_CMD[@]}" "$@"
    }

    local _volume_link_dir="${VOLUME_LINK_DIR:-/home/docker/volume}"

    beforeMenu(){
    _blue "> ---  当前目录: [ $(pwd) ] ---- < v:$selfversion"
    echo
    _yellow "当前菜单: $menuname "
    echo
    }

    # 兼容 v1 / v2 的 compose 文件名
    has_compose_file() {
        [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ] \
        || [ -f "compose.yml" ] || [ -f "compose.yaml" ]
    }

    checkcompose() {
        if ! has_compose_file; then
            _red "当前目录没有 compose 文件 (docker-compose.yml / compose.yaml)"
            return 1
        fi
        return 0
    }

    catruncontainer() {
        echo
        local -a containers
        if [[ "$1" == "-all" ]]; then
            _green "当前所有容器："
            mapfile -t containers < <(docker ps -a --format '{{.Names}}\t{{.ID}}\t{{.Status}}')
        elif [[ "$1" == "-stop" ]]; then
            _green "当前已停止的容器："
            mapfile -t containers < <(docker ps -a --filter 'status=exited' --format '{{.Names}}\t{{.ID}}\t{{.Status}}')
        else
            _green "当前正在运行的容器："
            mapfile -t containers < <(docker ps --format '{{.Names}}\t{{.ID}}\t{{.Status}}')
        fi

        echo
        _blue "序号\t容器名称  容器ID         容器状态"

        local i=1 line
        for line in "${containers[@]}"; do
            echo -e "$i\t$line"
            ((i++))
        done
        echo
    }


    catdockervolume() {
        echo
        echo "卷名              路径"
        for volume in $(docker volume ls -q); do
            _blue "$volume  $(docker volume inspect "$volume" --format '{{.Mountpoint}}')"
        done
    }

    catdockerimg() {
        echo
        _blue "镜像列表："
        echo -e "\033[36m序号\t镜像名称\t\t\t镜像ID\t\t大小\t\t状态\033[0m"

        local -a used_images=()
        mapfile -t used_images < <(docker ps --format '{{.Image}}' | sort -u)
        local i=1 name id size used status
        while IFS='|' read -r name id size; do
            status=""
            for used in "${used_images[@]}"; do
                if [[ "$name" == "$used" ]]; then
                    status="（已使用）"
                    break
                fi
            done
            printf "%s\t%-30s\t%-12s\t%-10s\t%s\n" "$i" "$name" "$id" "$size" "$status"
            ((i++))
        done < <(docker images -f "dangling=false" --format "{{.Repository}}:{{.Tag}}|{{.ID}}|{{.Size}}")
    }

    dockerstatusfun() {
        echo
        RUNNING_CONTAINERS=$(docker ps -q | wc -l)
        TOTAL_CONTAINERS=$(docker ps -aq | wc -l)
        NETWORKS=$(docker network ls -q | wc -l)
        VOLUMES=$(docker volume ls -q | wc -l)


        docker -v
        dc version
        echo
        _blue "基本信息"
        echo "运行中/共: ${RUNNING_CONTAINERS}/${TOTAL_CONTAINERS} 网络: ${NETWORKS} | 卷: ${VOLUMES}"

        _blue "docker端口映射"
        if [ "$RUNNING_CONTAINERS" -gt 0 ]; then
            docker ps --format '{{.Names}}\t{{.Ports}}' | while IFS=$'\t' read -r name ports; do
                if [[ "$ports" == *"->"* ]]; then
                    echo "$ports" | tr ',' '\n' | while read -r mapping; do
                        [[ "$mapping" == *"->"* ]] || continue
                        host_port="${mapping%%->*}"
                        host_port="${host_port##*:}"
                        container_port="${mapping##*->}"
                        echo "$name|$host_port|$container_port"
                    done
                fi
            done | sort -u | while IFS='|' read -r name host_port container_port; do
                echo -e "主机端口 $host_port -> 容器端口 $container_port \033[32m [$name] \033[0m   "
            done
        fi
        echo
        _blue "compose情况"
        if has_compose_file; then
            dc ps
        else
            _red "当前目录没有 compose 文件"
        fi
        echo
        _blue "容器情况"
        _green 'runing'
        docker ps
    }

    dockerexec() {
        catruncontainer
        echo
        read -p "请输入容器序号（从 1 开始）： " index

        container_ids=($(docker ps -q))

        if [[ "$index" =~ ^[0-9]+$ ]] && (( index > 0 && index <= ${#container_ids[@]} )); then
            container_id=${container_ids[$((index - 1))]}

            if docker exec "$container_id" /bin/bash -c 'true' >/dev/null 2>&1; then
                docker exec -it "$container_id" /bin/bash
            else
                _yellow "该容器无 /bin/bash，使用 /bin/sh"
                docker exec -it "$container_id" /bin/sh
            fi
        else
            echo "无效的序号，请输入有效的序号。"
        fi
    }


    dockerimagesrm() {

        unused_images=$(docker images -f "dangling=true" -q)
        if [ -n "$unused_images" ]; then
            _blue "将要删除的悬空镜像ID："
            docker images -f "dangling=true"
        else
            _green "没有悬空镜像"
        fi

        _blue "将要删除的未被使用的镜像："
        docker images --filter "dangling=false" --format "{{.Repository}}:{{.Tag}}\t{{.ID}}" | while read -r line; do
            image_id=$(echo "$line" | awk '{print $2}')
            if ! docker ps -a --format '{{.Image}}' | grep -qw "$(echo "$line" | awk '{print $1}')"; then
                echo "$line"
            fi
        done

        read -rp "请输入 y 或 n: " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            _blue "已取消操作"
            return
        fi

        if [ -n "$unused_images" ]; then
            docker rmi $unused_images && _green "已删除所有悬空镜像"
        fi

        _blue "正在删除所有未被使用的镜像..."
        docker image prune -a -f
        loading $!
        wait
        _green "已清理所有未被使用的镜像"
    }

    dockersysrm(){
        _red "警告：将删除所有停止的容器、未被使用的网络/镜像/构建缓存及数据卷（不可逆）"
        waitinput
        docker system prune -af --volumes
        _blue '清理完成'
    }

    composestart() {
        checkcompose || return
        dc start
    }

    composestop() {
        checkcompose || return
        dc stop
    }

    restartcontainer() {

        catruncontainer

        read -p "请输入要重启的容器序号（从 1 开始）： " index

        container_ids=($(docker ps -q))

        if [[ "$index" =~ ^[0-9]+$ ]] && (( index > 0 && index <= ${#container_ids[@]} )); then
            container_id=${container_ids[$((index - 1))]}

            _blue "正在重启容器：$index"
            docker restart "$container_id" &
            loading $!
            wait
            _green "已重启"
        else
            echo "无效的序号，请输入有效的序号。"
        fi
    }

    restartallcontainer(){
        catruncontainer
        _blue "正在重启全部容器"
        docker restart $(docker ps -q) &
        loading $!
        wait
        _green "已重启"
    }

    startcontainer() {

        catruncontainer -stop

        read -p "请输入要启动的容器序号（从 1 开始）： " index

        container_ids=($(docker ps -a -q -f status=exited))

        if [[ "$index" =~ ^[0-9]+$ ]] && (( index > 0 && index <= ${#container_ids[@]} )); then
            container_id=${container_ids[$((index - 1))]}

            _blue "正在启动容器：$index"
            docker start "$container_id" &
            loading $!
            wait
            _green "已启动"
        else
            echo "无效的序号，请输入有效的序号。"
        fi
    }

    stopcontainer() {

        catruncontainer

        read -p "请输入要停止的容器序号（从 1 开始）： " index

        container_ids=($(docker ps -q))

        if [[ "$index" =~ ^[0-9]+$ ]] && (( index > 0 && index <= ${#container_ids[@]} )); then
            container_id=${container_ids[$((index - 1))]}

            _blue "正在停止容器：$index"
            docker stop "$container_id" &
            loading $!
            wait
            _green "已停止"
        else
            echo "无效的序号，请输入有效的序号。"
        fi
    }

    killcontainer(){
        catruncontainer
        _red "注意！这将会使用 docker kill container"

        read -p "请输入要强行停止的容器序号（从 1 开始）： " index

        container_ids=($(docker ps -q))

        if [[ "$index" =~ ^[0-9]+$ ]] && (( index > 0 && index <= ${#container_ids[@]} )); then
            container_id=${container_ids[$((index - 1))]}

            _blue "正在停止容器：$index"
            docker kill "$container_id" &
            loading $!
            wait
            _green "已停止"
        else
            echo "无效的序号，请输入有效的序号。"
        fi
    }

    catcomposelogs() {
        checkcompose || return
        dc logs
    }

    composeinstall() {
            checkcompose || return
            dc up -d "$@" || { _red "compose 启动失败"; return 1; }

            _blue "创建命名卷软连接 $_volume_link_dir（仅本项目使用的卷）"
            mkdir -p "$_volume_link_dir"

            local -a project_vols=()
            mapfile -t project_vols < <(
                for cid in $(dc ps -q); do
                    docker inspect "$cid" --format '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}{{"\n"}}{{end}}{{end}}' 2>/dev/null
                done | sort -u
            )

            local volume mountpoint
            for volume in "${project_vols[@]}"; do
                [[ -z "$volume" ]] && continue
                mountpoint=$(docker volume inspect "$volume" --format '{{.Mountpoint}}' 2>/dev/null)
                [[ -z "$mountpoint" ]] && continue
                if [ ! -e "$_volume_link_dir/$volume" ] && [ ! -L "$_volume_link_dir/$volume" ]; then
                    ln -s "$mountpoint" "$_volume_link_dir/$volume" >/dev/null 2>&1 \
                        && _green "已创建软链: $_volume_link_dir/$volume -> $mountpoint"
                fi
            done
        }

        composedown() {
            checkcompose || return
            dc down
        }

        composeinstallbuild() {
            composeinstall '--build'
        }



        dockervolumerm_one() {
            catdockervolume
            echo
            read -p "请输入要删除的数据卷名称: " volume
            if docker volume ls -q | grep -wq "$volume"; then
            docker volume rm "$volume" && _green "已删除数据卷 $volume"
            rm -rf "$_volume_link_dir/$volume"
            else
            _red "未找到数据卷 $volume"
            fi
        }

        dockervolumerm_unused() {
            _red "确定删除所有未使用的数据卷吗?"
            waitinput
            _red "正在删除未使用的数据卷并移除软链接"
            for volume in $(docker volume ls -qf "dangling=true"); do
            docker volume rm "$volume"
            rm -rf "$_volume_link_dir/$volume"
            done
            _green "未使用的数据卷已删除"
        }

        dockervolumerm_all() {
            catdockervolume
            echo
            _red '确定全部删除吗?'
            waitinput
            _red "删除并移除软链接"
            for volume in $(docker volume ls -q); do
            docker volume rm "$volume"
            rm -rf "$_volume_link_dir/$volume"
            done
            _green "所有数据卷已删除"
        }



    catnetworkfun() {
        echo
        printf "%-20s %-10s %-10s %-10s %-20s %-15s %-18s\n" \
            "网络ID" "内部网络" "Driver" "Scope" "网络名称" "Gateway" "IPv4Address"

        local -a net_ids=()
        mapfile -t net_ids < <(docker network ls -q)
        local network name scope driver gateway ipv4 internal
        for network in "${net_ids[@]}"; do
            IFS=$'\t' read -r name scope driver gateway ipv4 internal < <(
                docker network inspect "$network" 2>/dev/null | jq -r \
                    '.[0] | [.Name, .Scope, .Driver,
                             (.IPAM.Config[0].Gateway // ""),
                             (.IPAM.Config[0].Subnet // ""),
                             (if .Internal then "是" else "否" end)] | @tsv'
            )
            [[ -z "$name" ]] && continue
            printf "%-18s %-10s %-8s %-10s %-20s %-15s %-18s\n" \
                "$network" "$internal" "$driver" "$scope" "$name" "$gateway" "$ipv4"
        done

        echo "总网络数: ${#net_ids[@]}"
        echo

    }

    catcontainerlogs(){
        catruncontainer

        read -p "请输入容器序号（从 1 开始）： " index

        container_ids=($(docker ps -q))

        if [[ "$index" =~ ^[0-9]+$ ]] && (( index > 0 && index <= ${#container_ids[@]} )); then
            container_id=${container_ids[$((index - 1))]}

            _blue "容器：$index"
            docker logs --tail 50 "$container_id"

        else
            echo "无效的序号，请输入有效的序号。"
        fi
    }

    catrealtimecontainerlogs(){
        catruncontainer

        read -p "请输入容器序号（从 1 开始）： " index

        container_ids=($(docker ps -q))

        if [[ "$index" =~ ^[0-9]+$ ]] && (( index > 0 && index <= ${#container_ids[@]} )); then
            container_id=${container_ids[$((index - 1))]}

            _blue "容器：$index"
            docker logs --tail 10 --follow "$container_id"

        else
            echo "无效的序号，请输入有效的序号。"
        fi
    }

    dockerimageimportexport() {

        local _img_dir="${IMG_EXPORT_DIR:-/home/img}"
        if [ ! -d "$_img_dir" ]; then
            mkdir -p "$_img_dir"
        fi

        dockerimageexportone() {
            catdockerimg

            echo
            read -p "请输入要导出的镜像序号（从 1 开始）: " index

            mapfile -t images < <(docker images -f "dangling=false" --format "{{.Repository}}:{{.Tag}}")


            if [[ "$index" =~ ^[0-9]+$ ]] && (( index > 0 && index <= ${#images[@]} )); then
            image_name="${images[$((index - 1))]}"
            filename="$_img_dir/${image_name//[:\/]/_}.tar"
            _blue "导出镜像 $image_name 为 $filename"
            docker save -o "$filename" "$image_name" &
            loading $!
            wait
            _green "导出成功：$filename"
            else
            _red "无效的序号"
            fi
        }

        dockerimageexportuseall(){
            _blue "正在导出正在使用的镜像到 $_img_dir 目录..."
            local -a used_images=()
            mapfile -t used_images < <(docker ps --format '{{.Image}}' | sort -u | grep -v '^<none>:<none>$')
            if [ ${#used_images[@]} -eq 0 ]; then
                _red "当前没有正在使用的镜像"
                return
            fi
            local -a pids=()
            for image in "${used_images[@]}"; do
                filename="$_img_dir/${image//[:\/]/_}.tar"
                _blue "导出镜像 $image -> $filename"
                docker save -o "$filename" "$image" &
                pids+=($!)
            done
            loadingprogressbar "${pids[@]}"
            wait
            _green "导出成功"
            ls "$_img_dir"
        }


        dockerimageexportall() {
            _blue "开始批量导出镜像到 $_img_dir 目录..."
            local -a pids=()
            while IFS= read -r image; do
                [[ -z "$image" || "$image" == "<none>:<none>" ]] && continue
                filename="$_img_dir/${image//[:\/]/_}.tar"
                _blue "导出镜像 $image -> $filename"
                docker save -o "$filename" "$image" &
                pids+=($!)
            done < <(docker images -f "dangling=false" --format "{{.Repository}}:{{.Tag}}")
            if [ ${#pids[@]} -eq 0 ]; then
                _yellow "没有可导出的镜像"
                return
            fi
            loadingprogressbar "${pids[@]}"
            wait
            _green "导出成功"
            ls "$_img_dir"
        }

        dockerimageimportall() {
            if [ ! -d "$_img_dir" ]; then
                _red "当前目录下没有镜像目录 $_img_dir"
                return
            fi

            _blue "开始导入 $_img_dir 目录中的镜像文件..."
            for file in "$_img_dir"/*.tar; do
                [ -e "$file" ] || { _red "没有找到任何 .tar 镜像文件"; return; }
                image_name=$(tar -tf "$file" | grep manifest.json | xargs -I{} tar -xOf "$file" {} | jq -r '.[0].RepoTags[0] // empty')
                if [ -n "$image_name" ] && docker images | grep -q "$image_name"; then
                    _red "已存在同名镜像 $image_name"
                    echo "请选择操作：1 覆盖（删除旧镜像） 2 跳过 3 共存（导入后会有同名不同ID）"
                    read -p "输入选项（1/2/3）: " choice
                    case "$choice" in
                        1)
                            docker rmi "$image_name"
                            _blue "已删除旧镜像，准备导入..."
                            docker load -i "$file" && _green "导入成功" || _red "导入失败"
                            ;;
                        2)
                            _blue "已跳过 $image_name"
                            ;;
                        3)
                            _blue "共存模式，导入后会有同名不同ID镜像"
                            docker load -i "$file" && _green "导入成功" || _red "导入失败"
                            ;;
                        *)
                            _red "无效选项，已跳过 $image_name"
                            ;;
                    esac
                else
                    _blue "导入镜像文件: $file"
                    docker load -i "$file" && _green "导入成功" || _red "导入失败"
                fi
            done
        }

        menuname='首页/docker/镜像导入导出'
        options=("单个导出" dockerimageexportone "批量导出已使用的镜像" dockerimageexportuseall  "批量导出全部镜像" dockerimageexportall "批量导入" dockerimageimportall)
        menu "${options[@]}"
    }

    dockerstatusadvancedfun(){
        echo
        _blue '容器监控'
        docker stats --no-stream

        echo
        _blue "Docker情况"
        if command -v snap &> /dev/null && ( snap list | grep -q "docker" ) >/dev/null 2>&1; then
            echo "检测到 Docker 通过 snap 安装"
            SNAP_DAEMON_CONFIG="var/snap/docker/current/config/daemon.json"

            if [ -f "$SNAP_DAEMON_CONFIG" ]; then
                echo "snap Docker 配置文件: $SNAP_DAEMON_CONFIG"
            else
                echo "snap Docker 配置文件不存在: $SNAP_DAEMON_CONFIG"
            fi
        else
            echo "检测到 Docker 通过常规方式安装"
        fi

        DEFAULT_CONFIG="/etc/docker/daemon.json"
        if [ -f "$DEFAULT_CONFIG" ]; then
            echo "配置文件: $DEFAULT_CONFIG"
        else
            echo "系统默认 Docker 配置文件不存在: $DEFAULT_CONFIG"
        fi
        echo "当前生效的镜像代理配置:"
        docker info 2>/dev/null | grep -A1 -i "registry mirrors" || echo "未配置镜像代理"


    }

    dockervolumerm() {
        menuname='首页/docker/删除数据卷'
        options=("删除单个数据卷" dockervolumerm_one "删除所有未使用的数据卷" dockervolumerm_unused "删除所有数据卷" dockervolumerm_all)
        menu "${options[@]}"
    }


    catcomposepath() {
        echo
        _blue "查询容器对应的 docker-compose 文件位置"
        echo

        local containers_arr=()
        while read -r line; do
            containers_arr+=("$line")
        done < <(docker ps -a --format '{{.Names}}' 2>/dev/null)

        if [[ ${#containers_arr[@]} -eq 0 ]]; then
            _yellow "没有容器"
            return
        fi

        printf "%-30s %-60s\n" "容器名称" "compose文件路径"
        printf "%-30s %-60s\n" "------------------------------" "------------------------------------------------------------"

        local unique_paths=()
        for name in "${containers_arr[@]}"; do
            [[ -z "$name" ]] && continue
            local config_files
            config_files=$(docker inspect "$name" --format '{{index .Config.Labels "com.docker.compose.project.config_files"}}' 2>/dev/null)
            local working_dir
            working_dir=$(docker inspect "$name" --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' 2>/dev/null)

            local resolved=""
            if [[ -n "$config_files" ]]; then
                local IFS=','
                for f in $config_files; do
                    f=$(echo "$f" | xargs)
                    [[ -z "$f" ]] && continue
                    if [[ "$f" != /* && -n "$working_dir" ]]; then
                        f="$working_dir/$f"
                    fi
                    [[ -n "$resolved" ]] && resolved="$resolved,$f"
                    [[ -z "$resolved" ]] && resolved="$f"
                done
                printf "%-30s %s\n" "$name" "$resolved"
                IFS=','
                for f in $resolved; do
                    unique_paths+=("$(echo "$f" | xargs)")
                done
            elif [[ -n "$working_dir" ]]; then
                printf "%-30s %s/ (无config_files标签)\n" "$name" "$working_dir"
            else
                printf "%-30s %s\n" "$name" "(非compose创建)"
            fi
        done

        echo
    }

    catcomposepath_one() {
        echo
        _blue "查询单个容器的 compose 文件位置"
        echo

        local containers_arr=()
        while read -r line; do
            containers_arr+=("$line")
        done < <(docker ps -a --format '{{.Names}}' 2>/dev/null)

        if [[ ${#containers_arr[@]} -eq 0 ]]; then
            _yellow "没有容器"
            return
        fi

        for i in "${!containers_arr[@]}"; do
            printf "  %d) %s\n" "$((i+1))" "${containers_arr[$i]}"
        done
        echo

        read -ep "请输入容器序号 [1-${#containers_arr[@]}], 回车取消: " choice
        [[ -z "$choice" ]] && { _yellow "已取消"; return; }

        if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#containers_arr[@]} )); then
            _red "无效序号"
            return
        fi

        local name="${containers_arr[$((choice-1))]}"
        local config_files
        config_files=$(docker inspect "$name" --format '{{index .Config.Labels "com.docker.compose.project.config_files"}}' 2>/dev/null)
        local working_dir
        working_dir=$(docker inspect "$name" --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' 2>/dev/null)
        local project
        project=$(docker inspect "$name" --format '{{index .Config.Labels "com.docker.compose.project"}}' 2>/dev/null)

        echo
        _blue "容器: $name"
        [[ -n "$project" ]] && echo "  compose项目: $project"
        [[ -n "$working_dir" ]] && echo "  工作目录:    $working_dir"
        if [[ -n "$config_files" ]]; then
            local resolved=""
            local IFS=','
            for f in $config_files; do
                f=$(echo "$f" | xargs)
                [[ -z "$f" ]] && continue
                if [[ "$f" != /* && -n "$working_dir" ]]; then
                    f="$working_dir/$f"
                fi
                [[ -n "$resolved" ]] && resolved="$resolved, $f"
                [[ -z "$resolved" ]] && resolved="$f"
            done
            echo "  compose文件:  $resolved"
        else
            _yellow "  该容器不是通过 compose 创建的"
        fi

        if [[ -n "$working_dir" ]]; then
            read -ep "是否进入该目录? (y/n, 默认n): " go
            if [[ "$go" == "y" ]]; then
                _green "进入 $working_dir (exit退回脚本)"
                cd "$working_dir" && bash
            fi
        fi
    }

    findcomposefun() {
        menuname='首页/docker/查找compose'
        options=("查询compose文件(全部)" catcomposepath "查询compose文件(单个)" catcomposepath_one)
        menu "${options[@]}"
    }

    # 其他
    othercommands() {

        menuname='首页/docker/其他'
        options=("查看状态(高级)" dockerstatusadvancedfun "查看docker网络" catnetworkfun "最新容器日志50条" catcontainerlogs "启动容器" startcontainer "停止容器" stopcontainer "强制停止容器" killcontainer "批量启动容器composes" composestart "批量停止容器composes" composestop "重启全部容器" restartallcontainer "查看数据卷" catdockervolume "删除命名卷" dockervolumerm "查看docker镜像" catdockerimg "删除无用镜像" dockerimagesrm "Docker清理" dockersysrm  "镜像导入导出" dockerimageimportexport "实时容器日志" catrealtimecontainerlogs)

        menu "${options[@]}"
    }


    menuname='首页/docker'
    echo "dockerfun" >$installdir/config/lastfun
    options=("查看状态" dockerstatusfun "重启容器" restartcontainer "安装" composeinstall  "安装(强制构建)" composeinstallbuild "终止" composedown "exec进入容器" dockerexec    "查看compose日志" catcomposelogs "其他" othercommands "查找compose" findcomposefun  )

    menu "${options[@]}"

}
