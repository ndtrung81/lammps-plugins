# lammps-plugins
LAMMPS plugins

This project illustrates how to build LAMMPS plugins with Kokkos-derived pair styles.

## Prerequisite

LAMMPS is already built with KOKKOS suppport with CUDA backend

```
  git clone https://github.com/lammps/lammps.git
  cd lammps
  mkdir install
  mkdir build && cd build
  cmake ../cmake -C ../cmake/preset/basic.cmake \
     -DBUILD_MPI=on -DPKG_KOKKOS=on -DKokkos_ENABLE_CUDA -Kokkos_ARCH_AMPERE80=on -DCMAKE_INSTALL_PREFIX=../install
  make -j4
  make install
```

## Configure the build:

```
  git clone https://github.com/ndtrung81/lammps-plugins.git

  cd lammps-plugins
  mkdir build && cd build
  export LAMMPS_INSTALL_DIR=/home/ndtrung/Codes/lammps-git/install
  export LAMMPS_SOURCE_DIR=/home/ndtrung/Codes/lammps-git/src
  export LAMMPS_BUILD_DIR=/home/ndtrung/Codes/lammps-git/build
  export KOKKOS_ROOT=$LAMMPS_BUILD_DIR/cmake_packages/Kokkos

  cmake ../src -DLAMMPS_ROOT=$LAMMPS_INSTALL_DIR \
    -DKokkos_ROOT=$KOKKOS_ROOT \
    -DCMAKE_CXX_COMPILER=$LAMMPS_SOURCE_DIR/../lib/kokkos/bin/nvcc_wrapper \
    -DLAMMPS_SOURCE_DIR=$LAMMPS_SOURCE_DIR \
    -DLAMMPS_BUILD_DIR=$LAMMPS_BUILD_DIR
  make
```

The build when complete will generate `morse2plugin.so` and lj2plugin.so in the `build` folder.

The `examples` folder contains the input scripts to test the plugins.


