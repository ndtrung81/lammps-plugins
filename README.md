# lammps-plugins

This project illustrates how to build LAMMPS plugins with Kokkos-derived pair styles out of the LAMMPS KOKKOS source tree.

## Prerequisite

LAMMPS is already built with KOKKOS suppport with CUDA backend

```
  git clone https://github.com/lammps/lammps.git
  cd lammps
  mkdir install
  mkdir build && cd build
  cmake ../cmake -C ../cmake/preset/basic.cmake -DBUILD_MPI=on -DPKG_PLUGIN=on \
       -DPKG_KOKKOS=on -DKokkos_ENABLE_CUDA -Kokkos_ARCH_AMPERE80=on \
       -DCMAKE_INSTALL_PREFIX=../install
  make -j4
  make install
```

The installation folder `CMAKE_INSTALL_PREFIX` is needed for the plugin CMake build to find `LAMMPS_Targets.cmake`, `LAMMPSConfig.cmake` and `LAMMPSConfigVersion.cmake`.

Without the `make install` step  `LAMMPS_Targets.cmake` is buried under a temporary folder under `build/CMakeFiles/Export`.

## Download and build the plugin


```
  git clone https://github.com/ndtrung81/lammps-plugins.git

  cd lammps-plugins
  mkdir build && cd build

  export LAMMPS_INSTALL_DIR=/path/to/lammps/install
  export LAMMPS_SOURCE_DIR=/path/to/lammps/src
  export LAMMPS_BUILD_DIR=/path/to/lammps/build
  export KOKKOS_ROOT=$LAMMPS_BUILD_DIR/cmake_packages/Kokkos

  cmake ../cmake -DLAMMPS_ROOT=$LAMMPS_INSTALL_DIR \
    -DKokkos_ROOT=$KOKKOS_ROOT \
    -DCMAKE_CXX_COMPILER=$LAMMPS_SOURCE_DIR/../lib/kokkos/bin/nvcc_wrapper \
    -DLAMMPS_SOURCE_DIR=$LAMMPS_SOURCE_DIR \
    -DLAMMPS_BUILD_DIR=$LAMMPS_BUILD_DIR
  make
```


The variable `KOKKOS_ROOT` is for the location where the Kokkos cmake settings `KokkosConfig.cmake`, `KokkosConfigCommon.cmake`, `KokkosConfigVersion.cmake` and `KokkosTargets.cmake` are located.

The build when complete will generate `morse2plugin.so`, `lj2plugin.so` and `nve2plugin.so` in the `build` folder.

## Test

The `examples` folder contains the input scripts to test the plugins.

```
  cd examples/
  LAMMPS_INSTALL_DIR/bin/lmp -in in.lj -k on g 1 -sf kk
```

where the `in.lj` script loads the plugin with the command and uses the pair styles

```
plugin          load /path/to/lammps-plugins/build/lj2plugin.so
plugin          load /path/to/lammps-plugins/build/nve2plugin.so

pair_style      lj/cut2 2.5
pair_coeff      * * 1.0 1.0

fix             1 all nve2
```


