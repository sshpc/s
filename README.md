# 交互式shell脚本工具

## 示例

```sh
> ---- S [ 首页/其他工具 ] -------- < v: x.x

当前目录: [ /root ]

1: 状态           2: soft软件管理

3: network网络管理  4: system系统管理

5: docker       6: 其他工具

7: 升级脚本         8: 卸载脚本

0: 首页 b: 返回 q: 退出

请输入命令号(0-8): 

```


## 安装

### 一键安装(推荐)
> 推荐ubuntu 1804+ root 用户

```sh
wget -N  http://raw.githubusercontent.com/sshpc/s/main/s.sh && chmod +x s.sh &&  bash s.sh
```

> 再次执行只需要输入 “s” 

```sh
 root@server:~#  s
```

国内加速链接
```sh
wget -N  https://gh.ddlc.top/http://raw.githubusercontent.com/sshpc/s/main/s.sh && chmod +x s.sh &&  bash s.sh
```
```sh
wget -N  https://gh-proxy.com/http://raw.githubusercontent.com/sshpc/s/main/s.sh && chmod +x s.sh &&  bash s.sh
```
```sh
wget -N  https://edgeone.gh-proxy.com/http://raw.githubusercontent.com/sshpc/s/main/s.sh && chmod +x s.sh &&  bash s.sh
```
## 说明

新增参数模式 可传入多个函数参数，从而不进入交互操作直接执行
>自定义执行命令 自行查看脚本结构 (避免_exists slog 等内部工具函数、无意义、无效函数执行)

### 示例

#### 查看系统信息

s statusfun sysinfo

输出
```sh
 CPU Model          : QEMU Virtual CPU version 2.5+
 CPU Cores          : 2 @ 3695.986 MHz
 CPU Cache          : 16.0 MB
 AES-NI             : Enabled
 VM-x/AMD-V         : Disabled
 Total Disk         : 104.0 GB (35.4 GB Used)
 Total Mem          : 1.9 GB (1.6 GB Used)
 Total Swap         : 6.2 GB (863.4 MB Used)
 System uptime      : 19 days, 21 hour 3 min
 OS                 : Ubuntu 24.04.1 LTS
 Arch               : x86_64 (64 Bit)
 Kernel             : 6.8.0-71-generic
 TCP CC             : cubic
 Virtualization     : KVM
```
#### 查看docker状态

s dockerfun dockerstatusfun

输出
```sh
基本信息
运行中/共: 6/7 网络: 9 | 卷: 0
docker端口映射   
主机端口 3307 -> 容器端口 3306/tcp  [mysql2]    
主机端口 3306 -> 容器端口 3306/tcp  [mysql]    
主机端口 3001 -> 容器端口 3001/tcp  [uptime-kuma_uptime-kuma_1]    

compose情况
当前目录没有 docker-compose.yml 文件

容器情况
runing
CONTAINER ID   IMAGE                    COMMAND                  CREATED        STATUS                 PORTS                               NAMES
ee33fe9234c9   mysql:5.7                "docker-entrypoint.s…"   2 weeks ago    Up 2 hours             0.0.0.0:3306->3306/tcp, 33060/tcp   mysql
0646cd7b59a6   mysql:5.7                "docker-entrypoint.s…"   2 weeks ago    Up 27 hours            33060/tcp, 0.0.0.0:3307->3306/tcp   mysql2
b2097aaaf448   louislam/uptime-kuma:1   "/usr/bin/dumb-init …"   8 weeks ago    Up 2 weeks (healthy)   0.0.0.0:3001->3001/tcp              uptime-kuma_uptime-kuma_1

```

#### 重启容器

s dockerfun restartcontainer

输出
```sh
当前正在运行的容器：

序号    容器名称  容器ID         容器状态
1       mysql                       ee33fe9234c9   Up 2 hours
2       mysql2                      0646cd7b59a6   Up 27 hours

请输入要重启的容器序号（从 1 开始）： 1
正在重启容器：1
[ | ] loading ...ee33fe9234c9
已重启
```


#### 批量导出已使用的镜像到/home/img 目录

s dockerfun dockerimageimportexport  dockerimageexportuseall


#### 批量从/home/img 目录导入全部镜像

s dockerfun dockerimageimportexport  dockerimageimportall










