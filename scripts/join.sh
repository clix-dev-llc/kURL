#!/bin/bash

set -e

DIR=.

# Magic begin: scripts are inlined for distribution. See "make build/join.sh"
. $DIR/scripts/Manifest
. $DIR/scripts/common/addon.sh
. $DIR/scripts/common/common.sh
. $DIR/scripts/common/discover.sh
. $DIR/scripts/common/docker.sh
. $DIR/scripts/common/kubernetes.sh
. $DIR/scripts/common/object_store.sh
. $DIR/scripts/common/preflights.sh
. $DIR/scripts/common/prompts.sh
. $DIR/scripts/common/proxy.sh
. $DIR/scripts/common/rook.sh
. $DIR/scripts/common/utilbinaries.sh
. $DIR/scripts/common/yaml.sh
# Magic end

function join() {
    if [ "$MASTER" = "1" ]; then
        logStep "Join Kubernetes master node"

        # this will stop all the control plane pods except etcd
        rm -f /etc/kubernetes/manifests/kube-*
        if commandExists docker ; then
            while docker ps | grep -q kube-apiserver ; do
                sleep 2
            done
        elif commandExists crictl ; then
            while crictl ps | grep -q kube-apiserver ; do
                sleep 2
            done
        fi
        # delete files that need to be regenerated in case of load balancer address change
        rm -f /etc/kubernetes/*.conf
        rm -f /etc/kubernetes/pki/apiserver.crt /etc/kubernetes/pki/apiserver.key
    else
        logStep "Join Kubernetes node"
    fi

    kustomize_kubeadm_join=./kustomize/kubeadm/join
    if [ "$MASTER" = "1" ]; then
        insert_patches_strategic_merge \
            $kustomize_kubeadm_join/kustomization.yaml \
            patch-certificate-key.yaml
    fi
    # Add kubeadm join patches from addons.
    for patch in $(ls -1 ${kustomize_kubeadm_join}-patches/* 2>/dev/null || echo); do
        patch_basename="$(basename $patch)"
        cp $patch $kustomize_kubeadm_join/$patch_basename
        insert_patches_strategic_merge \
            $kustomize_kubeadm_join/kustomization.yaml \
            $patch_basename
    done
    mkdir -p "$KUBEADM_CONF_DIR"
    kubectl kustomize $kustomize_kubeadm_join > $KUBEADM_CONF_DIR/kubeadm-join-raw.yaml
    render_yaml_file $KUBEADM_CONF_DIR/kubeadm-join-raw.yaml > $KUBEADM_CONF_FILE

    cp $KUBEADM_CONF_FILE $KUBEADM_CONF_DIR/kubeadm_conf_copy_in
    $DIR/bin/yamlutil -r -fp $KUBEADM_CONF_DIR/kubeadm_conf_copy_in -yf metadata
    mv $KUBEADM_CONF_DIR/kubeadm_conf_copy_in $KUBEADM_CONF_FILE

    set +e
    (set -x; kubeadm join --config /opt/replicated/kubeadm.conf --ignore-preflight-errors=all)
    _status=$?
    set -e

    if [ "$_status" -ne "0" ]; then
        printf "${RED}Failed to join the kubernetes cluster.${NC}\n" 1>&2
        exit $_status
    fi

    if [ "$MASTER" = "1" ]; then
        exportKubeconfig
        logStep "Master node joined successfully"
    else
        logStep "Node joined successfully"
    fi
}

outro() {
    printf "\n"
    printf "\t\t${GREEN}Installation${NC}\n"
    printf "\t\t${GREEN}  Complete ✔${NC}\n"
    if [ "$MASTER" = "1" ]; then
        printf "\n"
        kubeconfig_setup_outro
    fi
    printf "\n"
}

function main() {
    export KUBECONFIG=/etc/kubernetes/admin.conf
    require_root_user
    get_patch_yaml "$@"
    proxy_bootstrap
    download_util_binaries
    merge_yaml_specs
    apply_bash_flag_overrides "$@"
    parse_yaml_into_bash_variables
    parse_kubernetes_target_version
    discover
    preflights
    joinPrompts
    prompts
    journald_persistent
    configure_proxy
    configure_no_proxy
    install_cri
    get_shared
    setup_kubeadm_kustomize
    addon_for_each addon_join
    kubernetes_host
    join
    outro
}

main "$@"
