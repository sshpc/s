diskfun() {
    beforeMenu(){
    _blue "> ---  当前目录: [ $(pwd) ] ---- < v:${branch}-$selfversion"
    echo
    _yellow "当前菜单: $menuname "
    echo
    }

    #磁盘详细信息
    diskinfo() {
        _blue "--fdisk信息--"
        fdisk -l
        _blue "--lsblk块设备信息--"
        lsblk
        _blue "--分区信息--"
        df -Th
        echo
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

    menuname='首页/磁盘管理'
    echo "diskfun" >$installdir/config/lastfun
    options=("磁盘信息" diskinfo "磁盘测速" diskspeedtest)

    menu "${options[@]}"

}