#!/bin/bash

new_page() {
    clear
    colorful blue bold "********* Yunikorn Build Script *********\n"

    colorful yellow bold "-----------------------------------------"

    if [[ -f ~/yunikorn/.yunikorn-version ]]; then
        colorful yellow bold "\tYunikorn Version: $(cat ~/yunikorn/.yunikorn-version)"
    else
        colorful yellow bold "\tYunikorn Version: None"
    fi

    colorful yellow bold "-----------------------------------------\n"
}

colorful() {
    local color_tag=$1 && shift
    local style_tag=$1 && shift
    local text=$@

    declare -A color
    declare -A style
    
    NC='\e[0m'
    
    color["black"]="0m"
    color["red"]="1m"
    color["green"]="2m"
    color["yellow"]="3m"
    color["blue"]="4m"
    color["purple"]="5m"
    color["cyan"]="6m"
    color["white"]="7m"
    
    style["regular"]="0;3"
    style["bold"]="1;3"
    style["faded"]="2;3"
    style["italics"]="3;3"
    style["underline"]="4;3"
    style["blink"]="5;3"

    echo -e "\e[${style[$style_tag]}${color[$color_tag]}$text${NC}"
}

download_yunikorn() {
    new_page

    # Remove old directory
    if [ -d "$HOME/yunikorn" ]; then
        colorful red bold "$HOME/yunikorn has already exist."
        read -p "$(colorful red bold "This will rewrite the file, continue? [y/N] ")" rewrite_flag && echo
        
        if [[ $rewrite_flag == "y" || $rewrite_flag == "Y" || $rewrite_flag == "" ]]; then
            rm -rf ~/yunikorn
        else
            echo "Abort."
            return 0
        fi
    fi
    
    # Create new Yunikorn directory
    mkdir ~/yunikorn
    cd ~/yunikorn

    # List Yunikorn version
    # This will call github api, may cause api rate limit error.
    new_page
    colorful blue bold "Select a Yunikorn version to download\n"

    local response=$(curl -s "https://api.github.com/repos/apache/yunikorn-k8shim/releases")
    local optnum=1
    declare -A yunikorn_version

    yunikorn_version["0"]="master"
    colorful green bold " $(printf "%2d" "0"). master"

    while read -r tag; do
        colorful green bold " $(printf "%2d" "$optnum"). $tag"
        yunikorn_version["$optnum"]="$tag"
        optnum=$((optnum+1))
    done < <(echo "$response" | jq -r '.[].tag_name')

    # Version Selector
    echo -e -n "\nPlease select a version: " && read version_tag
    if [[ -z ${yunikorn_version["$version_tag"]} ]]; then
        colorful red bold "Invalid Option!"
        return 0
    fi

    # Download Yunikorn
    YUNIKORN_VERSION=${yunikorn_version["$version_tag"]}
    echo "$YUNIKORN_VERSION" > .yunikorn-version

    colorful yellow bold "Yunikorn Version: ${YUNIKORN_VERSION}"

    if [[ $YUNIKORN_VERSION == "master" ]]; then
        colorful blue bold "\nDownloading yunikorn-core..." && git clone https://github.com/apache/yunikorn-core.git
        colorful blue bold "\nDownloading yunikorn-k8shim..." && git clone https://github.com/apache/yunikorn-k8shim.git
        colorful blue bold "\nDownloading yunikorn-scheduler-interface..." && git clone https://github.com/apache/yunikorn-scheduler-interface.git
        colorful blue bold "\nDownloading yunikorn-web..." && git clone https://github.com/apache/yunikorn-web.git
    else
        colorful blue bold "\nDownloading yunikorn-core..."
        curl -fsSL -o yunikorn-core.tar.gz https://github.com/apache/yunikorn-core/archive/refs/tags/${YUNIKORN_VERSION}.tar.gz
        tar -xzvf yunikorn-core.tar.gz -C ~/yunikorn && rm -f ~/yunikorn/yunikorn-core.tar.gz
        mv ~/yunikorn/yunikorn-core-${YUNIKORN_VERSION#v} ~/yunikorn/yunikorn-core

        colorful blue bold "\nDownloading yunikorn-k8shim..."
        curl -fsSL -o yunikorn-k8shim.tar.gz https://github.com/apache/yunikorn-k8shim/archive/refs/tags/${YUNIKORN_VERSION}.tar.gz
        tar -xzvf yunikorn-k8shim.tar.gz -C ~/yunikorn && rm -f ~/yunikorn/yunikorn-k8shim.tar.gz
        mv ~/yunikorn/yunikorn-k8shim-${YUNIKORN_VERSION#v} ~/yunikorn/yunikorn-k8shim
        
        colorful blue bold "\nDownloading yunikorn-scheduler-interface..."
        curl -fsSL -o yunikorn-scheduler-interface.tar.gz https://github.com/apache/yunikorn-scheduler-interface/archive/refs/tags/${YUNIKORN_VERSION}.tar.gz
        tar -xzvf yunikorn-scheduler-interface.tar.gz -C ~/yunikorn && rm -f ~/yunikorn/yunikorn-scheduler-interface.tar.gz
        mv ~/yunikorn/yunikorn-scheduler-interface-${YUNIKORN_VERSION#v} ~/yunikorn/yunikorn-scheduler-interface
        
        colorful blue bold "\nDownloading yunikorn-web..."
        curl -fsSL -o yunikorn-web.tar.gz https://github.com/apache/yunikorn-web/archive/refs/tags/${YUNIKORN_VERSION}.tar.gz
        tar -xzvf yunikorn-web.tar.gz -C ~/yunikorn && rm -f ~/yunikorn/yunikorn-web.tar.gz
        mv ~/yunikorn/yunikorn-web-${YUNIKORN_VERSION#v} ~/yunikorn/yunikorn-web
    fi
}

build_yunikorn() {
    new_page

    if [ ! -d "$HOME/yunikorn/yunikorn-k8shim" ]; then
        read -p "$(colorful red bold "Can't find yunikorn! Do you want to download? [y/N] ")" download_flag && echo
        if [[ $download_flag == "y" || $download_flag == "Y" || $download_flag == "" ]]; then
            download_yunikorn
        else
            echo "Abort."
        fi
        return 0
    fi

    local core_replacement="replace $(cat ~/yunikorn/yunikorn-k8shim/go.mod | grep github.com/apache/yunikorn-core | sed 's/^[ \t]*//;s/[ \t]*$//') => ../yunikorn-core"
    local interface_replacement="replace $(cat ~/yunikorn/yunikorn-k8shim/go.mod | grep github.com/apache/yunikorn-scheduler-interface | sed 's/^[ \t]*//;s/[ \t]*$//') => ../yunikorn-scheduler-interface"

    if [[ $(cat ~/yunikorn/yunikorn-k8shim/go.mod | grep "${core_replacement}" | wc -l) -eq 0 && $(cat ~/yunikorn/yunikorn-k8shim/go.mod | grep "${interface_replacement}" | wc -l) -eq 0 ]]; then
        colorful blue bold "Direct core & interface to local."
        sed -i "$ a\\\n$core_replacement\n$interface_replacement\n" ~/yunikorn/yunikorn-k8shim/go.mod
    else
        colorful yellow bold "Core & Interface are already directed to local."
    fi

    colorful blue bold "\nCleaning old images..."
    sudo chmod 777 /var/run/docker.sock
    sudo crictl rmi --prune
    if [[ $(sudo docker images --filter "reference=yunikorn/yunikorn"  --format {{.ID}}) ]]; then
        docker rmi $(sudo docker images --filter "reference=yunikorn/yunikorn"  --format {{.ID}})
    fi
    
    colorful blue bold "\nBuild k8shim image..."
    cd ~/yunikorn/yunikorn-k8shim && make image DOCKER_ARCH=amd64 REGISTRY=yunikorn VERSION=latest 
    
    colorful blue bold "\nBuild web image..."
    cd ~/yunikorn/yunikorn-web && make image DOCKER_ARCH=amd64 REGISTRY=yunikorn VERSION=latest 

    colorful blue bold "\nCurrect Docker images:"
    docker images

    colorful blue bold "\nLoading images to Kubernetes cluster..."
    for i in $(docker images --filter "reference=yunikorn/yunikorn" --format {{.Repository}}:{{.Tag}}); do
        docker save -o ~/yunikorn/${i#yunikorn/yunikorn:*}.tar $i
        sudo ctr -n k8s.io image import ~/yunikorn/${i#yunikorn/yunikorn:*}.tar
        rm ~/yunikorn/${i#yunikorn/yunikorn:*}.tar
    done

    colorful blue bold "\nCurrect CRIO images:"
    sudo crictl images
}

deploy_yunikorn() {
    new_page

    colorful blue bold "Choose yunikorn deployment modes\n"
    colorful green bold " 1. Standard mode"
    colorful green bold " 2. Plugin mode"

    echo -e -n "\nPlease select mode: " && read mode_tag

    if [[ $mode_tag != "1" && $mode_tag != "2" ]]; then
        colorful red bold "Invalid Option!"
        return 0
    fi

    new_page
    
    cd ~/yunikorn/yunikorn-k8shim/deployments/scheduler

    if [[ $mode_tag == "1" ]]; then
        colorful yellow bold "Deploy yunikorn standard mode.\n"

        colorful blue bold "Create yunikorn namespace."
        kubectl create ns yunikorn

        # Setup RBAC for Scheduler
        colorful blue bold "\nSetup RBAC for Scheduler."
        kubectl create -f yunikorn-rbac.yaml -n yunikorn

        # Create the ConfigMap
        colorful blue bold "\nCreate the ConfigMap."
        kubectl create -f yunikorn-configs.yaml -n yunikorn

        # Deploy the Scheduler
        colorful blue bold "\nDeploy the Scheduler."
        sed 's/image: apache/image: yunikorn/g' scheduler-load.yaml | kubectl create -f - -n yunikorn

        # Setup RBAC for Admission Controller
        colorful blue bold "\nSetup RBAC for Admission Controller."
        kubectl create -f admission-controller-rbac.yaml -n yunikorn

        # Create the Secret
        colorful blue bold "\nCreate the Secret."
        kubectl create -f admission-controller-secrets.yaml -n yunikorn

        # Deploy the Admission Controller
        colorful blue bold "\nDeploy the Admission Controller."
        sed 's/image: apache/image: yunikorn/g' admission-controller.yaml | kubectl create -f - -n yunikorn

    elif [[ $mode_tag == "2" ]]; then
        colorful yellow bold "Deploy yunikorn plugin mode.\n"

        colorful blue bold "Create yunikorn namespace."
        kubectl create ns yunikorn

        # Setup RBAC for Scheduler
        colorful blue bold "\nSetup RBAC for Scheduler."
        kubectl create -f yunikorn-rbac.yaml -n yunikorn

        # Create the ConfigMap
        colorful blue bold "\nCreate the ConfigMap."
        kubectl create -f yunikorn-configs.yaml -n yunikorn

        colorful blue bold "\nDeploy the Scheduler."
        sed 's/image: apache/image: yunikorn/g' plugin.yaml | kubectl create -f - -n yunikorn
    fi

    sleep 3

    colorful blue bold "\nCurrent Pod Status."
    kubectl get pods -n yunikorn
}

delete_yunikorn() {
    new_page

    cd ~/yunikorn/yunikorn-k8shim/deployments/scheduler

    colorful blue bold "Delete yunikorn from Kubernetes\n"

    colorful blue bold "\nDelete the Admission Controller."
    sed 's/image: apache/image: yunikorn/g' admission-controller.yaml | kubectl delete -f - -n yunikorn

    colorful blue bold "\nDelete the Secret."
    kubectl delete -f admission-controller-secrets.yaml -n yunikorn

    colorful blue bold "\nDelete RBAC for Admission Controller."
    kubectl delete -f admission-controller-rbac.yaml -n yunikorn

    colorful blue bold "\nDelete the Scheduler."
    sed 's/image: apache/image: yunikorn/g' scheduler-load.yaml | kubectl delete -f - -n yunikorn

    colorful blue bold "\nDelete the ConfigMap."
    kubectl delete -f yunikorn-configs.yaml -n yunikorn

    colorful blue bold "\nDelete RBAC for Scheduler."
    kubectl delete -f yunikorn-rbac.yaml -n yunikorn

    colorful blue bold "\nDelete yunikorn namespace."
    kubectl delete ns yunikorn
}

main() {
    while true; do
        new_page

        colorful green bold " 1. Download Yunikorn."
        colorful green bold " 2. Build Yunikorn. (v1.3+ only)"
        colorful green bold " 3. Deploy Yunikorn on Kubernetes."
        colorful green bold " 4. Delete Yunikorn from Kubernetes.\n"

        colorful green bold " Q. Quit\n"

        read -p "Please select an option: " flag

        case $flag in
            1)
                download_yunikorn
                ;;
            2)
                build_yunikorn
                ;;
            3)
                deploy_yunikorn
                ;;
            4)
                delete_yunikorn
                ;;
            q | Q)
                exit 0
                ;;
            *)
                colorful red bold "Invalid Option!"
        esac

        read -p "$(colorful cyan regular "\nPress Enter to continue.")"
        
        clear
    done
}

main