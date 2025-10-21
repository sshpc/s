dockerfun() {
    beforeMenu(){
    _blue "> ---  当前目录: [ $(pwd) ] ---- < v:${branch}-$selfversion"
    echo
    _yellow "当前菜单: $menuname "
    echo
    }

    checkcompose() {
        # 检查当前目录是否存在 docker-compose.yml 文件
        if [ ! -f "docker-compose.yml" ]; then
            _red "当前目录没有 docker-compose.yml 文件"
            exit
        fi
    }

    catruncontainerbak() {
        echo
        # 获取所有正在运行的容器
        containers=$(docker ps --format 'table {{.Names}}\t{{.ID}}\t{{.Status}}')

        # 打印容器列表并添加序号
        _green "当前正在运行的容器："
        echo
        _blue "序号\t容器名称  容器ID         容器状态"
        i=1
        while read -r line; do
            if [[ $line != "NAMES"* ]]; then # 跳过标题行
                echo -e "$i\t$line"
                ((i++))
            fi
        done <<<"$containers"
        echo
    }

    catruncontainer() {
        echo
        local cmd="docker ps --format 'table {{.Names}}\t{{.ID}}\t{{.Status}}'"

        # 参数判断
        if [[ "$1" == "-all" ]]; then
            cmd="docker ps -a --format 'table {{.Names}}\t{{.ID}}\t{{.Status}}'"
        elif [[ "$1" == "-stop" ]]; then
            cmd="docker ps -a --filter 'status=exited' --format 'table {{.Names}}\t{{.ID}}\t{{.Status}}'"
        fi

        containers=$(eval "$cmd")

        # 打印容器列表并添加序号
        if [[ "$1" == "-stop" ]]; then
            _green "当前已停止的容器："
        elif [[ "$1" == "-all" ]]; then
            _green "当前所有容器："
        else
            _green "当前正在运行的容器："
        fi

        echo
        _blue "序号\t容器名称  容器ID         容器状态"

        i=1
        while read -r line; do
            if [[ $line != "NAMES"* ]]; then # 跳过标题行
                echo -e "$i\t$line"
                ((i++))
            fi
        done <<<"$containers"
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

        images=()
        i=1
        # 获取正在使用的镜像列表
        used_images=($(docker ps --format '{{.Image}}' | sort | uniq))
        docker images --format "{{.Repository}}:{{.Tag}}|{{.ID}}|{{.Size}}" | while IFS='|' read -r name id size; do
            images+=("$name")
            status=""
            for used in "${used_images[@]}"; do
                if [[ "$name" == "$used" ]]; then
                status="（已使用）"
                break
                fi
            done
            printf "%s\t%-30s\t%-12s\t%-10s\t%s\n" "$i" "$name" "$id" "$size" "$status"
            ((i++))
        done
    }

    dockerstatusfun() {
        echo
        # 统计信息
        RUNNING_CONTAINERS=$(docker ps -q | wc -l)
        TOTAL_CONTAINERS=$(docker ps -aq | wc -l)
        NETWORKS=$(docker network ls -q | wc -l)
        VOLUMES=$(docker volume ls -q | wc -l)
        
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
        if [ ! -f "docker-compose.yml" ]; then
            _red "当前目录没有 docker-compose.yml 文件"
        else
            docker-compose ps
        fi
        echo
        _blue "容器情况"
        _green 'runing'
        docker ps
        _blue 'all'
        docker ps -a
        

    }

    dockerexec() {
        catruncontainer
        echo
        read -p "请输入容器序号（从 1 开始）： " index

        # 获取容器的 ID 列表
        container_ids=($(docker ps -q))

        # 检查输入的序号是否有效
        if [[ "$index" -gt 0 && "$index" -le "${#container_ids[@]}" ]]; then
            container_id=${container_ids[$((index - 1))]}

            docker exec -it "$container_id" /bin/bash
        else
            echo "无效的序号，请输入有效的序号。"
        fi
        nextrun

    }
    

    dockerimagesrm() {
        
        # 列出将要删除的悬空镜像
        unused_images=$(docker images -f "dangling=true" -q)
        if [ -n "$unused_images" ]; then
            _blue "将要删除的悬空镜像ID："
            docker images -f "dangling=true"
        else
            _green "没有悬空镜像"
        fi

        # 列出将要删除的未被使用的镜像
        _blue "将要删除的未被使用的镜像："
        docker images --filter "dangling=false" --format "{{.Repository}}:{{.Tag}}\t{{.ID}}" | while read -r line; do
            image_id=$(echo "$line" | awk '{print $2}')
            # 检查是否被容器使用
            if ! docker ps -a --format '{{.Image}}' | grep -qw "$(echo "$line" | awk '{print $1}')"; then
                echo "$line"
            fi
        done

        read -p "请输入 y 或 n: " confirm
        if [[ "$confirm" != "y" ]]; then
            _blue "已取消操作"
            return
        fi

        if [ -n "$unused_images" ]; then
            docker rmi $unused_images && _green "已删除所有悬空镜像"
        fi

        # 删除所有未被使用的镜像
        _blue "正在删除所有未被使用的镜像..."
        docker image prune -a -f
        loading $!
        wait
        _green "已清理所有未被使用的镜像"

        nextrun
    }

    composestart() {
        checkcompose
        docker-compose start
    }

    composestop() {
        checkcompose
        docker-compose stop
    }

    restartcontainer() {

        catruncontainer

        # 提示用户输入要重启的容器序号
        read -p "请输入要重启的容器序号（从 1 开始）： " index

        # 获取容器的 ID 列表
        container_ids=($(docker ps -q))

        # 检查输入的序号是否有效
        if [[ "$index" -gt 0 && "$index" -le "${#container_ids[@]}" ]]; then
            container_id=${container_ids[$((index - 1))]}

            # 重启容器
            _blue "正在重启容器：$index"
            docker restart "$container_id" &
            loading $!
            wait
            _green "已重启"
        else
            echo "无效的序号，请输入有效的序号。"
        fi
    }

    startcontainer() {

        catruncontainer -stop

        # 提示用户输入要启动的容器序号
        read -p "请输入要启动的容器序号（从 1 开始）： " index

        # 获取已停止容器的 ID 列表
        container_ids=($(docker ps -a -q -f status=exited))

        # 检查输入的序号是否有效
        if [[ "$index" -gt 0 && "$index" -le "${#container_ids[@]}" ]]; then
            container_id=${container_ids[$((index - 1))]}

            # 启动容器
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

        # 提示用户输入要停止的容器序号
        read -p "请输入要停止的容器序号（从 1 开始）： " index

        # 获取容器的 ID 列表
        container_ids=($(docker ps -q))

        # 检查输入的序号是否有效
        if [[ "$index" -gt 0 && "$index" -le "${#container_ids[@]}" ]]; then
            container_id=${container_ids[$((index - 1))]}

            # 停止容器
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

        # 提示用户输入要停止的容器序号
        read -p "请输入要强行停止的容器序号（从 1 开始）： " index

        # 获取容器的 ID 列表
        container_ids=($(docker ps -q))

        # 检查输入的序号是否有效
        if [[ "$index" -gt 0 && "$index" -le "${#container_ids[@]}" ]]; then
            container_id=${container_ids[$((index - 1))]}

            # 停止容器
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
        checkcompose
        docker-compose logs
    }

    composeinstall() {
            checkcompose
            docker-compose up -d $1

            if [ $? -eq 0 ]; then
                _blue '创建命名卷软连接 /home/docker/volume'

                # 获取目录
                #current_dir=$(pwd)
                if [ ! -d "/home/docker/volume" ]; then
                    mkdir -p /home/docker/volume
                fi
                current_dir=/home/docker/volume
                # 列出所有卷并遍历
                for volume in $(docker volume ls -q); do
                    mountpoint=$(docker volume inspect "$volume" --format '{{.Mountpoint}}')
                    if [ ! -L "$current_dir/$volume" ]; then
                        ln -s "$mountpoint" "$current_dir/$volume" >/dev/null 2>&1
                        _green "Created symlink for volume '$volume' at '$current_dir/$volume' -> '$mountpoint'"
                    fi
                done
            fi

        }

        composedown() {
            checkcompose
            docker-compose down
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
            rm -rf "/home/docker/volume/$volume"
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
            rm -rf "/home/docker/volume/$volume"
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
            rm -rf "/home/docker/volume/$volume"
            done
            _green "所有数据卷已删除"
        }

    

    catnetworkfun() {
        echo
        # 获取所有 Docker 网络
        # 表头（字段宽度可根据实际微调）
        printf "%-20s %-10s %-10s %-10s %-20s %-15s %-18s\n" "网络ID" "类别" "Driver" "Scope" "网络名称" "Gateway" "IPv4Address"

        for network in $(docker network ls -q); do
            info=$(docker network inspect "$network")
            name=$(echo "$info" | jq -r '.[0].Name')
            scope=$(echo "$info" | jq -r '.[0].Scope')
            driver=$(echo "$info" | jq -r '.[0].Driver')
            gateway=$(echo "$info" | jq -r '.[0].IPAM.Config[0].Gateway // ""')
            ipv4=$(echo "$info" | jq -r '.[0].IPAM.Config[0].Subnet // ""')
            internal=$(echo "$info" | jq -r '.[0].Internal')
            [[ "$internal" == "true" ]] && type="internal" || type="external"

            # 数据行
            printf "%-18s %-10s %-8s %-10s %-20s %-15s %-18s\n" \
                "$network" "$type" "$driver" "$scope" "$name" "$gateway" "$ipv4"
        done

        # 统计信息
        total_networks=$(docker network ls -q | wc -l)
        echo "总网络数: $total_networks"
        echo

    }

    catcontainerlogs(){
        catruncontainer

        # 提示用户输入要停止的容器序号
        read -p "请输入容器序号（从 1 开始）： " index

        # 获取容器的 ID 列表
        container_ids=($(docker ps -q))

        # 检查输入的序号是否有效
        if [[ "$index" -gt 0 && "$index" -le "${#container_ids[@]}" ]]; then
            container_id=${container_ids[$((index - 1))]}

            _blue "容器：$index"
            docker logs "$container_id"
            
        else
            echo "无效的序号，请输入有效的序号。"
        fi
    }

    dockerimageimportexport() {

        if [ ! -d "/home/img" ]; then
            mkdir -p /home/img
        fi

        dockerimageexportone() {
            catdockerimg

            echo
            read -p "请输入要导出的镜像序号（从 1 开始）: " index

            # 重新获取镜像名列表（因为 while 中的 images 变量是 subshell）
            mapfile -t images < <(docker images --format "{{.Repository}}:{{.Tag}}")


            if [[ "$index" -gt 0 && "$index" -le "${#images[@]}" ]]; then
            image_name="${images[$((index - 1))]}"
            filename="/home/img/${image_name//[:\/]/_}.tar"
            _blue "导出镜像 $image_name 为 $filename"
            docker save -o "$filename" "$image_name" &
            loading $!
            wait
            _green "导出成功：$filename"
            else
            _red "无效的序号"
            fi
            nextrun
        }

        dockerimageexportuseall(){
            _blue "正在导出正在使用的镜像到 /home/img 目录..."
            used_images=($(docker ps --format '{{.Image}}' | sort | uniq))
            if [ ${#used_images[@]} -eq 0 ]; then
                _red "当前没有正在使用的镜像"
                nextrun
            fi
            for image in "${used_images[@]}"; do
                filename="/home/img/${image//[:\/]/_}.tar"
                _blue "导出镜像 $image -> $filename"
                docker save -o "$filename" "$image" &
                pids+=($!)
            done
            loadingprogressbar "${pids[@]}"
            wait
            _green "导出成功"
            ls /home/img
            nextrun
        }


        dockerimageexportall() {
            _blue "开始批量导出镜像到 /home/img 目录..."
            for image in $(docker images --format "{{.Repository}}:{{.Tag}}"); do
                filename="/home/img/${image//[:\/]/_}.tar"
                _blue "导出镜像 $image -> $filename"
                docker save -o "$filename" "$image" &
                pids+=($!)          # 收集子进程 PID
            done
            loadingprogressbar "${pids[@]}" # 显示加载动画
            wait                 # 等待所有子进程完成
            _green "导出成功"
            ls /home/img
            nextrun
        }

        dockerimageimportall() {
            if [ ! -d "/home/img" ]; then
                _red "当前目录下没有 img 文件夹"
                return
            fi

            _blue "开始导入 /home/img 目录中的镜像文件..."
            for file in /home/img/*.tar; do
                [ -e "$file" ] || { _red "没有找到任何 .tar 镜像文件"; return; }
                # 获取镜像名
                image_name=$(tar -tf "$file" | grep manifest.json | xargs -I{} tar -xOf "$file" {} | jq -r '.[0].RepoTags[0]')
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
            nextrun
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
        # 检查 Docker 是否通过 snap 安装
        if command -v snap &> /dev/null && ( snap list | grep -q "docker" ) >/dev/null 2>&1; then
            echo "检测到 Docker 通过 snap 安装"
            SNAP_DAEMON_CONFIG="var/snap/docker/current/config/daemon.json"
            
            # 检查 snap 配置文件
            if [ -f "$SNAP_DAEMON_CONFIG" ]; then
                echo "snap Docker 配置文件: $SNAP_DAEMON_CONFIG"
            else
                echo "snap Docker 配置文件不存在: $SNAP_DAEMON_CONFIG"
            fi
        else
            echo "检测到 Docker 通过常规方式安装"
        fi

        # 检查系统默认配置文件
        DEFAULT_CONFIG="/etc/docker/daemon.json"
        if [ -f "$DEFAULT_CONFIG" ]; then
            echo "配置文件: $DEFAULT_CONFIG"
        else
            echo "系统默认 Docker 配置文件不存在: $DEFAULT_CONFIG"
        fi
        # 检查当前生效的镜像代理
        echo "当前生效的镜像代理配置:"
        docker info 2>/dev/null | grep -A1 -i "registry mirrors" || echo "未配置镜像代理"


    }

    dockervolumerm() {
        menuname='首页/docker/删除数据卷'
        options=("删除单个数据卷" dockervolumerm_one "删除所有未使用的数据卷" dockervolumerm_unused "删除所有数据卷" dockervolumerm_all)
        menu "${options[@]}"
    }


    #其他
    othercommands() {

        menuname='首页/docker/其他'
        options=("查看状态(高级)" dockerstatusadvancedfun "查看docker网络" catnetworkfun "查看容器日志" catcontainerlogs "启动容器" startcontainer "停止容器" stopcontainer "强制停止容器" killcontainer "批量启动容器" composestart "批量停止容器" composestop "查看数据卷" catdockervolume "删除命名卷" dockervolumerm "查看docker镜像" catdockerimg "删除无用镜像" dockerimagesrm  "镜像导入导出" dockerimageimportexport )

        menu "${options[@]}"
    }


    menuname='首页/docker'
    echo "dockerfun" >$installdir/config/lastfun
    options=("查看状态" dockerstatusfun "重启容器" restartcontainer "安装" composeinstall  "安装(强制构建)" composeinstallbuild "终止" composedown "exec进入容器" dockerexec    "查看compose日志" catcomposelogs "其他" othercommands )

    menu "${options[@]}"

}
