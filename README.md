# lammps-plugins

This project illustrates how to build LAMMPS plugins with Kokkos-derived pair and fix styles out of the LAMMPS KOKKOS source tree. This work could be helpful for numerous projects which require LAMMPS built with the KOKKOS package and then add their custom (pair) styles with Kokkos variants.  One workaround has been to copy the source code of the custom styles into the source tree of a copy of LAMMPS repo and patch the CMakeLists.txt with the new Kokkos pair styles. 

Specifically, we re-implement the pair style `lj/cut2/kk` and fix style `nve2/kk` which are essentially the copy of pair `lj/cut/kk` and fix `nve/kk` into separate plugins.  In the input script `in.lj` under `examples/` we load the plugins and use these styles with the KOKKOS package and `kk` suffix.

## Implementation notes

The script `cmake/Modules/FindLAMMPSTool.cmake` is based on the implementation by Pablo Zubieta [@pabloferz](https://github.com/pabloferz) in the [`lammps-dlext`](https://github.com/SSAGESLabs/lammps-dlext) project to detect LAMMPS and KOKKOS targets. This script finds the LAMMPS package, and retrieves the include directories, compile options and LAMMPS flags from the generated LAMMPS targets.

The script `cmake/CMakeLists.txt` is based on the version provided by `examples/plugins` in the LAMMPS repo.

Comments and suggestions via pull requests are welcome.

## Prerequisite

LAMMPS should already be built with KOKKOS suppport with CUDA backend (optional but recommended):

```
  git clone https://github.com/lammps/lammps.git
  cd lammps
  mkdir install
  cmake ../cmake -B build -C ../cmake/preset/basic.cmake -DBUILD_MPI=on -DPKG_PLUGIN=on \
       -DPKG_KOKKOS=on -DKokkos_ENABLE_CUDA -Kokkos_ARCH_AMPERE80=on \
       -DCMAKE_INSTALL_PREFIX=../install
  cmake --build build -j4
  make install
```

The installation folder `CMAKE_INSTALL_PREFIX` and the `make install` step are needed for the plugin CMake build to find `LAMMPS_Targets.cmake`, `LAMMPSConfig.cmake` and `LAMMPSConfigVersion.cmake`.

## Download and build the plugins

```
  git clone https://github.com/ndtrung81/lammps-plugins.git
  cd lammps-plugins

  export LAMMPS_INSTALL_DIR=/path/to/lammps/install
  export LAMMPS_SOURCE_DIR=/path/to/lammps/src

  cmake -B build . -DLAMMPS_ROOT=$LAMMPS_INSTALL_DIR/lib/cmake/LAMMPS \
       -DLAMMPS_SOURCE_DIR=$LAMMPS_SOURCE_DIR -DKokkos_ENABLE_CUDA=on -DKokkos_ARCH_AMPERE80=on
  cmake --build build
```

Only `LAMMPS_ROOT` (the install tree) and `LAMMPS_SOURCE_DIR` are required; the
LAMMPS *build* directory is not needed. The Kokkos sources are taken from
`$LAMMPS_SOURCE_DIR/../lib/kokkos`, i.e. the very same Kokkos that was compiled
into `liblammps`, so the Kokkos version can never drift.

You still have to pass the same Kokkos **backend and architecture** that LAMMPS
was built with (`-DKokkos_ENABLE_CUDA=on -DKokkos_ARCH_AMPERE80=on` above). The
remaining settings are read out of the installed `lmp` binary automatically:

```
  $ lmp -h
  KOKKOS package API: CUDA Serial
  KOKKOS package precision: double
  KOKKOS package view layout: legacy
  Kokkos library version: 5.1.99
```

From this the build derives `Kokkos_ENABLE_IMPL_VIEW_LEGACY`, `LMP_KOKKOS_<PREC>`
and `LMP_KOKKOS_LAYOUT_<LAYOUT>`, and it aborts if the Kokkos version or any
enabled backend disagrees with `liblammps`.

**Why this matters.** Kokkos configuration macros do not take part in C++ name
mangling. A plugin compiled against a differently configured Kokkos therefore
compiles and links without a single warning, and then segfaults at run time --
typically inside `Kokkos::Impl::SharedAllocationRecord<void,void>::increment`,
as soon as a plugin style touches a Kokkos object owned by `liblammps`. The
usual culprit is `Kokkos_ENABLE_IMPL_VIEW_LEGACY`, which LAMMPS forces ON while
Kokkos itself defaults to OFF; the two settings give `Kokkos::View` different
sizes, which shifts every `DualView` member of `AtomKokkos`. This is why the
plugins must never be built against a stand-alone Kokkos.

If you also have the LAMMPS build directory at hand, pass `-DLAMMPS_BUILD_DIR=`
to enable one extra check: the generated `KokkosCore_config.h` is then compared
byte for byte against the one that went into `liblammps`.

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


