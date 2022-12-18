#!/usr/bin/env bash

function system_init() {
    # 更新YUM仓库源
    if [[ -n `grep -e '^mirrorlist=http://mirrorlist.centos.org' /etc/yum.repos.d/CentOS-Base.repo` ]]; then
        sed -e 's|^mirrorlist=|#mirrorlist=|g' \
         -e 's|^#baseurl=http://mirror.centos.org/centos|baseurl=https://mirrors.ustc.edu.cn/centos|g' \
         -i.bak \
         /etc/yum.repos.d/CentOS-Base.repo
        yum makecache && yum update -y
        yum install net-tools lsof yum-utils device-mapper-persistent-data lvm2
        #配置docker源仓库
        yum-config-manager --add-repo https://mirrors.ustc.edu.cn/docker-ce/linux/centos/docker-ce.repo
    fi

    #关闭SELinux
    if [[ "Enforcing" == `getenforce` ]]; then
        sed -i 's/^SELINUX=enforcing$/SELINUX=disabled/' /etc/selinux/config && setenforce 0
    fi

    systemctl stop firewalld && systemctl disable firewalld
}

function install_docker() {
    #删除旧docker
    if [[ -n `rpm -qa|grep docker` ]]; then
        yum remove docker* -y
    fi
    #安装docker
    yum install -y docker-ce-19.03.9-3.el7 docker-ce-cli-19.03.9-3.el7 containerd.io
    #配置开机启动且立即启动docker
    systemctl enable docker --now
    mkdir -p /etc/docker
     #配置docker的镜像加速
    cat > /etc/docker/daemon.json <<-EOF
{
  "registry-mirrors": ["http://hub-mirror.c.163.com"]
}
EOF
    #加载配置
    systemctl daemon-reload
    #重启docker
    systemctl restart docker
    if [[ -n `docker version` ]]; then
        echo "docker installed successful"
    fi
}

function install_k8s() {
    #允许iptables检查桥接流量
    cat > /etc/modules-load.d/k8s.conf <<-EOF
br_netfilter
EOF
    cat > /etc/sysctl.d/k8s.conf<<-EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
    #加载系统配置
    sysctl --system
    #配置k8s的yum源地址
    cat > /etc/yum.repos.d/kubernetes.repo <<-EOF
[kubernetes]
name=Kubernetes
baseurl=http://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=0
repo_gpgcheck=0
gpgkey=http://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg http://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
EOF
    #安装 kubelet、kubeadm、kubectl
    yum install kubelet-1.20.9 kubeadm-1.20.9 kubectl-1.20.9 -y

    #启动kubelet
    systemctl enable kubelet --now

    #所有机器配置master域名
    echo "`hostname -I|awk '{print$1}'` master-cloud.hmc.com" >> /etc/hosts
    echo "`hostname` node`hostname|awk -F '-' '{print$3}'`-cloud.hmc.com" >> /etc/hosts
}

system_init
install_docker
install_k8s