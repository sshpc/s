dockerfun() {

    dockerexec() {
        # 获取所有正在运行的容器
        containers=$(docker ps --format 'table {{.ID}}\t{{.Names}}')

        # 打印容器列表并添加序号
        echo
        _blue "当前正在运行的容器："
        echo "序号   容器ID         容器名称"
        i=1
        while read -r line; do
            if [[ $line != "CONTAINER ID"* ]]; then # 跳过标题行
                echo -e "$i\t$line"
                ((i++))
            fi
        done <<<"$containers"
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
        docker-compose up -d

    }

    composestart() {
        docker-compose start

    }

    composestop() {
        docker-compose stop
    }

    composeps() {
        echo
        echo "compose情况"
        echo
        docker-compose ps
        echo
        echo "容器情况"
        echo
        _green 'runing'
        docker ps
        _blue 'all'
        docker ps -a
    }

    catdockervolume() {
        echo
        echo "卷名              路径"
        for volume in $(docker volume ls -q); do
            _blue "$volume  $(docker volume inspect "$volume" --format '{{.Mountpoint}}')"
        done
    }

    restartcontainer() {

        # 获取所有正在运行的容器
        containers=$(docker ps --format 'table {{.ID}}\t{{.Names}}')

        # 打印容器列表并添加序号
        echo "当前正在运行的容器："
        echo "序号   容器ID         容器名称"
        i=1
        while read -r line; do
            if [[ $line != "CONTAINER ID"* ]]; then # 跳过标题行
                echo -e "$i\t$line"
                ((i++))
            fi
        done <<<"$containers"

        # 提示用户输入要重启的容器序号
        read -p "请输入要重启的容器序号（从 1 开始）： " index

        # 获取容器的 ID 列表
        container_ids=($(docker ps -q))

        # 检查输入的序号是否有效
        if [[ "$index" -gt 0 && "$index" -le "${#container_ids[@]}" ]]; then
            container_id=${container_ids[$((index - 1))]}

            # 重启容器
            _blue "正在重启容器：$index"
            docker restart "$container_id"
            _green "已重启"
        else
            echo "无效的序号，请输入有效的序号。"
        fi
    }

    catcomposelogs() {
        docker-compose logs
    }

    #维护
    maintenancefun() {

        composeinstall() {
            docker-compose up -d --build

            if [ $? -eq 0 ]; then
                _blue '创建命名卷软连接 /home/docker/volume'

                # 获取目录
                #current_dir=$(pwd)
                mkdir -p /home/docker/volume
                current_dir=/home/docker/volume
                # 列出所有卷并遍历
                for volume in $(docker volume ls -q); do
                    # 获取卷的真实路径
                    mountpoint=$(docker volume inspect "$volume" --format '{{.Mountpoint}}')

                    # 在当前目录创建指向真实路径的符号链接
                    ln -s "$mountpoint" "$current_dir/$volume"

                    _green "Created symlink for volume '$volume' at '$current_dir/$volume' -> '$mountpoint'"
                done
            fi

        }

        composedown() {
            docker-compose down
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
        options=("开启" composestart "终止" composedown "安装-build" composeinstall "删除所有命名卷" dockervolumerm)

        menu "${options[@]}"
    }

    sshpcdockerapp() {
        git clone https://github.com/sshpc/docker.git
    }

    menuname='首页/docker'
    echo "dockerfun" >$installdir/config/lastfun
    options=("启动" composestart "停止" composestop "查看状态" composeps "进入交互式容器" dockerexec "重启容器" restartcontainer "查看数据卷" catdockervolume "查看compose logs日志" catcomposelogs "安装&维护" maintenancefun "查看镜像" dockerimagesfun "下载sshpcdockerapp仓库" sshpcdockerapp)

    menu "${options[@]}"

}
