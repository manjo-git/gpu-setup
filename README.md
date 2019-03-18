# Install Nvidia GPU drivers on Ubuntu
This is a helper script to install Nvidia's GPU drivers on Ubuntu, supports
AMD64 and ppc64el architechtures. This script was tested on ppc64el arch and
works on 18.04 or newer Ubuntu releases. *(Ubuntu 18.04/18.10 please ensure 
you have the latest linux-firmware package installed for GPU support).*

## For usage:
```$ ./ubuntu-install-nvidia.sh -h | --help```

# Install drivers and cuda
```$ ./ubuntu-install-nvidia.sh ```
This script will download the latest cuda repo and key published by Nvidia,
set up the repository, and install the drivers, cuda libraries and tool.
After installation is complete and system reboot, run nvidia-smi command
to list the GPUs.

```
 $ nvidia-smi 
Mon Mar 18 19:21:09 2019       
+-----------------------------------------------------------------------------+
| NVIDIA-SMI 418.39       Driver Version: 418.39       CUDA Version: 10.1     |
|-------------------------------+----------------------+----------------------+
| GPU  Name        Persistence-M| Bus-Id        Disp.A | Volatile Uncorr. ECC |
| Fan  Temp  Perf  Pwr:Usage/Cap|         Memory-Usage | GPU-Util  Compute M. |
|===============================+======================+======================|
|   0  Tesla V100-SXM2...  On   | 00000004:04:00.0 Off |                    0 |
| N/A   29C    P0    37W / 300W |      0MiB / 16130MiB |      0%      Default |
+-------------------------------+----------------------+----------------------+
|   1  Tesla V100-SXM2...  On   | 00000004:05:00.0 Off |                    0 |
| N/A   32C    P0    37W / 300W |      0MiB / 16130MiB |      0%      Default |
+-------------------------------+----------------------+----------------------+
|   2  Tesla V100-SXM2...  On   | 00000035:03:00.0 Off |                    0 |
| N/A   30C    P0    35W / 300W |      0MiB / 16130MiB |      0%      Default |
+-------------------------------+----------------------+----------------------+
|   3  Tesla V100-SXM2...  On   | 00000035:04:00.0 Off |                    0 |
| N/A   32C    P0    39W / 300W |      0MiB / 16130MiB |      0%      Default |
+-------------------------------+----------------------+----------------------+
                                                                               
+-----------------------------------------------------------------------------+
| Processes:                                                       GPU Memory |
|  GPU       PID   Type   Process name                             Usage      |
|=============================================================================|
|  No running processes found                                                 |
+-----------------------------------------------------------------------------+
```

# Install pytorch on ppc64el.
pytorch is not packaged for ppc64el in Ubuntu, you will need to build it from
source as follows:

## Install pre-requisites
```
 $ sudo apt install python3-pip libffi-dev libssl-dev
 $ pip3 install certifi cffi numpy setuptools wheel pip pyyaml Collecting certifi
```

## Build and install pytorch
```
 $ git clone --recursive https://github.com/pytorch/pytorch ~/pytorch
 $ cd pytorch
 $ python3 setup.py bdist_wheel
 $ pip3 install torch-1.1.0a0+670f509-cp36-cp36m-linux_ppc64le.whl
```
If you get pip3 errors on installing the wheel, do the following:
```$ python3 -m pip uninstall pip```

## Run pytorch examples.
 - Download pytorch examples 
```
 $ git clone https://github.com/pytorch/examples.git ~/pyt-examples
 $ cd ~/pyt-examples/word_language_model
```
 - Add the following to main.py as follows for parallel runs on GPU.
```
  parser.add_argument("--local_rank", type=int)

  # Set your device to local rank
  torch.cuda.set_device(args.local_rank) 
```
 - Run the testcase as follows, and run ```$ watch nvidia-smi``` on a 
   seperate terminal.
``` 
 $ python3 -m torch.distributed.launch --nproc_per_node=4 main.py --cuda --epochs 6
 $ python3 -m torch.distributed.launch --nproc_per_node=4 main.py --cuda --epochs 6 --tied
 $ python3 -m torch.distributed.launch --nproc_per_node=4 main.py --cuda --tied
 $ python3 -m torch.distributed.launch --nproc_per_node=4 generate.py --cuda
```
