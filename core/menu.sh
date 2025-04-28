menutop() {
    clear
    _green '# Ubuntu初始化&工具脚本'
    _green '# Author:SSHPC <https://github.com/sshpc>'
    echo
    _blue ">~~~~~~~~~~~~~~ Ubuntu tools 脚本工具 ~~~~~~~~~~~~<  v: $selfversion"

}

menu() {
    menutop
    echo
    _yellow "当前菜单: $menuname "
    echo

    local options=("$@")
    local num_options=${#options[@]}
    local max_len=0

    for ((i = 0; i < num_options; i += 2)); do
        local str_len=${#options[i]}
        ((str_len > max_len)) && max_len=$str_len
    done

    for ((i = 0; i < num_options; i += 4)); do
        printf "%s%*s  " "$((i / 2 + 1)): ${options[i]}" "$((max_len - ${#options[i]}))"
        [[ -n "${options[i + 2]}" ]] && printf "$((i / 2 + 2)): ${options[i + 2]}"
        echo -e "\n"
    done

    _blue "0: 首页 b: 返回 q: 退出"
    
    echo
    read -ep "请输入命令号(0-$((num_options / 2))): " number

    if [[ $number -ge 1 && $number -le $((num_options / 2)) ]]; then
        #找到函数名索引
        local action_index=$((2 * (number - 1) + 1))
        #函数名赋值
        parentfun=${options[action_index]}
        #记录运行日志
        slog set run "$datevar | $menuname | ${options[action_index]} (${options[action_index - 1]})"

        #函数执行
        ${options[action_index]}
        nextrun
    elif [[ $number == 0 ]]; then
        main
    elif [[ $number == 'b' ]]; then
        if [[ -n "${FUNCNAME[3]}" ]]; then
            ${FUNCNAME[3]}
        else
            main
        fi
    elif [[ $number == 'q' ]]; then
        echo
        kill -15 $$
    else
        echo
        _red '输入有误  回车返回首页'
        waitinput
        main
    fi
}
