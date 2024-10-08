# lammps-plugins

This project illustrates how to build LAMMPS plugins with Kokkos-derived pair and fix styles out of the LAMMPS KOKKOS source tree. This work could be helpful for numerous projects which require LAMMPS built with the KOKKOS package and then add their custom (pair) styles with Kokkos variants.  One workaround has been to copy the source code of the custom styles into the source tree of a copy of LAMMPS repo and patch the CMakeLists.txt with the new Kokkos pair styles. 

Specifically, we re-implement the pair style `lj/cut2/kk` and fix style `nve2/kk` which are essentially the copy of pair `lj/cut/kk` and fix `nve/kk` into separate plugins.  In the input script `in.lj` under `examples/` we load the plugins and use these styles with the KOKKOS package and `kk` suffix.

## Implementation notes

The script `cmake/Modules/FindLAMMPSTool.cmake` is based on the implementation by @pabloferz in the project [`lammps-dlext`](https://github.com/SSAGESLabs/lammps-dlext) to detect LAMMPS and KOKKOS targets. This script finds the LAMMPS package, and retrieves the include directories, compile options and LAMMPS flags from the generated LAMMPS targets.

The script `cmake/CMakeLists.txt` is based on the version provided by `examples/plugins` in the LAMMPS repo.

Comments and suggestions via pull requests are welcome.

## Prerequisite

LAMMPS should already be built with KOKKOS suppport with CUDA backend (optional but recommended):

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

The installation folder `CMAKE_INSTALL_PREFIX` and the `make install` step are needed for the plugin CMake build to find `LAMMPS_Targets.cmake`, `LAMMPSConfig.cmake` and `LAMMPSConfigVersion.cmake`.

Without the `make install` step,  `LAMMPS_Targets.cmake` is buried under a temporary folder under `build/CMakeFiles/Export`.

The KOKKOS CMake configuration and generated targets are available under `build/cmake_packages/Kokkos` (see below).

## Download and build the plugins

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
  $LAMMPS_INSTALL_DIR/bin/lmp -in in.lj -k on g 1 -sf kk
```

where the `in.lj` script loads the plugins and uses the pair and fix styles

```
plugin          load /path/to/lammps-plugins/build/lj2plugin.so
plugin          load /path/to/lammps-plugins/build/nve2plugin.so

pair_style      lj/cut2 2.5
pair_coeff      * * 1.0 1.0

fix             1 all nve2
```

Here `-k on g 1` is for the CUDA backend of KOKKOS. If you built KOKKOS with OpenMP backend, then you need to switch to something like `-k on t 2`.


