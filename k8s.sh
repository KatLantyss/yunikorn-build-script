#!/bin/bash
# Tested on Kubernetes 1.26, 1.27

############ Color Text ############
colorful() {
  local color=$1 && shift 
  local text=$@

  # Regular Colors
  Black='\033[0;30m'        # Black
  Red='\033[0;31m'          # Red
  Green='\033[0;32m'        # Green
  Yellow='\033[0;33m'       # Yellow
  Blue='\033[0;34m'         # Blue
  Purple='\033[0;35m'       # Purple
  Cyan='\033[0;36m'         # Cyan
  White='\033[0;37m'        # White
  Done='\033[0m'

  case $color in
    black)
      echo -e "${Black}$text${Done}";;
    red)
      echo -e "${Red}$text${Done}";;
    green)
      echo -e "${Green}$text${Done}";;
    yellow)
      echo -e "${Yellow}$text${Done}";;
    blue)
      echo -e "${Blue}$text${Done}";;
    purple)
      echo -e "${Purple}$text${Done}";;
    cyan)
      echo -e "${Cyan}$text${Done}";;
    white)
      echo -e "${White}$text${Done}";;
  esac
}
####################################

############### Usage ##############
usage(){
  printf "Usage: k8s [options]\n"
  printf "Commands:\n"
  printf "  kill                           Terminate the Kubernetes Cluster\n"
  printf "  init                           Initialize a new Kubernetes Cluster\n"
  printf "  reset                          Reset and restart the Kubernetes Cluster\n\n"

  printf "  load                           Load Docker Images to Kubernetes.\n\n"

  printf "  list                           list Kubernetes Applications that can be installed\n"
  printf "  install                        Install Kubernetes Applications\n"
  printf "  uninstall                      Uninstall Kubernetes Applicaions\n\n"

  printf "  watch                          Watch Pod running status\n\n"

  printf "Options:\n"
  printf "  --cni [calico | flannel]       Specify the Container Network Interface (CNI) plugin (Calico as default)\n"
  printf "  --subnet [8/16/24/32]          Specify the CNI subnet (16 as default)\n"
  printf "  --gpu                          Configure for GPU environment (require nvidia-container-toolkit be installed)\n\n"

  printf "Examples:\n"
  printf "  k8s init  --cni=flannel        Initialize pods and use Flannel as CNI\n"
  printf "  k8s reset --gpu                Reset the cluster with GPU environment configuration\n"
  printf "  k8s install metric             Install matric API on cluster\n"
  printf "  k8s watch                      Watch Pod running status\n"
  printf "  k8s load local/my-image        Load local/my-image in Docker to Kubernetes\n"
  exit 1
}
####################################

cni_address() {
    if [[ $CNI == "flannel" ]]; then
      echo "10.244.0.0/$SUBNET"
    elif [[ $CNI == "calico" ]]; then
      echo "192.168.0.0/$SUBNET"
    fi
}

gpu_time_slice() {
  cat << EOF | kubectl create -f -
  apiVersion: v1
  kind: ConfigMap
  metadata:
    name: time-slicing-config
    namespace: nvidia-system
  data:
    default: |-
      version: v1
      flags:
        migStrategy: none
      sharing:
        timeSlicing:
          renameByDefault: false
          failRequestsGreaterThanOne: false
          resources:
            - name: nvidia.com/gpu
              replicas: $1
EOF
}

######### Combine commands #########
kubeadm_reset() {
  colorful red "Killing Kubernetes Cluster"
  echo "y" | sudo kubeadm reset
  sudo rm -rf ~/.kube
  sudo rm -rf /etc/cni/net.d
}

kubeadm_init() {
  colorful green "Initialize Kubernetes Cluster"
  sudo kubeadm init --pod-network-cidr=$(cni_address)

  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

  kubectl taint nodes --all node-role.kubernetes.io/control-plane-

  if [[ $CNI == "flannel" ]]; then
    curl -sL https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml \
    | sed "s/10.244.0.0\/16/10.244.0.0\/$SUBNET/g" \
    | kubectl apply -f -
  elif [[ $CNI == "calico" ]]; then
    kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/tigera-operator.yaml
    curl -sL https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/custom-resources.yaml \
    | sed "s/192.168.0.0\/16/192.168.0.0\/$SUBNET/g" \
    | kubectl create -f -
  fi

  watch -n 0 kubectl get pods -A
}

containerd_restart() { 
  colorful cyan "Restart Containerd"
  sudo bash -c "containerd config default > /etc/containerd/config.toml"
  sudo sed -i 's/            SystemdCgroup = false/            SystemdCgroup = true/' /etc/containerd/config.toml
  
  if [[ $NEED_GPU == true ]]; then
    colorful green "Enable GPU Enviroment..."
    sudo nvidia-ctk runtime configure --runtime=containerd
    sudo sed -i 's/      default_runtime_name = \"runc\"/      default_runtime_name = \"nvidia\"/' /etc/containerd/config.toml
  fi

  sudo systemctl restart containerd

  sudo crictl config runtime-endpoint unix:///var/run/containerd/containerd.sock
}

kubelet_restart() {
  colorful cyan "Restart Kubelet"
  sudo swapoff -a
  sudo systemctl restart kubelet
}
####################################

######### Parse argument #########
parse_argument() {
  CNI="calico"
  SUBNET="16"
  NEED_GPU=false

  ARGS=$(getopt -o "" -l cni:,subnet:,gpu -n "k8s" -- "$@")
  if [[ $? -ne 0 ]]; then usage; fi
  eval set -- "$ARGS"

  while [ $# -gt 0 ]
    do
      case $1 in
        --cni)
          if [[ "$2" == "calico" || "$2" == "flannel" ]]; then
            CNI="${2#*=}"
          else
            usage
          fi
          shift 2;;
        --subnet)
          if [[ "$2" == "8" || "$2" == "16" || "$2" == "24" || "$2" == "32" ]]; then
            SUBNET=$2
          else
            usage
          fi
          shift 2;;
        --gpu)
          NEED_GPU=true
          shift;;
        --)
          shift
          break;;
      esac
  done
  if [[ $# -ne 0 ]]; then usage; fi
}
####################################

############# Commands #############
kube_reset() {
  parse_argument "$@"

  colorful cyan "Reset cluster with ${CNI} [$(cni_address)]"

  kubeadm_reset
  containerd_restart
  kubelet_restart
  kubeadm_init
}

kube_kill() {
  kubeadm_reset
}

kube_init() {
  parse_argument "$@"

  colorful cyan "Init cluster with ${CNI} [$(cni_address)]"

  containerd_restart
  kubelet_restart
  kubeadm_init
}

kube_load() {
  if [[ $# -eq 0 ]]; then docker images --format '{{.Repository}}:{{.Tag}}' && exit; fi

  if [[ -z $(docker images --format  {{.Repository}}:{{.Tag}} | grep -w $1) ]]; then docker images --format '{{.Repository}}:{{.Tag}}' && exit; fi

  sudo crictl rmi --prune > /dev/null

  colorful cyan "[Docker] Save image..."
  docker save -o /tmp/temp_image.tar $1
  colorful cyan "[Containerd] Load image..."
  sudo ctr -n k8s.io image import /tmp/temp_image.tar
  sudo rm /tmp/temp_image.tar
  colorful cyan "[CRIO] List image..."
  sudo crictl images
}

kube_manage() { 
  if [[ $# -eq 0 ]]; then usage; fi
  while [ $# -gt 0 ]
    do
      case $1 in
        yunikorn)
          if [[ $COMMAND == "install" ]]; then
            helm repo add yunikorn https://apache.github.io/yunikorn-release
            helm repo update
            helm install yunikorn yunikorn/yunikorn --namespace yunikorn --create-namespace
          elif [[ $COMMAND == "uninstall" ]]; then
            helm uninstall yunikorn -n yunikorn
          fi
          shift;;
        prometheus)
          if [[ $COMMAND == "install" ]]; then
            helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
            helm repo update
            helm install prometheus prometheus-community/kube-prometheus-stack -n prometheus --create-namespace
          elif [[ $COMMAND == "uninstall" ]]; then
            helm uninstall prometheus -n prometheus
          fi
          shift;;
        metric)
          if [[ $COMMAND == "install" ]]; then
            curl -sL https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml \
            | sed '/      - args:/a \        - --kubelet-insecure-tls' \
            | kubectl create -f -
          elif [[ $COMMAND == "uninstall" ]]; then
            curl -sL https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml \
            | sed '/      - args:/a \        - --kubelet-insecure-tls' \
            | kubectl delete -f -
          fi
          shift;;
        kwok)
          local KWOK_LATEST_RELEASE=$(curl -s "https://api.github.com/repos/kubernetes-sigs/kwok/releases/latest" | jq -r '.tag_name')
          if [[ $COMMAND == "install" ]]; then
            kubectl create -f "https://github.com/kubernetes-sigs/kwok/releases/download/${KWOK_LATEST_RELEASE}/kwok.yaml"
            kubectl create -f "https://github.com/kubernetes-sigs/kwok/releases/download/${KWOK_LATEST_RELEASE}/stage-fast.yaml"
          elif [[ $COMMAND == "uninstall" ]]; then
            kubectl delete -f "https://github.com/kubernetes-sigs/kwok/releases/download/${KWOK_LATEST_RELEASE}/stage-fast.yaml"
            kubectl delete -f "https://github.com/kubernetes-sigs/kwok/releases/download/${KWOK_LATEST_RELEASE}/kwok.yaml"
          fi 
          shift;;
        nvidia:* | nvidia)
          if [[ $COMMAND == "install" ]]; then
            helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
            helm repo update
            helm install nvidia-operator nvidia/gpu-operator -n nvidia-system --create-namespace
          elif [[ $COMMAND == "uninstall" ]]; then
            helm uninstall nvidia-operator -n nvidia-system            
          fi

          if [[ ${1%:*} != ${1#*:} ]]; then
            colorful yellow "Setting GPU time slice to ${1#*:}"
            gpu_time_slice ${1#*:}

            kubectl patch clusterpolicy/cluster-policy \
            -n nvidia-system --type merge \
            -p '{"spec": {"devicePlugin": {"config": {"name": "time-slicing-config"}}}}'

            local node_name=$(kubectl describe node | grep Name: | awk '{print $2}')

            kubectl label node $node_name nvidia.com/device-plugin.config=default
          fi
          shift;;
        k9s)
          if [[ $COMMAND == "install" ]]; then
            local K9S_LATEST_RELEASE=$(curl -s "https://api.github.com/repos/derailed/k9s/releases/latest" | jq -r '.tag_name')
            curl -fsSL -o k9s_Linux_amd64.tar.gz https://github.com/derailed/k9s/releases/download/${K9S_LATEST_RELEASE}/k9s_Linux_amd64.tar.gz
            sudo tar -xzvf k9s_Linux_amd64.tar.gz -C /usr/local/bin k9s && rm -f k9s_Linux_amd64.tar.gz
          elif [[ $COMMAND == "uninstall" ]]; then
            sudo rm -rf /usr/local/bin/k9s
          fi
          shift;;
        *)
          colorful red "Application Not Found: ${1}"
          shift;;
      esac
  done
}

kube_list() {
  printf "Applications:\n"
  printf " - metric          Metrics Server is a scalable, efficient source of container resource metrics for Kubernetes built-in autoscaling pipelines\n"
  printf " - kwok            KWOK is a toolkit that enables setting up a cluster of thousands of Nodes in seconds\n"
  printf " - yunikorn        Unleash the power of resource scheduling for running Big Data & ML on Kubernetes\n"
  printf " - nvidia          NVIDIA GPU Operator uses the operator framework within Kubernetes to automate the management of all NVIDIA software components needed to provision GPU\n"
  printf " - prometheus      Power your metrics and alerting with the leading open-source monitoring solution\n"
  printf " - k9s             K9s is a terminal based UI to interact with your Kubernetes clusters\n"
}
####################################

############### Main ###############
if [ $# -lt 1 ]; then usage; fi

COMMAND=$1
shift

case $COMMAND in
  reset)
    kube_reset "$@"
    ;;
  kill)
    kube_kill
    ;;
  init)
    kube_init "$@"
    ;;
  load)
    kube_load "$@"
    ;;
  install | uninstall)
    kube_manage "$@"
    ;;
  list)
    kube_list
    ;;
  watch)
    watch -n 0 kubectl get pods -A
    ;;
  *)
    usage
    ;;
esac
####################################