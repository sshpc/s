dockerfun() {

    checkcompose() {
        # 检查当前目录是否存在 docker-compose.yml 文件
        if [ ! -f "docker-compose.yml" ]; then
            _red "当前目录没有 docker-compose.yml 文件"
            exit
        fi
    }

    catruncontainer() {
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

    catdockervolume() {
        echo
        echo "卷名              路径"
        for volume in $(docker volume ls -q); do
            _blue "$volume  $(docker volume inspect "$volume" --format '{{.Mountpoint}}')"
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
    dockerimagesfun() {
        docker images
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

    catcomposelogs() {
        checkcompose
        docker-compose logs
    }

    #维护
    maintenancefun() {

        composeinstall() {
            checkcompose
            docker-compose up -d $1

            if [ $? -eq 0 ]; then
                _blue '创建命名卷软连接 /home/docker/volume'

                # 获取目录
                #current_dir=$(pwd)
                mkdir -p /home/docker/volume
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
        
        dockervolumerm() {
            catdockervolume
            echo
            _red '确定全部删除吗?'
            waitinput
            _red "删除并移除软链接"
            for volume in $(docker volume ls -q); do
                docker volume rm $volume
                rm -r $volume
            done
        }

        menuname='首页/docker/维护'
        options=("安装" composeinstall "终止" composedown "安装-build(强制构建)" composeinstallbuild "删除所有命名卷" dockervolumerm)

        menu "${options[@]}"
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

    menuname='首页/docker'
    echo "dockerfun" >$installdir/config/lastfun
    options=("查看状态" dockerstatusfun "exec进入容器" dockerexec "启动容器" composestart "停止容器" composestop "重启容器" restartcontainer "查看数据卷" catdockervolume "查看日志" catcomposelogs "make&build安装&维护" maintenancefun "查看docker镜像" dockerimagesfun "查看docker网络" catnetworkfun)

    menu "${options[@]}"

}
