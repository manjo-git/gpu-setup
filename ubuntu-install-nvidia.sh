# Copyright 2019 Canonical Ltd.  This software is licensed under the
# GNU Affero General Public License version 3 (see the file LICENSE).
# Author: Manoj Iyer <manoj.iyer@canonical.com>
#!/bin/bash

download_only=""
proxy=""
url=""
nvidia_cuda_url=""
nvidia_ml_url=""
host_arch=""
arch=""
rel=""
nvidia_release=""
latest_cuda_deb=""
latest_ml_deb=""
latest_key=""

opts=`getopt -o dhp: --long help,proxy -n 'parse-options' -- "$@"`

usage() {
    cat <<EOF
    Usage: $0 [--proxy <proxy> ]
    Options:
    -d | --download-only   Download latest debs and key only
    -h | --help            This message
    -p | --proxy           proxy_server:port

    Installs nvidia properitary drivers. If used from behind a firewall
    please use provide proxy_server:port information.
EOF
}

while true; do
    case $1 in
	-d | --download-only) download_only="True"; shift;;
        -h | --help) usage; exit 1 ;;
        -p | --proxy) proxy="$2"; shift ;;
        --) shift; break;;
        *) break ;;
    esac
done

# Setup proxy eg: squid.internal:3128
if [[ ! -z ${proxy} ]]; then
    export http_proxy=${proxy}
    export https_proxy=${proxy}

    if [[ ! -f $HOME/.wgetrc ]]; then
        cat <<EOF >> $HOME/.wgetrc
use_proxy=yes
http_proxy=${proxy}
https_proxy=${proxy}
EOF
    else
        if grep -Fxq "${proxy}" $HOME/.wgetrc; then
            :
        else
            cat <<EOF >> $HOME/.wgetrc
use_proxy=yes
http_proxy=${proxy}
https_proxy=${proxy}
EOF
        fi
    fi
fi

# Get architecture of debs to download
host_arch=$(dpkg --print-architecture)
case ${host_arch} in
    amd64) arch="x86_64" ;;
    ppc64el) arch=${host_arch} ;;
    *) echo "FATAL: Unsopported architecture ${host_arch}" ;;
esac

# Get host Ubuntu release version.
# Force min host Uubntu release to 18.04 or newer
check_version() { test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1"; }
host_ver=$(lsb_release  -r | cut -d: -f2)
if check_version "18.04" ${host_ver}; then
    echo "FATAL: Unsupported Ubuntu release"
    echo "Host Ubuntu release must be 18.04 or greater"
    exit
fi

# Check if we can reach Nvidia's cuda repos and ML repos.
for repos in "cuda" "machine-learning"; do
    curl --connect-timeout 20 -s \
	http://developer.download.nvidia.com/compute/${repos}/repos/ &>/dev/null
    if [ $? -eq 28 ]; then
        echo "Unable to reach http://developer.download.nvidia.com/"
        echo "If you are behind a fire wall use -p | --proxy "
        usage
        exit 1
    fi
done

# Find the latest Ubuntu cudo repo from Nvidia, and generate corresponding
# ML repo.
# Nvidia's web site has empty directories for newer releases, skip those
# till we find Ubuntu releases for which we have valid debs.
nvidia_releases=$(curl --connect-timeout 20 -s \
	http://developer.download.nvidia.com/compute/cuda/repos/ | \
	awk '{gsub(/<[^>]*>/,""); print }' | grep ubuntu | tail -n2 | tac)

for rel in ${nvidia_releases%/}; do
    url=$(curl -s \
    http://developer.download.nvidia.com/compute/cuda/repos/${rel}/${arch}/ | \
    grep cuda-repo-ubuntu);
    if [[ ! -z "${url}" ]]; then
        nvidia_cuda_url="http://developer.download.nvidia.com/compute/cuda/repos/${rel}/${arch}/";
	# Generate Machine Learning repo URL that corresponds to cuda URL.
	# We want the library to match the driver.
        nvidia_ml_url="http://developer.download.nvidia.com/compute/machine-learning/repos/${rel}/${arch}/";
        break;
    fi
done

# Find the latest cuda and ML repo debs for Ubuntu release from Nvidia
# Nvidia retains older debs along with the latest debs in the same directory,
# we want to pick up the latest debs that are available.
if [[ ! -z ${nvidia_cuda_url} ]]; then
    latest_cuda_deb=$(curl -s ${nvidia_cuda_url} | grep "cuda-repo-ubuntu" | \
	    tail -n1 | awk '{gsub(/<[^>]*>/,""); print }' | tr -d ' ')
    latest_key=$(curl -s ${nvidia_cuda_url} | grep ".pub" | tail -n1 | \
	    awk '{gsub(/<[^>]*>/,""); print }' | tr -d ' ')
else
    echo "FATAL: No nvidia cuda repository found.. exiting"
    exit 1
fi

if [[ ! -z ${nvidia_ml_url} ]]; then
    latest_ml_deb=$(curl -s ${nvidia_ml_url} | \
	    grep "nvidia-machine-learning-repo-ubuntu" | \
	    tail -n1 | awk '{gsub(/<[^>]*>/,""); print }' | tr -d ' ')
else
    echo "FATAL: No nvidia ML repository found.. exiting"
    exit 1
fi

# Download cuda repo deb and key from Nvidia
for files in ${latest_cuda_deb} ${latest_key}; do
    if [[ ! -f ${files} ]]; then
        wget -c ${nvidia_cuda_url}${files}
        RC=$?
        if [ $RC -ne 0 ]; then
            echo "ERROR: wget returned $RC: Unable to download ${nvidia_cuda_url}${files}"
	    exit 1
        fi
        
    fi
done

# Download the latest ML repo deb from Nvidia.
if [[ ! -f ${latest_ml_deb} ]]; then
    wget -c ${nvidia_ml_url}${latest_ml_deb}
    if [ $? -ne 0 ]; then
        echo "ERROR: wget returned $RC: Unable to download ${nvidia_ml_url}${files}"
        exit 1
    fi
fi

# Download the latest debs for Ubuntu and exit.
if [ "${download_only}" == "True" ]; then
    exit 0
fi

# Install latest repo, install cuda and libcudnn libraries.
dpkg -l "*cuda-repo-ubuntu*" &>/dev/null
if [ $? -ne 0 ]; then
    sudo apt-key add ${latest_key}
    sudo dpkg -i ${latest_cuda_deb} ${latest_ml_deb}
    sudo apt update
    if [ $? -ne 0 ]; then
        echo "FATAL: sudo apt update falied."
    exit 1
    fi
    # TODO: Need logic to install latest libcudnn
    sudo apt install -y cuda libcudnn7 libcudnn7-dev libnccl2 libnccl-dev
fi

# Setup systemd Nvidia persistence daemon.
if [[ ! -f /lib/systemd/system/nvidia-persistenced.service ]]; then
    sudo bash -c 'cat <<EOF >> /lib/systemd/system/nvidia-persistenced.service
[Unit]
Description=NVIDIA Persistence Daemon
Wants=syslog.target

[Service]
Type=forking
PIDFile=/var/run/nvidia-persistenced/nvidia-persistenced.pid
Restart=always
ExecStart=/usr/bin/nvidia-persistenced --verbose
ExecStopPost=/bin/rm -rf /var/run/nvidia-persistenced
TimeoutSec=300
EOF'
fi

# Disable CPU hotplug.
if [[ ! -f /lib/udev/rules.d/40-vm-hotadd.rules.bak ]]; then
    sudo sed -i.bak '/^SUBSYSTEM=="cpu"/s/^\(.*\)$/#\1/' \
	    /lib/udev/rules.d/40-vm-hotadd.rules
    sudo cp /lib/udev/rules.d/40-vm-hotadd.rules /etc/udev/rules.d/
    echo "export PATH=/usr/local/cuda/bin/\${PATH:+:\${PATH}}" >> $HOME/.profile
    sudo update-initramfs -u
    if [ $? -eq 0 ]; then
    echo " "
        echo "Reboot required.."
    echo " "
        read -p "reboot the system now? (y/n):" -n 1 -r 
    echo " "
        if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "*************************************************"
            echo "Your system will now reboot"
            echo "Run nvidia-smi to make sure your GPUs are listed"
        echo "*************************************************"
            sudo reboot
    else
        echo " "
        echo "**********************************************************"
        echo "A reboot is recommended to complete configuration"
        echo "After a reboot run nvidia-smi to make sure GPUs are listed"
        echo "**********************************************************"
        echo " "
        fi
    fi
fi
