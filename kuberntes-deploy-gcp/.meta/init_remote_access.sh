#!/bin/bash
##############################################################################
# This file is part of CW4D toolkit. it SETUP K8s CLUSTER IN RAW MODE
# ("Kubernetes Hard Way" Like)
# Copyright (C) Vadym Yanik 2024
#
# CW4D is free software: you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3  of the License, or (at your option) any
# later version
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; # without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License  along
# with this program; If not, see <http://www.gnu.org/licenses/>.
###############################################################################
CHEKED_SUCCES_FILE="/usr/local/etc/KUBE-OK"
MASTER="master-0"
BASTION="bastion.gcp"
GATEWAY="localhost"
KUBE_HOST_NAME="kubernetes"
KEY_PATH="../../.meta/private.key"
SSH_MODE="-o StrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null -i $KEY_PATH"

patch_windows_hosts_file() {
    #====== for Windows hosts file beyond WSL
    local hosts="/mnt/c/Windows/System32/drivers/etc/hosts"
    local hosts_tmp

    if [ -f "${hosts}" ]; then
        if stat -c "%A" $hosts | grep -q 'rw.$'; then
            hosts_tmp=$(mktemp)
            cp -f $hosts "$hosts_tmp"
            sed "/${1}/d" "$hosts_tmp" | tee $hosts >/dev/null 2>&1
            rm -f "$hosts_tmp"
            if [ -n "$2" ]; then
                cp -f $hosts "$hosts_tmp"
                sed "/${2}/d" "$hosts_tmp" | tee $hosts >/dev/null 2>&1
                rm -f "$hosts_tmp"
                echo "$1 $2" >>$hosts
            fi
        else

            echo "WSL users can't write to Windows hosts file!!!"
            echo "on WSL path: ${hosts}"
            stat -c "%A %U:%G " $hosts
            echo "setup needful access rights to it in  Windows!"

        fi
    fi
}

patch_linux_hosts_file() {
    #======= for any linux hosts file
    local hosts="/etc/hosts"
    local hosts_tmp
    hosts_tmp=$(mktemp)
    sudo chmod 666 $hosts
    cp -f "$hosts" "$hosts_tmp"
    sed "/${1}/d" "$hosts_tmp" | tee "$hosts" >/dev/null 2>&1
    rm -f "$hosts_tmp"
    if [ -n "$2" ]; then
        cp -f $hosts "$hosts_tmp"
        sed "/${2}/d" "$hosts_tmp" | tee "$hosts" >/dev/null 2>&1
        rm -f "$hosts_tmp"
        echo "$1 $2" >>"$hosts"
    fi
    sudo chmod 644 $hosts
}

get_kube_config() {
    [ -z "$3" ] && return
    [ -n "$2" ] && BASTION=$2
    local ssh_user=$3
    local config_file="/home/$ssh_user/.kube/config"
    local success_file=$config_file
    local user_home="/home/$(whoami)"

    [ -n "$CHEKED_SUCCES_FILE" ] && success_file=$CHEKED_SUCCES_FILE
    [ "$user_home" = "/home/root" ] && user_home="/root"

    echo "SSH-TUNNEL==>$BASTION==>$MASTER"
    ssh-keygen -f "$user_home/.ssh/known_hosts" -R "${BASTION}" >/dev/null 2>&1

    for ((i = 0; i < 60; i++)); do
        if ssh -q ${SSH_MODE} "$ssh_user@$BASTION" [[ -f "/usr/local/etc/KUBE-FAIL" ]] >/dev/null; then
            ssh ${SSH_MODE} "$ssh_user@$BASTION" "sudo cat /usr/local/etc/KUBE-FAIL"
            echo "BOOTSTRAP FAILED"
            break
        else
            if ssh -q ${SSH_MODE} "$ssh_user@$BASTION" [[ -f "$success_file" ]] >/dev/null; then
                mkdir -p "$user_home/.kube"
                echo "BOOTSTRAPING of CLUSTER finished IN: time=${i}0sec"

                ssh ${SSH_MODE} "$ssh_user@$BASTION" "sudo cat $config_file" >"$user_home/.kube"/cubefile.txt

                sed <"$user_home/.kube"/cubefile.txt "s/https:\/\/.*/https:\/\/$KUBE_HOST_NAME:8443/" >"$user_home/.kube/config.$BASTION"

                # reload SSH tunnel on local host
                TUNNEL=$(sudo ps -aux | grep 'ssh -o' | grep '8443:' | grep -v grep | awk '{print $2}')
                [ -n "$TUNNEL" ] && sudo kill -9 "$TUNNEL"
                ssh ${SSH_MODE} -NTf -L 8443:${MASTER}:6443 "$BASTION" >/dev/null 2>&1
                sudo rm -f "$user_home/.kube"/cubefile.txt
                echo "=====BOOTSTRAP of CLUSTER FINISHED======"
                ssh ${SSH_MODE} "$ssh_user@$BASTION" "[ -f '/usr/local/etc/KUBE-OK' ] && sudo cat /usr/local/etc/KUBE-OK"
                echo "*************************************************************************"
                echo " SSH tunnel to kube-api-server OPENED on $GATEWAY port 8443"
                echo " kube-config copied locally to $user_home/.kube/config.$BASTION"
                echo " and patched for DIRECT local access to this cluster over SSH tunnel"
                echo " RUN: kubectl --kubeconfig ~/.kube/config.$BASTION get nodes FOR START"
                echo "*************************************************************************"
                return
            fi
            echo "BOOTSTRAPING CLUSTER: time=${i}0sec"
            sleep 10
        fi
    done
    echo "=====BOOTSTRAP of CLUSTER FAILED (((======"
}

if [ -z "$1" ]; then
    echo '======= if set $1 only(any IP or FQDN) -> remove matched record from hosts file =========='
    echo '======== if set $1 & $2..4 (IP + FQDNs) -> change matched record in hosts file or add new ====='
else
    patch_linux_hosts_file $BASTION
    patch_windows_hosts_file $BASTION
    patch_linux_hosts_file localhost
    patch_windows_hosts_file localhost
    patch_linux_hosts_file "127.0.0.1" "localhost kubernetes"
    patch_windows_hosts_file "127.0.0.1" "localhost kubernetes"

    patch_linux_hosts_file "$@"
    patch_windows_hosts_file "$@"
    get_kube_config "$@"
fi
