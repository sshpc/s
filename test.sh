#!/bin/bash

get_ini_value() {
    local section="$1"
    local key="$2"
    local file="$3"

    # 检查文件是否存在
    if [ ! -f "$file" ]; then
        echo "Error: 文件 $file 不存在" >&2
        return 1
    fi

    # 使用sed先处理文件：移除Windows换行符^M，再用awk解析
    result=$(sed 's/\r$//' "$file" | awk -v target_section="$section" -v target_key="$key" '
        BEGIN {
            in_target = 0
            found = 0
        }
        
        # 清除首尾空白
        { 
            gsub(/^[ \t]+|[ \t]+$/, "", $0) 
        }
        
        # 跳过空行
        $0 == "" { next }
        
        # 匹配section行
        /^\[.*\]$/ {
            current_section = substr($0, 2, length($0)-2)
            gsub(/^[ \t]+|[ \t]+$/, "", current_section)
            in_target = (current_section == target_section)
            if (in_target) {
                #print "调试: 找到目标section [" current_section "]" > "/dev/stderr"
            }
            next
        }
        
        # 在目标section中查找key
        in_target {
            if ($0 ~ "^[ \t]*" target_key "[ \t]*=") {
                # 提取值
                value = substr($0, index($0, "=") + 1)
                gsub(/^[ \t]+|[ \t]+$/, "", value)
                print value
                found = 1
                exit 0
            }
        }
        
        END {
            if (!found) exit 1
        }
    ')

    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo "Error: 未找到 key '$key' 在 section '$section' 中" >&2
        return $exit_code
    fi

    echo "$result"
}

# 测试函数
echo "测试结果:"
get_ini_value "status" "name" "modules.conf"
