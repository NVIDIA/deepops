Software modules for Slurm clusters
===================================

Slurm clusters will frequently provide a bare-metal development environment in the form of "Environment Modules".
Enviroment Modules provide a convenient way to dynamically change the user's environment variables, such as `PATH` or `LD_LIBRARY_PATH`, to enable use of software installed in different locations.
This makes it easy to install multiple versions of the same software package and dynamically switch between them, such as different versions of CUDA or OpenMPI.

DeepOps installs the Lmod tool for managing your Environment Modules.
The [Lmod documentation](https://lmod.readthedocs.io/en/latest/) provides more information on using Lmod and writing Modules.

DeepOps also provides tooling for managing Environment Modules with two different frameworks: EasyBuild and Spack.
These tools provide a selection of tested build recipes for common development tools and scientific software packages,
making it easier to install software without a tedious manual build process.


## Installing Spack

[Spack](https://spack.io/) is a package manager for supercomputers, Linux, and MacOS which makes installing scientific software easy.

To install Spack using DeepOps, you can run:

```bash
ansible-playbook -l slurm-cluster playbooks/slurm-cluster/spack-modules.yml
```

### Configuration

* `spack_install_dir`: Controls the directory where Spack is installed. This should be a shared filesystem visible on all nodes in the cluster (for example, using NFS). The default is `/sw/spack`.
* `spack_build_packages`: Controls whether to build a default set of packages when installing Spack. Defaults to `false`.
* `spack_default_packages`: List of default packages to build, if `spack_build_packages` is `true`. The default value for this can be found in `config.example/group_vars/slurm-cluster.yml`.

### Usage

Once you have installed Spack, you can view the list of installed Environment Modules using the `module avail` command:

```bash
vagrant@virtual-login01:~$ module avail

------------------------------------------- /sw/spack/share/spack/modules/linux-ubuntu18.04-ivybridge --------------------------------------------
   autoconf-2.69-gcc-7.5.0-hfxfrih          libsigsegv-2.12-gcc-7.5.0-2yve3ej    perl-5.30.3-gcc-7.5.0-khsv2dq
   automake-1.16.2-gcc-7.5.0-j5wdstd        libtool-2.4.6-gcc-7.5.0-lec45xk      pkgconf-1.7.3-gcc-7.5.0-zmzhxvk
   cuda-10.2.89-gcc-7.5.0-sozilk3           libxml2-2.9.10-gcc-7.5.0-nxbegjt     readline-8.0-gcc-7.5.0-mnwvfzz
   gdbm-1.18.1-gcc-7.5.0-4nm26e5            m4-1.4.18-gcc-7.5.0-6uxhjm6          util-macros-1.19.1-gcc-7.5.0-7katknz
   hwloc-1.11.11-gcc-7.5.0-ahecdai          ncurses-6.2-gcc-7.5.0-ucxzuau        xz-5.2.5-gcc-7.5.0-g6ssadh
   libiconv-1.16-gcc-7.5.0-pndwbk6          numactl-2.0.12-gcc-7.5.0-qmslmbp     zlib-1.2.11-gcc-7.5.0-dsnnbcq
   libpciaccess-0.13.5-gcc-7.5.0-ynb22rn    openmpi-3.1.6-gcc-7.5.0-dpwfhsq

Use "module spider" to find all possible modules.
Use "module keyword key1 key2 ..." to search for all possible modules matching any of the "keys".
```

You can then load a chosen module using `module load`.
Loading a module will change your active environment variables (such as `PATH`) to add the software package in question to your environment.

```bash
vagrant@virtual-login01:~$ module load cuda-10.2.89-gcc-7.5.0-sozilk3
vagrant@virtual-login01:~$ which nvcc
/sw/spack/opt/spack/linux-ubuntu18.04-ivybridge/gcc-7.5.0/cuda-10.2.89-sozilk3ahqmsg3nndyifhv7hhw2j6cgt/bin/nvcc
```

In addition to using Environment Modules directly, Spack also provides a mechanism to load and unload modules directly using the `spack` command.

```bash
vagrant@virtual-login01:~$ spack find
==> 20 installed packages
-- linux-ubuntu18.04-ivybridge / gcc@7.5.0 ----------------------
autoconf@2.69    gdbm@1.18.1    libpciaccess@0.13.5  libxml2@2.9.10  numactl@2.0.12  pkgconf@1.7.3       xz@5.2.5
automake@1.16.2  hwloc@1.11.11  libsigsegv@2.12      m4@1.4.18       openmpi@3.1.6   readline@8.0        zlib@1.2.11
cuda@10.2.89     libiconv@1.16  libtool@2.4.6        ncurses@6.2     perl@5.30.3     util-macros@1.19.1
vagrant@virtual-login01:~$ spack load cuda@10.2.89
vagrant@virtual-login01:~$ which nvcc
/sw/spack/opt/spack/linux-ubuntu18.04-ivybridge/gcc-7.5.0/cuda-10.2.89-sozilk3ahqmsg3nndyifhv7hhw2j6cgt/bin/nvcc
```

For more information on using Spack, see the [Spack documentation](https://spack.readthedocs.io/en/latest/).

### Architecture-specific builds

It's important to note that, by default, Spack will detect and optimize for the specific microarchitecture where packages are being built.
This will likely improve performance for many packages!
However, if you run multiple CPU microarchitectures on your cluster, you may wish to build the same packages multiple times, once on each architecture.

If you prefer to avoid optimizing for a specific microarchitecture, you can target the generic `x86_64` architecture by adding `target=x86_64` to the spec.
This will produce less-optimized but more generic builds.


## Installing EasyBuild

[EasyBuild](https://easybuild.readthedocs.io/en/latest/) is a software build and installation framework that allows you to manage (scientific) software on HPC systems in an efficient way.

To install EasyBuild using DeepOps, you can run:

```bash
ansible-playbook -l slurm-cluster playbooks/slurm-cluster/easybuild-modules.yml
```

### Configuration

* `sm_prefix`: Root path for installing modules. Defaults to `/sw`.
* `sm_install_default`: Controls whether to install a default set of packages when installing EasyBuild. Defaults to `true`.
* `sm_files_url`: Git repository to find default easyconfigs to install. Default is `https://github.com/DeepOps/easybuild_files.git` 

### Usage

Once you have installed EasyBuild, you can view the list of installed Environment Modules using the `module avail` command:

```bash
vagrant@virtual-login01:~$ module avail

------------------------------------------------------------------------------------------------- /sw/modules/all --------------------------------------------------------------------------------------------------
   Bison/3.3.2    EasyBuild/4.2.2 (L)    M4/1.4.18    binutils/2.32    flex/2.6.4    help2man/1.47.4    zlib/1.2.11

  Where:
   L:  Module is loaded

Use "module spider" to find all possible modules.
Use "module keyword key1 key2 ..." to search for all possible modules matching any of the "keys".
```

You can then load a chosen module using `module load`.
Loading a module will change your active environment variables (such as `PATH`) to add the software package in question to your environment.

```bash
vagrant@virtual-login01:~$ module load flex/2.6.4
vagrant@virtual-login01:~$ which flex
/sw/software/flex/2.6.4/bin/flex
```

For more information on using EasyBuild, see the [EasyBuild documentation](https://easybuild.readthedocs.io/en/latest/).
