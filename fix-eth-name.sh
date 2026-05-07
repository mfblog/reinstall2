#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC3001

set -eE

# 本脚本在首次进入新系统后运行
# 将 trans 阶段生成的网络配置中的网卡名(eth0) 改为正确的网卡名
# 也适用于安装时和安装后内核网卡命名不一致的情况
# https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=928923

# 首次启动时网卡名可能会被 udev/systemd 反复修改几次，需等待名称稳定。
has_eth=false
check_count=0
stable_count=0
old_state=
while true; do
    check_count=$((check_count + 1))

    new_state=$(ip -o link | awk '$2 != "lo:"')
    if [ -n "$new_state" ]; then
        has_eth=true
    fi

    if $has_eth && [ "$old_state" = "$new_state" ]; then
        stable_count=$((stable_count + 1))
    else
        stable_count=0
    fi

    old_state=$new_state

    if $has_eth && [ "$stable_count" -ge 10 ]; then
        break
    fi

    if ! $has_eth && [ "$check_count" -ge 60 ]; then
        exit 1
    fi

    sleep 1
done

to_lower() {
    tr '[:upper:]' '[:lower:]'
}

get_ethx_by_mac() {
    mac=$(echo "$1" | to_lower)

    ip -o link | grep -i "$mac" | grep -v master | awk '{print $2}' | cut -d: -f1 | grep .
}

fix_ifupdown() {
    file=/etc/network/interfaces
    tmp_file=$file.tmp

    rm -f "$tmp_file"

    if [ -f "$file" ]; then
        while IFS= read -r line; do
            del_this_line=false
            if [[ "$line" = "# mac "* ]]; then
                ethx=
                if mac=$(echo "$line" | awk '{print $NF}'); then
                    ethx=$(get_ethx_by_mac "$mac") || true
                fi
                del_this_line=true
            elif [[ "$line" = "iface e"* ]] ||
                [[ "$line" = "auto e"* ]] ||
                [[ "$line" = "allow-hotplug e"* ]]; then
                if [ -n "$ethx" ]; then
                    line=$(echo "$line" | awk "{\$2=\"$ethx\"; print \$0}")
                fi
            elif [[ "$line" = *" dev e"* ]]; then
                if [ -n "$ethx" ]; then
                    line=$(echo "$line" | sed -E "s/[^ ]*$/$ethx/")
                fi
            fi
            if ! $del_this_line; then
                echo "$line" >>"$tmp_file"
            fi
        done <"$file"

        mv "$tmp_file" "$file"
    fi
}

fix_ifupdown
