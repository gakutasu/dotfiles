#!/usr/bin/sh

# ROS2 default workspace path
ROS_WS=~/ros
export _colcon_cd_root=$ROS_WS
source $ROS_WS/install/setup.bash

# roskill: force-kill all ROS-related processes
roskill() {
    ps aux | grep ros | grep -v grep | awk '{ print "kill -9", $2 }' | sh
}

# Find workspace root
find_ros_workspace_root() {
    local dir=$(pwd)
    while [ "$dir" != "/" ]; do
        if [ -d "$dir/src" ]; then
            if find "$dir/src" -name package.xml | grep -q .; then
                if [ ! -f "$dir/package.xml" ]; then
                    echo "$dir"
                    return 0
                fi
            fi
        fi
        dir=$(dirname "$dir")
    done
    echo -e "\e[31mNot a ROS2 workspace.\e[0m" >&2
    return 1
}

# rossource: source install/setup.bash of the current workspace
rossource() {
    local ws
    ws=$(find_ros_workspace_root) || return 1
    if [ -f "$ws/install/setup.bash" ]; then
        source "$ws/install/setup.bash"
        echo "Sourced $ws/install/setup.bash"
    else
        echo -e "\e[31m$ws/install/setup.bash not found.\e[0m"
    fi
}

# cbt: build the current package with --packages-up-to and source
cbt() {
    local ws
    ws=$(find_ros_workspace_root) || return 1
    if [ ! -f "package.xml" ]; then
        echo -e "\e[31mpackage.xml not found in $(pwd).\e[0m" >&2
        return 1
    fi
    local pkg_name
    pkg_name=$(grep "<name>" package.xml | sed -e "s/<[^>]*>//g" | xargs)
    cd "$ws" || return 1
    colcon build --symlink-install \
        --cmake-args -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
        -DCMAKE_BUILD_TYPE=Release \
        --parallel-workers "$(nproc)" --packages-up-to "$pkg_name"
    rossource
}

# cb [pkg]: build the whole workspace or a specific package and source
cb() {
    local ws
    ws=$(find_ros_workspace_root) || return 1
    cd "$ws" || return 1
    if [ $# -gt 0 ]; then
        colcon build --symlink-install \
            --cmake-args -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
            -DCMAKE_BUILD_TYPE=Release \
            --parallel-workers "$(nproc)" --packages-up-to "$1"
    else
        colcon build --symlink-install \
            --cmake-args -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
            -DCMAKE_BUILD_TYPE=Release \
            --parallel-workers "$(nproc)"
    fi
    rossource
}

# rosclean [pkg]: clean the whole workspace or a specific package
rosclean() {
    local ws
    ws=$(find_ros_workspace_root) || return 1
    cd "$ws" || return 1
    if [ $# -eq 0 ]; then
        colcon clean workspace
    else
        colcon clean packages --packages-select "$1"
    fi
}


REAL_ROSDEP="$(command -v rosdep)"
rosdep() {
    local sub="$1"
    shift
    case "$sub" in
        install)
            local ws
            ws=$(find_ros_workspace_root) || return 1
            cd "$ws" || return 1
            "$REAL_ROSDEP" install --from-paths src --ignore-src -ry "$@"
            ;;
        *)
            "$REAL_ROSDEP" "$sub" "$@"
            ;;
    esac
}

# _rtop_load_color: return ANSI color for a load average value
#   yellow if > cores, red if > cores * 1.5
_rtop_load_color() {
    awk -v v="$1" -v c="$2" 'BEGIN {
        if (v > c * 1.5) print "\033[31m";
        else if (v > c) print "\033[33m";
        else print "";
    }'
}

# rtop: htop-like view of processes with ROS node names (auto-refresh)
#   Usage: rtop [interval_sec]  (default: 1.5, matches htop's default)
#   Colors: cyan=ROS / default=system / yellow=heavy / red=very heavy
rtop() {
    local interval=${1:-1.5}
    local cores=$(nproc)
    trap 'tput cnorm; echo; return 0' INT
    tput civis
    clear
    echo "Sampling for ${interval}s..."
    while :; do
        local data
        data=$(top -bn2 -d "$interval" -o %CPU -w 512 2>/dev/null | awk '
            /^[[:space:]]*PID[[:space:]]+USER/ {h++; if (h == 2) flag=1; next}
            flag && NF > 0 {print $1, $9, $10}
        ' | sort -k2 -nr | head -15)
        local timestamp="$(date '+%H:%M:%S')"
        local load_str
        load_str="$(uptime | awk -F'load average: ' '{print $2}')"
        local load_1 load_5 load_15
        IFS=', ' read -r load_1 load_5 load_15 <<< "$load_str"
        local lc1 lc5 lc15
        lc1=$(_rtop_load_color "$load_1" "$cores")
        lc5=$(_rtop_load_color "$load_5" "$cores")
        lc15=$(_rtop_load_color "$load_15" "$cores")
        local reset="\033[0m"
        local mem_info="$(free -h | awk '/^Mem:/ {printf "%s/%s", $3, $2}')"
        {
            printf "\033[1;36m=== ROS Top ===\033[0m  %s  load: ${lc1}%s${reset}, ${lc5}%s${reset}, ${lc15}%s${reset}  (%d cores)  mem: %s\n" \
                "$timestamp" "$load_1" "$load_5" "$load_15" "$cores" "$mem_info"
            printf "Refresh: %ss | \033[36mROS\033[0m / System | CPU \033[33m>50%%\033[0m \033[31m>100%%\033[0m | MEM \033[33m>5%%\033[0m \033[31m>15%%\033[0m | load \033[33m>%dcore\033[0m \033[31m>%dcore\033[0m | Ctrl+C\n\n" \
                "$interval" "$cores" "$((cores * 3 / 2))"
            printf "\033[1m%-8s %8s %7s  %s\033[0m\n" "PID" "%CPU" "%MEM" "PROCESS"
            printf -- '-%.0s' $(seq 1 75); echo
            echo "$data" | while read pid cpu mem; do
                local args node name is_ros=0
                args=$(ps -p "$pid" -o args= 2>/dev/null)
                node=$(echo "$args" | grep -oP "__node:=\K[^ ]+" | head -1)
                if [ -n "$node" ]; then
                    is_ros=1
                    name="$node"
                else
                    if echo "$args" | grep -qE "(/ros/|/ros2_|component_container|rclcpp|^ros2 | ros2 |/opt/ros/)"; then
                        is_ros=1
                    fi
                    name=$(ps -p "$pid" -o comm= 2>/dev/null)
                fi
                local reset="\033[0m"
                # CPU column color: load-based
                local cpu_int="${cpu%.*}"
                local cpu_color=""
                if [ "$cpu_int" -gt 100 ] 2>/dev/null; then
                    cpu_color="\033[31m"       # red (very heavy)
                elif [ "$cpu_int" -gt 50 ] 2>/dev/null; then
                    cpu_color="\033[33m"       # yellow (heavy)
                fi
                # MEM column color: usage-based
                local mem_int="${mem%.*}"
                local mem_color=""
                if [ "$mem_int" -gt 15 ] 2>/dev/null; then
                    mem_color="\033[31m"       # red (very heavy memory use)
                elif [ "$mem_int" -gt 5 ] 2>/dev/null; then
                    mem_color="\033[33m"       # yellow (heavy memory use)
                fi
                # Name column color: ROS vs System
                local name_color=""
                [ "$is_ros" = "1" ] && name_color="\033[36m"  # cyan for ROS
                printf "%-8s ${cpu_color}%7s%%${reset} ${mem_color}%6s%%${reset}  ${name_color}%s${reset}\n" \
                    "$pid" "$cpu" "$mem" "$name"
            done
        } > /tmp/.rtop_buf.$$
        clear
        cat /tmp/.rtop_buf.$$
        rm -f /tmp/.rtop_buf.$$
    done
}
