# lammps-plugins

This project illustrates how to build LAMMPS plugins with Kokkos-derived pair and fix styles out of the LAMMPS KOKKOS source tree. This work could be helpful for numerous projects which require LAMMPS built with the KOKKOS package and then add their custom (pair) styles with Kokkos variants.  One workaround has been to copy the source code of the custom styles into the source tree of a copy of LAMMPS repo and patch the CMakeLists.txt with the new Kokkos pair styles. 

Specifically, we re-implement the pair style `lj/cut2/kk` and fix style `nve2/kk` which are essentially the copy of pair `lj/cut/kk` and fix `nve/kk` into separate plugins.  In the input script `in.lj` under `examples/` we load the plugins and use these styles with the KOKKOS package and `kk` suffix.

## Implementation notes

The script `cmake/Modules/FindLAMMPSTools.cmake` is based on the implementation by Pablo Zubieta [@pabloferz](https://github.com/pabloferz) in the [`lammps-dlext`](https://github.com/SSAGESLabs/lammps-dlext) project to detect LAMMPS and KOKKOS targets. This script finds the LAMMPS package, and retrieves the include directories, compile options and LAMMPS flags from the generated LAMMPS targets.

The top-level `CMakeLists.txt` is based on the version provided by `examples/plugins` in the LAMMPS repo.

Comments and suggestions via pull requests are welcome.

## Prerequisite

LAMMPS should already be built with KOKKOS suppport with CUDA backend (optional but recommended):

```
  git clone https://github.com/lammps/lammps.git
  cd lammps
  mkdir install
  cmake ../cmake -B build -C ../cmake/preset/basic.cmake -DBUILD_MPI=on -DPKG_PLUGIN=on \
       -DPKG_KOKKOS=on -DKokkos_ENABLE_CUDA=on -DKokkos_ARCH_AMPERE80=on \
       -DCMAKE_INSTALL_PREFIX=../install
  cmake --build build -j4
  make install
```

The installation folder `CMAKE_INSTALL_PREFIX` and the `make install` step are needed for the plugin CMake build to find `LAMMPS_Targets.cmake`, `LAMMPSConfig.cmake` and `LAMMPSConfigVersion.cmake`.

The command above uses the Kokkos bundled with LAMMPS under `lib/kokkos`. LAMMPS
can also be built against a Kokkos installed outside of its source tree, with
`-DEXTERNAL_KOKKOS=yes -DKokkos_ROOT=/path/to/kokkos/install`. Both cases are
supported by the plugin build; see below.

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

`LAMMPS_ROOT` (the install tree) and `LAMMPS_SOURCE_DIR` are always required.
Where Kokkos itself comes from depends on how LAMMPS was built, and both
possibilities are supported.

### Case 1: Kokkos provided under the LAMMPS repo

This is the default LAMMPS build (`EXTERNAL_KOKKOS=off`), where the KOKKOS
package is compiled from the Kokkos sources bundled at `<lammps>/lib/kokkos`.
Nothing beyond the command line above is needed: the plugins are configured
against `$LAMMPS_SOURCE_DIR/../lib/kokkos`, i.e. the very same Kokkos that was
compiled into `liblammps`, so the Kokkos version can never drift, and the LAMMPS
*build* directory is not required.

If you still have the LAMMPS build directory around, you can point the plugins
at the Kokkos CMake package that build exported instead, which is exact rather
than reconstructed:

```
  cmake -B build . -DLAMMPS_ROOT=$LAMMPS_INSTALL_DIR/lib/cmake/LAMMPS \
       -DLAMMPS_SOURCE_DIR=$LAMMPS_SOURCE_DIR \
       -DLAMMPS_BUILD_DIR=/path/to/lammps/build
```

`LAMMPS_BUILD_DIR` is worth passing in either case: it enables a full comparison
of the generated `KokkosCore_config.h` against the one that went into
`liblammps`, which is the only completely airtight check.

### Case 2: Kokkos outside of the LAMMPS source tree

This is a LAMMPS built with `-DEXTERNAL_KOKKOS=yes -DKokkos_ROOT=<kokkos install>`
against a Kokkos installed somewhere else. Point the plugins at that same
installation:

```
  cmake -B build . -DLAMMPS_ROOT=$LAMMPS_INSTALL_DIR/lib/cmake/LAMMPS \
       -DLAMMPS_SOURCE_DIR=$LAMMPS_SOURCE_DIR \
       -DKokkos_ROOT=/path/to/kokkos/install
```

The Kokkos backend and architecture then come from that installation and do not
have to be repeated on the command line.

### Selecting the mode explicitly

`LAMMPS_KOKKOS_MODE` overrides the automatic choice:

| value     | meaning                                                                        |
|-----------|--------------------------------------------------------------------------------|
| `auto`    | default: `package` if `Kokkos_ROOT`/`Kokkos_DIR` is set or `LAMMPS_BUILD_DIR` has one, otherwise `source` |
| `source`  | `add_subdirectory()` the Kokkos sources at `<lammps>/lib/kokkos` (case 1)        |
| `package` | `find_package(Kokkos)`, i.e. an already configured Kokkos (case 2)               |
| `none`    | do not look for Kokkos; only `morse2plugin.so` is built                          |

Use `LAMMPS_KOKKOS_DIR` to point `source` mode at a Kokkos source tree other than
`$LAMMPS_SOURCE_DIR/../lib/kokkos`.

### What the build checks, and why

In `source` mode you have to pass the same Kokkos **backend and architecture**
that LAMMPS was built with (`-DKokkos_ENABLE_CUDA=on -DKokkos_ARCH_AMPERE80=on`
above). The remaining settings are read out of the installed `lmp` binary
automatically:

```
  $ lmp -h
  KOKKOS package API: CUDA Serial
  KOKKOS package precision: double
  KOKKOS package view layout: legacy
  Kokkos library version: 5.1.99
```

From this the build derives `LMP_KOKKOS_<PREC>` and `LMP_KOKKOS_LAYOUT_<LAYOUT>`,
and it aborts if the Kokkos version or any enabled backend disagrees with
`liblammps` -- in either mode.

**Why this matters.** Kokkos configuration macros do not take part in C++ name
mangling. A plugin compiled against a differently configured Kokkos therefore
compiles and links without a single warning, and then segfaults at run time --
typically inside `Kokkos::Impl::SharedAllocationRecord<void,void>::increment`,
as soon as a plugin style touches a Kokkos object owned by `liblammps`. The
usual culprit is `Kokkos_ENABLE_IMPL_VIEW_LEGACY`, which LAMMPS forces ON while
Kokkos itself defaults to OFF; the two settings give `Kokkos::View` different
sizes, which shifts every `DualView` member of `AtomKokkos`. This is why the
plugins must never be built against an arbitrary stand-alone Kokkos.

`Kokkos_ENABLE_IMPL_VIEW_LEGACY` is the one setting the installed LAMMPS does
not report (LAMMPS keeps it separate from its own `KOKKOS_LAYOUT`), so `source`
mode reads it from `LAMMPS_BUILD_DIR` when available and otherwise assumes the
LAMMPS default (ON). Set `LAMMPS_KOKKOS_VIEW_LEGACY=on|off` if your LAMMPS was
built the other way round.

If the configuration comparison against `LAMMPS_BUILD_DIR` flags an option you
know cannot affect the ABI, add it to `LAMMPS_KOKKOS_CONFIG_IGNORE` (which
already contains `KOKKOS_ENABLE_DEPRECATION_WARNINGS`).

The build when complete will generate `morse2plugin.so`, `lj2plugin.so` and `nve2plugin.so` in the `build` folder. Without Kokkos only `morse2plugin.so` is built, since the other two carry the Kokkos variants of their styles.

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


