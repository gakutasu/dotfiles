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
        colcon clean packages --packages-up-to "$1"
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
