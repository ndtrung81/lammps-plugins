# Global requirements
# -------------------

find_package(Git REQUIRED)


# Global variables
# ----------------

set(LAMMPS_URL "https://github.com/lammps/lammps.git")

if(NOT LAMMPS_ROOT)
    if(DEFINED ENV{LAMMPS_ROOT})
        set(LAMMPS_ROOT $ENV{LAMMPS_ROOT})
    elseif(CMAKE_PREFIX_PATH)
        find_path(LAMMPS_ROOT
            NAMES LAMMPS_Targets.cmake
            HINTS ${CMAKE_PREFIX_PATH}
            PATH_SUFFIXES LAMMPS
        )
        if("${LAMMPS_ROOT}" STREQUAL "LAMMPS_ROOT-NOTFOUND")
            message(FATAL_ERROR
                "Unable to find LAMMPS. Try setting the CMake "
                "variables LAMMPS_ROOT or CMAKE_PREFIX_PATH."
            )
        endif()
    endif()
endif()


# Utility functions
# -----------------

#     fetch_lammps
#
# Given a LAMMPS `tag` use CPM to retrieve the code for that release.
function(fetch_lammps tag)
    # We use lowercase lammps to avoid clashes with the main library
    CPMAddPackage(NAME lammps
        GIT_REPOSITORY  ${LAMMPS_URL}
        GIT_TAG         ${tag}
        GIT_SHALLOW     TRUE
        DOWNLOAD_ONLY   TRUE
    )
    if(lammps_ADDED)
        set(lammps_SOURCE_DIR ${lammps_SOURCE_DIR} PARENT_SCOPE)
    else()
        message(WARNING "Failed to download LAMMPS source")
    endif()
endfunction()

#     find_executable
#
# Looks for the IMPORTED_LOCATION of the first available IMPORTED_LOCATION_<config>
# for the given target and sets a variable `varname` on the parent scope.
function(find_executable target varname)
    get_target_property(var ${target} IMPORTED_LOCATION)
    if("${var}" STREQUAL "var-NOTFOUND")
        get_target_property(configs ${target} IMPORTED_CONFIGURATIONS)
        list(GET configs 0 config)
        get_target_property(var ${target} "IMPORTED_LOCATION_${config}")
    endif()
    set(${varname} ${var} PARENT_SCOPE)
endfunction()

#     find_lammps_cxx_compiler(path)
#
# Look for the  `nvcc_wrapper` shipped by lammps within the specified `path` and,
# if found, set its location to `LAMMPS_CXX_COMPILER` in the parent scope.
function(find_lammps_cxx_compiler path)
    get_filename_component(NVCC_WRAPPER "${path}/nvcc_wrapper" ABSOLUTE)
    if(EXISTS ${NVCC_WRAPPER})
        set(LAMMPS_CXX_COMPILER ${NVCC_WRAPPER} PARENT_SCOPE)
    endif()
endfunction()

#     get_lammps_tag(version)
#
# Given a LAMMPS `version` as reported to CMake or Python, sets `LAMMPS_tag` in the
# parent scope to the latest git tag matching this version within the LAMMPS repo.
function(get_lammps_tag version)
    # Try to get the git tag or commit directly from LAMMPS' help
    execute_process(
        COMMAND ${LAMMPS_EXECUTABLE} -h
        RESULT_VARIABLE exit_code
        OUTPUT_VARIABLE LAMMPS_help
        ERROR_QUIET
    )

    if(exit_code EQUAL 0)
        string(REGEX MATCH "Git info [^ ]+ / ([^)]+)" _ "${LAMMPS_help}")

        if(
            (NOT ("${CMAKE_MATCH_1}" STREQUAL "")) AND
            (NOT ("${CMAKE_MATCH_1}" STREQUAL "(unknown)"))
        )
            set(LAMMPS_tag "${CMAKE_MATCH_1}" PARENT_SCOPE)
            return()
        endif()
    endif()

    # If we're unable to find it we search for the last tag that matches
    # the provided `version`.
    set(MONTHS _ Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)

    # Newer LAMMPS reports a version like "2026.7.4.99" rather than a bare
    # YYYYMMDD stamp.  Only the YYYYMMDD form can be mapped onto a git tag, so
    # bail out quietly instead of erroring out in list(GET) below.
    if(NOT "${version}" MATCHES "^[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]")
        set(LAMMPS_tag "" PARENT_SCOPE)
        return()
    endif()

    string(REGEX MATCH "([0-9][0-9][0-9][0-9])([0-9][0-9])([0-9][0-9]).*" _ "${version}")
    set(year ${CMAKE_MATCH_1})
    list(GET MONTHS ${CMAKE_MATCH_2} month)
    math(EXPR day ${CMAKE_MATCH_3})
    set(pattern "*${day}${month}${year}*")

    execute_process(
        COMMAND ${GIT_EXECUTABLE} ls-remote --tags --refs ${LAMMPS_URL} ${pattern}
        RESULT_VARIABLE exit_code  # TODO: use this to check if it fails and inform the user
        OUTPUT_VARIABLE git_tags
        ERROR_QUIET
        OUTPUT_STRIP_TRAILING_WHITESPACE
    )

    string(REGEX MATCH ".*/(.+)$" _ "${git_tags}")

    set(LAMMPS_tag "${CMAKE_MATCH_1}" PARENT_SCOPE)
endfunction()

#     get_lammps_version(path)
#
# Tries loading the LAMMPSConfigVersion.cmake from within `path`,
# and sets LAMMPS_VERSION in the parent scope.
function(get_lammps_version path)
    if(EXISTS "${path}/LAMMPSConfigVersion.cmake")
        include("${path}/LAMMPSConfigVersion.cmake")
    endif()
    set(LAMMPS_VERSION "${PACKAGE_VERSION}" PARENT_SCOPE)
endfunction()

#     find_lammps()
#
# Macro equivalent to find_package(LAMMPS QUIET), but avoids looking for MPI,
# which is performed separately. It also looks for the NVCC wrapper that
# comes with LAMMPS and tries to find an appropriate git tag matching the
# LAMMPS version.
macro(find_lammps)
    include("${LAMMPS_ROOT}/LAMMPS_Targets.cmake")
    find_executable(LAMMPS::lmp "LAMMPS_EXECUTABLE")
    find_lammps_cxx_compiler("${LAMMPS_EXECUTABLE}/..")
    get_lammps_version(${LAMMPS_ROOT})
    get_lammps_tag(${LAMMPS_VERSION})
endmacro()

#     append_paths(list)
#
# Given a list and any number of file names, appends to the list
# the absolute paths to the provided files.
function(append_paths list)
    list(POP_FRONT ARGV)
    foreach(file ${ARGV})
        get_filename_component(path ${file} ABSOLUTE)
        set(${list} ${${list}} ${path})
    endforeach()
    set(${list} ${${list}} PARENT_SCOPE)
endfunction()

#    copy_target_property
#
# Given a source target `src` and a destination target `dst`, reads the value of the
# `property` in `src` and if found, sets it in `dst`.
function(copy_target_property src dst property)
    get_target_property(var ${src} ${property})
    if(NOT ("${var}" STREQUAL "var-NOTFOUND"))
        set_target_properties(${dst} PROPERTIES ${property} "${var}")
    endif()
endfunction()

#    copy_target_property_fallback
#
# Given a source target `src` and a destination target `dst`, reads the value of the
# `property` in `src` and only if not found, sets it in `dst` using the corresponding
# value from the configuration `config` provided.
function(copy_target_property_fallback src dst property config)
    get_target_property(var ${src} ${property})
    if("${var}" STREQUAL "var-NOTFOUND")
        get_target_property(var ${src} "${property}_${config}")
        set_target_properties(${dst} PROPERTIES ${property} "${var}")
    endif()
endfunction()

#    copy_target_property
#
# Given a source target `src` and a destination target `dst`, finds all the
# IMPORTED_CONFIGURATIONS in `src` and for each of them tries to extract the value of the
# corresponding `property` in `src`, and if found, sets it in `dst`.
function(copy_target_property_configs src dst property)
    get_target_property(configs ${src} IMPORTED_CONFIGURATIONS)
    list(LENGTH configs nconfigs)

    if("${configs}" STREQUAL "configs-NOTFOUND")
        return()
    endif()

    if(${nconfigs})
        foreach(config ${configs})
            copy_target_property(${src} ${dst} "${property}_${config}")
        endforeach()
        # TODO: fix when multiple configurations are present
        # (we're assuming the first one is appropriate)
        list(GET configs 0 config)
        copy_target_property_fallback(${src} ${dst} ${property} ${config})
    endif()
endfunction()

#     set_python_module_path
#
# Tries finding the path where the python lammps module is installed and sets the
# variable `PYLAMMPS_PATH` to that path, otherwise `PYLAMMPS_PATH` will be empty.
function(set_python_module_path)
    find_package(Python QUIET COMPONENTS Interpreter)
    if(NOT (Python_FOUND AND Python_Interpreter_FOUND))
        message(FATAL_ERROR
            "Could not find Python interpreter, make sure it is installed and enabled"
        )
    endif()
    set(find_lammps_script "
from __future__ import print_function;
import os
try:
    import lammps
    print(os.path.dirname(lammps.__file__), end='')
except:
    print('', end='')"
    )
    set(find_liblammps_script "
from __future__ import print_function;
import os
try:
    import lammps
    lmp = lammps.lammps(cmdargs='-log none -screen none'.split())
    print(lmp.lib._name, end='')
except:
    print('', end='')"
    )
    execute_process(
        COMMAND ${Python_EXECUTABLE} -c "${find_lammps_script}"
        OUTPUT_VARIABLE PYLAMMPS_PATH
    )
    execute_process(
        COMMAND ${Python_EXECUTABLE} -c "${find_liblammps_script}"
        OUTPUT_VARIABLE PYLAMMPS_LIBRARY
    )
    if("${PYLAMMPS_PATH}" STREQUAL "" OR "${PYLAMMPS_LIBRARY}" STREQUAL "")
        unset(PYLAMMPS_LIBRARY)
        find_library(PYLAMMPS_LIBRARY
            NAMES lammps
            HINTS ${Python_SITELIB}
            PATH_SUFFIXES lammps
        )
        if("${PYLAMMPS_LIBRARY}" STREQUAL "PYLAMMPS_LIBRARY-NOTFOUND")
            message(FATAL_ERROR "Unable to locate LAMMPS python module")
        else()
            get_filename_component(PYLAMMPS_PATH "${PYLAMMPS_LIBRARY}" DIRECTORY)
        endif()
    endif()
    set(PYLAMMPS_PATH "${PYLAMMPS_PATH}" PARENT_SCOPE)
    set(PYLAMMPS_LIBRARY "${PYLAMMPS_LIBRARY}" PARENT_SCOPE)
endfunction()


# Setup LAMMPS
# ------------

# We use find_lammps() first instead of find_package(LAMMPS) to avoid finding
# MPI which requires CXX enabled, but we want to enable CXX after looking for
# the NVCC compiler wrapper that comes with LAMMPS.
find_lammps()

message(STATUS "Found LAMMPS at ${LAMMPS_ROOT} (version ${LAMMPS_VERSION})")

#fetch_lammps(${LAMMPS_tag})

# `fetch_lammps()` above is disabled, so `lammps_SOURCE_DIR` (the variable it
# would have set) is empty and paths built from it degenerate to "/src/...".
# Derive it from LAMMPS_SOURCE_DIR, which the user has to provide anyway.
if(NOT lammps_SOURCE_DIR AND LAMMPS_SOURCE_DIR)
    get_filename_component(lammps_SOURCE_DIR "${LAMMPS_SOURCE_DIR}/.." ABSOLUTE)
endif()

if(NOT CMAKE_BUILD_TYPE)
    if(${LAMMPS_VERSION} GREATER 20190618)
        set(CMAKE_BUILD_TYPE RelWithDebInfo CACHE STRING "Type of build" FORCE)
    else()
        set(CMAKE_BUILD_TYPE Release CACHE STRING "Type of build" FORCE)
    endif()
endif()

set(CMAKE_CXX_EXTENSIONS OFF CACHE FILEPATH "Use compiler extensions")
if(LAMMPS_CXX_COMPILER)
    set(CMAKE_CXX_COMPILER ${LAMMPS_CXX_COMPILER} CACHE FILEPATH "C++ compiler")
endif()

enable_language(CXX)

find_package(LAMMPS REQUIRED)

if(TARGET LAMMPS::mpi_stubs)  # LAMMPS was built without MPI support
    target_include_directories(LAMMPS::mpi_stubs SYSTEM INTERFACE
        "${lammps_SOURCE_DIR}/src/STUBS"
    )
else()
    find_package(MPI REQUIRED)
endif()

if(NOT LAMMPS_INSTALL_PREFIX)
    get_filename_component(LAMMPS_INSTALL_PREFIX "${LAMMPS_ROOT}/../../.." ABSOLUTE)
endif()

add_library(LAMMPS_src INTERFACE)
add_library(LAMMPS::src ALIAS LAMMPS_src)

target_include_directories(LAMMPS_src INTERFACE "${LAMMPS_SOURCE_DIR}")

# Kokkos
# ------
#
# The plugins must be compiled against the *same* Kokkos headers and the *same*
# Kokkos configuration that liblammps was built with.  Kokkos configuration
# macros do not take part in C++ name mangling, so a plugin built against a
# differently configured Kokkos still compiles and links without a single
# diagnostic and then segfaults at run time, typically inside
# Kokkos::Impl::SharedAllocationRecord<void,void>::increment, as soon as it
# touches a Kokkos object owned by liblammps.
#
# The worst offender is Kokkos_ENABLE_IMPL_VIEW_LEGACY: LAMMPS forces it ON
# while Kokkos itself defaults to OFF, and the two settings give Kokkos::View
# different sizes.  It is marked advanced in the LAMMPS build, so nobody would
# think to pass it by hand.
#
# Two ways of getting Kokkos are supported, matching the two ways LAMMPS itself
# can be built.  They are selected with LAMMPS_KOKKOS_MODE:
#
#   source   Take the Kokkos sources that ship *inside the LAMMPS repository*,
#            i.e. <lammps>/lib/kokkos, and add_subdirectory() them.  This is
#            the case when LAMMPS was built with its bundled Kokkos
#            (EXTERNAL_KOKKOS=off, the default).  Only LAMMPS_ROOT and
#            LAMMPS_SOURCE_DIR are needed -- no LAMMPS build directory -- and
#            the Kokkos version can never drift.
#
#   package  Take an already configured Kokkos CMake package with
#            find_package(Kokkos).  This is the case when LAMMPS was built
#            against a Kokkos living *outside of the LAMMPS source tree*
#            (-DEXTERNAL_KOKKOS=yes -DKokkos_ROOT=<kokkos install>); point
#            Kokkos_ROOT at that very same installation.  It also works with
#            the package that a bundled-Kokkos LAMMPS build exports to
#            <LAMMPS_BUILD_DIR>/cmake_packages/Kokkos.
#
#   none     Do not look for Kokkos; the Kokkos plugins are not built.
#
#   auto     (default) `package` when Kokkos_ROOT/Kokkos_DIR is set or
#            <LAMMPS_BUILD_DIR>/cmake_packages/Kokkos exists, otherwise
#            `source` when <lammps>/lib/kokkos is present, otherwise a plain
#            find_package(Kokkos) as a last resort.
#
# Whichever mode is used, the resulting Kokkos configuration is verified
# against the one reported by the installed `lmp` binary (version, enabled
# backends, view implementation), and -- when LAMMPS_BUILD_DIR is given -- the
# whole generated KokkosCore_config.h is compared with the one that went into
# liblammps, which is the only fully airtight check.

set(LAMMPS_KOKKOS_MODE "auto" CACHE STRING
    "Where to take Kokkos from: auto, source, package or none")
set_property(CACHE LAMMPS_KOKKOS_MODE PROPERTY STRINGS auto source package none)

# LAMMPS keeps its own view layout (KOKKOS_LAYOUT, reported by `lmp -h`) and the
# Kokkos view implementation (Kokkos_ENABLE_IMPL_VIEW_LEGACY, invisible from
# outside) as two independent options, so the latter cannot be recovered from
# the installed LAMMPS.  Default to the LAMMPS default (ON), read it out of
# LAMMPS_BUILD_DIR when that is available, and let the user override.
set(LAMMPS_KOKKOS_VIEW_LEGACY "auto" CACHE STRING
    "Kokkos_ENABLE_IMPL_VIEW_LEGACY that liblammps was built with: auto, on or off")
set_property(CACHE LAMMPS_KOKKOS_VIEW_LEGACY PROPERTY STRINGS auto on off)

# Kokkos configuration macros that are allowed to differ between the plugins and
# liblammps because they cannot change the ABI.  Extend it if the full
# configuration comparison below flags something you know to be harmless.
set(LAMMPS_KOKKOS_CONFIG_IGNORE "KOKKOS_ENABLE_DEPRECATION_WARNINGS" CACHE STRING
    "Kokkos configuration macros that may differ from liblammps")

#     probe_lammps_kokkos()
#
# Reads the KOKKOS settings straight out of the installed `lmp` binary.  `lmp -h`
# reports them from the "info" machinery without initialising Kokkos, so this
# also works on a build node that has no GPU:
#
#   KOKKOS package API: CUDA Serial
#   KOKKOS package precision: double
#   KOKKOS package view layout: legacy
#   Kokkos library version: 5.1.99
#
# Sets, in the parent scope: LAMMPS_KOKKOS_FOUND, LAMMPS_KOKKOS_VERSION,
# LAMMPS_KOKKOS_PREC, LAMMPS_KOKKOS_LAYOUT and LAMMPS_KOKKOS_API.
function(probe_lammps_kokkos)
    set(LAMMPS_KOKKOS_FOUND FALSE PARENT_SCOPE)

    if(NOT LAMMPS_EXECUTABLE OR NOT EXISTS "${LAMMPS_EXECUTABLE}")
        return()
    endif()

    # An installed lmp frequently has no RPATH to liblammps, so help it along.
    get_target_property(_lammps_lib LAMMPS::lammps IMPORTED_LOCATION)
    if(NOT _lammps_lib)
        get_target_property(_configs LAMMPS::lammps IMPORTED_CONFIGURATIONS)
        if(_configs)
            list(GET _configs 0 _config)
            get_target_property(_lammps_lib LAMMPS::lammps "IMPORTED_LOCATION_${_config}")
        endif()
    endif()
    get_filename_component(_libdir "${_lammps_lib}" DIRECTORY)

    execute_process(
        COMMAND ${CMAKE_COMMAND} -E env
                "LD_LIBRARY_PATH=${_libdir}:$ENV{LD_LIBRARY_PATH}"
                "DYLD_LIBRARY_PATH=${_libdir}:$ENV{DYLD_LIBRARY_PATH}"
                ${LAMMPS_EXECUTABLE} -h
        RESULT_VARIABLE exit_code
        OUTPUT_VARIABLE info
        ERROR_VARIABLE  info_err
    )
    string(APPEND info "${info_err}")

    if(NOT exit_code EQUAL 0)
        message(WARNING
            "Could not run ${LAMMPS_EXECUTABLE} to query its KOKKOS settings "
            "(exit code ${exit_code})."
        )
        return()
    endif()

    string(REGEX MATCH "KOKKOS package API:([^\n]*)"           _ "${info}")
    string(STRIP "${CMAKE_MATCH_1}" _api)
    string(REGEX MATCH "KOKKOS package precision:([^\n]*)"     _ "${info}")
    string(STRIP "${CMAKE_MATCH_1}" _prec)
    string(REGEX MATCH "KOKKOS package view layout:([^\n]*)"   _ "${info}")
    string(STRIP "${CMAKE_MATCH_1}" _layout)
    string(REGEX MATCH "Kokkos library version: ([0-9]+\\.[0-9]+\\.[0-9]+)" _ "${info}")
    set(_version "${CMAKE_MATCH_1}")

    if(NOT _api OR NOT _prec OR NOT _layout OR NOT _version)
        return()  # this LAMMPS has no KOKKOS package
    endif()

    set(LAMMPS_KOKKOS_FOUND   TRUE          PARENT_SCOPE)
    set(LAMMPS_KOKKOS_VERSION "${_version}" PARENT_SCOPE)
    set(LAMMPS_KOKKOS_PREC    "${_prec}"    PARENT_SCOPE)
    set(LAMMPS_KOKKOS_LAYOUT  "${_layout}"  PARENT_SCOPE)
    set(LAMMPS_KOKKOS_API     "${_api}"     PARENT_SCOPE)
endfunction()

#     lammps_kokkos_config_header(include_dirs outvar)
#
# Locates the generated KokkosCore_config.h within `include_dirs` and sets
# `outvar` in the parent scope to its full path (empty when not found).
function(lammps_kokkos_config_header include_dirs outvar)
    set(${outvar} "" PARENT_SCOPE)
    foreach(dir ${include_dirs})
        if(EXISTS "${dir}/KokkosCore_config.h")
            set(${outvar} "${dir}/KokkosCore_config.h" PARENT_SCOPE)
            return()
        endif()
    endforeach()
endfunction()

#     lammps_build_kokkos_config_header(outvar)
#
# Sets `outvar` in the parent scope to the KokkosCore_config.h that went into
# liblammps, if the LAMMPS build directory is available (empty otherwise).  A
# bundled-Kokkos LAMMPS build generates it under lib/kokkos, an EXTERNAL_KOKKOS
# build only has the one belonging to the external Kokkos it was pointed at.
function(lammps_build_kokkos_config_header outvar)
    set(${outvar} "" PARENT_SCOPE)
    if(NOT LAMMPS_BUILD_DIR)
        return()
    endif()
    if(EXISTS "${LAMMPS_BUILD_DIR}/lib/kokkos/KokkosCore_config.h")
        set(${outvar} "${LAMMPS_BUILD_DIR}/lib/kokkos/KokkosCore_config.h" PARENT_SCOPE)
    endif()
endfunction()

#     kokkos_config_defines(header outvar)
#
# Reads the `#define KOKKOS_*` names out of a generated KokkosCore_config.h and
# returns them as a list in `outvar` (parent scope).  Commented-out `#undef`
# lines are ignored, so the list holds exactly the options that are ON.
function(kokkos_config_defines header outvar)
    set(defines "")
    file(STRINGS "${header}" lines REGEX "^#define +KOKKOS_")
    foreach(line ${lines})
        string(REGEX MATCH "^#define +([A-Za-z0-9_]+)" _ "${line}")
        list(APPEND defines "${CMAKE_MATCH_1}")
    endforeach()
    set(${outvar} "${defines}" PARENT_SCOPE)
endfunction()

#     kokkos_config_value(header name outvar)
#
# Returns the value of a `#define <name> <value>` in a generated
# KokkosCore_config.h, or an empty string when the macro is not defined.
function(kokkos_config_value header name outvar)
    set(${outvar} "" PARENT_SCOPE)
    file(STRINGS "${header}" line REGEX "^#define +${name} +")
    if(line)
        string(REGEX MATCH "^#define +${name} +(.*)$" _ "${line}")
        string(STRIP "${CMAKE_MATCH_1}" value)
        set(${outvar} "${value}" PARENT_SCOPE)
    endif()
endfunction()

#     check_kokkos_matches_lammps(config_header)
#
# Compares the Kokkos configuration the plugins are about to be built against
# with the one reported by the installed `lmp`: Kokkos version, enabled
# backends and the view implementation.  Aborts on any disagreement, because
# none of them would ever be diagnosed by the compiler or the linker.
function(check_kokkos_matches_lammps config_header)
    kokkos_config_value("${config_header}" KOKKOS_VERSION plugin_kokkos_version)
    if(NOT plugin_kokkos_version)
        message(FATAL_ERROR "No KOKKOS_VERSION in ${config_header}")
    endif()

    string(REPLACE "." ";" v "${LAMMPS_KOKKOS_VERSION}")
    list(GET v 0 v_major)
    list(GET v 1 v_minor)
    list(GET v 2 v_patch)
    math(EXPR lammps_kokkos_version "${v_major} * 10000 + ${v_minor} * 100 + ${v_patch}")

    if(NOT plugin_kokkos_version EQUAL lammps_kokkos_version)
        message(FATAL_ERROR
            "Kokkos version mismatch: liblammps reports ${LAMMPS_KOKKOS_VERSION} "
            "(${lammps_kokkos_version}) but the Kokkos used here is "
            "${plugin_kokkos_version} (${config_header}). Point the build at the "
            "Kokkos that liblammps was actually built with."
        )
    endif()

    kokkos_config_defines("${config_header}" defines)

    # Every enabled backend has to match: a GPU-enabled liblammps defines
    # LMP_KOKKOS_GPU, which changes the layout of several LAMMPS KOKKOS
    # classes, and each backend also adds its own memory spaces.
    foreach(backend CUDA HIP SYCL OPENMP SERIAL)
        if(backend STREQUAL "OPENMP")
            set(name "OpenMP")
        elseif(backend STREQUAL "SERIAL")
            set(name "Serial")
        else()
            set(name "${backend}")
        endif()

        if("${LAMMPS_KOKKOS_API}" MATCHES "(^| )${name}( |$)")
            set(lammps_has TRUE)
        else()
            set(lammps_has FALSE)
        endif()
        if("KOKKOS_ENABLE_${backend}" IN_LIST defines)
            set(plugin_has TRUE)
        else()
            set(plugin_has FALSE)
        endif()

        if(lammps_has AND NOT plugin_has)
            message(FATAL_ERROR
                "liblammps was built with the Kokkos ${name} backend but this "
                "plugin build was not. Add -DKokkos_ENABLE_${backend}=on (and "
                "the matching -DKokkos_ARCH_... for a GPU backend), or point "
                "Kokkos_ROOT at a Kokkos that has it. liblammps reports: "
                "${LAMMPS_KOKKOS_API}"
            )
        elseif(plugin_has AND NOT lammps_has)
            message(FATAL_ERROR
                "This plugin build enables the Kokkos ${name} backend but "
                "liblammps was not built with it. liblammps reports: "
                "${LAMMPS_KOKKOS_API}"
            )
        endif()
    endforeach()

    if("KOKKOS_ENABLE_IMPL_VIEW_LEGACY" IN_LIST defines)
        set(plugin_view_legacy ON)
    else()
        set(plugin_view_legacy OFF)
    endif()
    if(NOT "${plugin_view_legacy}" STREQUAL "${LAMMPS_KOKKOS_VIEW_LEGACY_VALUE}")
        set(complaint
            "Kokkos_ENABLE_IMPL_VIEW_LEGACY is ${plugin_view_legacy} for the "
            "plugins but liblammps is expected to have been built with "
            "${LAMMPS_KOKKOS_VIEW_LEGACY_VALUE} (${config_header}).\n"
            "The two settings give Kokkos::View different sizes, which shifts "
            "every DualView member of AtomKokkos."
        )
        if(LAMMPS_KOKKOS_VIEW_LEGACY_KNOWN)
            message(FATAL_ERROR ${complaint}
                " Rebuild the Kokkos used here with "
                "-DKokkos_ENABLE_IMPL_VIEW_LEGACY=${LAMMPS_KOKKOS_VIEW_LEGACY_VALUE}, "
                "or set LAMMPS_KOKKOS_VIEW_LEGACY if liblammps really was built "
                "the other way round."
            )
        else()
            # We only guessed the liblammps value from the LAMMPS default, so a
            # disagreement is not proof of a mismatch.
            message(WARNING ${complaint}
                " The value used by liblammps could not be determined, so the "
                "LAMMPS default (ON) was assumed. Set LAMMPS_KOKKOS_VIEW_LEGACY "
                "to the value liblammps was really built with, or pass "
                "LAMMPS_BUILD_DIR so that it can be read out of the LAMMPS build."
            )
        endif()
    endif()
endfunction()

#     check_kokkos_config_matches_lammps(config_header)
#
# Belt-and-braces check, only possible when LAMMPS_BUILD_DIR is given: compares
# the whole generated KokkosCore_config.h the plugins will use against the one
# that went into liblammps, and reports exactly which options differ.  Macros
# listed in LAMMPS_KOKKOS_CONFIG_IGNORE are exempt.
function(check_kokkos_config_matches_lammps config_header)
    lammps_build_kokkos_config_header(lammps_config)
    if(NOT lammps_config OR NOT config_header)
        return()
    endif()

    # The same file is not worth comparing with itself (`package` mode pointed
    # at <LAMMPS_BUILD_DIR>/cmake_packages/Kokkos ends up here).
    get_filename_component(a "${config_header}" REALPATH)
    get_filename_component(b "${lammps_config}" REALPATH)
    if("${a}" STREQUAL "${b}")
        message(STATUS "Kokkos configuration is the one used by liblammps")
        return()
    endif()

    kokkos_config_defines("${config_header}" plugin_defines)
    kokkos_config_defines("${lammps_config}"  lammps_defines)

    set(only_plugin ${plugin_defines})
    if(lammps_defines)
        list(REMOVE_ITEM only_plugin ${lammps_defines})
    endif()
    set(only_lammps ${lammps_defines})
    if(plugin_defines)
        list(REMOVE_ITEM only_lammps ${plugin_defines})
    endif()
    foreach(ignored ${LAMMPS_KOKKOS_CONFIG_IGNORE})
        if(only_plugin)
            list(REMOVE_ITEM only_plugin ${ignored})
        endif()
        if(only_lammps)
            list(REMOVE_ITEM only_lammps ${ignored})
        endif()
    endforeach()

    if(only_plugin OR only_lammps)
        string(REPLACE ";" "\n        " on_here  "${only_plugin}")
        string(REPLACE ";" "\n        " on_lammps "${only_lammps}")
        set(details "")
        if(only_plugin)
            string(APPEND details "\n    on for the plugins but not for liblammps:\n        ${on_here}")
        endif()
        if(only_lammps)
            string(APPEND details "\n    on for liblammps but not for the plugins:\n        ${on_lammps}")
        endif()
        message(FATAL_ERROR
            "The Kokkos configuration used for the plugins does not match the "
            "one compiled into liblammps:\n"
            "    plugins  : ${config_header}\n"
            "    liblammps: ${lammps_config}"
            "${details}\n"
            "Pass the same value for each of these on the plugin command line. "
            "Building against a mismatched Kokkos succeeds silently and then "
            "crashes at run time. Options that genuinely cannot affect the ABI "
            "can be added to LAMMPS_KOKKOS_CONFIG_IGNORE instead."
        )
    endif()

    message(STATUS "Kokkos configuration matches the one used by liblammps")
endfunction()

#     resolve_kokkos_view_legacy()
#
# Sets LAMMPS_KOKKOS_VIEW_LEGACY_VALUE (ON/OFF) in the parent scope: the value
# of Kokkos_ENABLE_IMPL_VIEW_LEGACY that liblammps was built with.
function(resolve_kokkos_view_legacy)
    set(LAMMPS_KOKKOS_VIEW_LEGACY_KNOWN TRUE PARENT_SCOPE)
    string(TOUPPER "${LAMMPS_KOKKOS_VIEW_LEGACY}" requested)

    if(requested STREQUAL "ON" OR requested STREQUAL "OFF")
        set(LAMMPS_KOKKOS_VIEW_LEGACY_VALUE ${requested} PARENT_SCOPE)
        return()
    endif()

    # Read it out of the Kokkos that the LAMMPS build generated, when we have
    # the LAMMPS build directory.  Its CMakeCache is deliberately not consulted:
    # LAMMPS declares the option even for an EXTERNAL_KOKKOS build, where it has
    # no effect on the Kokkos that liblammps actually uses.
    lammps_build_kokkos_config_header(lammps_config)
    if(lammps_config)
        kokkos_config_defines("${lammps_config}" defines)
        if("KOKKOS_ENABLE_IMPL_VIEW_LEGACY" IN_LIST defines)
            set(LAMMPS_KOKKOS_VIEW_LEGACY_VALUE ON PARENT_SCOPE)
        else()
            set(LAMMPS_KOKKOS_VIEW_LEGACY_VALUE OFF PARENT_SCOPE)
        endif()
        return()
    endif()

    # Fall back to the LAMMPS default (cmake/Modules/Packages/KOKKOS.cmake
    # turns it ON, while Kokkos itself defaults to OFF).
    set(LAMMPS_KOKKOS_VIEW_LEGACY_VALUE ON PARENT_SCOPE)
    set(LAMMPS_KOKKOS_VIEW_LEGACY_KNOWN FALSE PARENT_SCOPE)
endfunction()

#     select_kokkos_mode()
#
# Resolves LAMMPS_KOKKOS_MODE=auto into `package` or `source` and sets, in the
# calling scope, LAMMPS_KOKKOS_MODE_RESOLVED plus LAMMPS_KOKKOS_PACKAGE_HINT
# (for `package`) and LAMMPS_KOKKOS_DIR (for `source`).
macro(select_kokkos_mode)
    string(TOLOWER "${LAMMPS_KOKKOS_MODE}" LAMMPS_KOKKOS_MODE_RESOLVED)

    if(NOT LAMMPS_KOKKOS_MODE_RESOLVED MATCHES "^(auto|source|package|none)$")
        message(FATAL_ERROR
            "LAMMPS_KOKKOS_MODE must be one of auto, source, package or none, "
            "not '${LAMMPS_KOKKOS_MODE}'"
        )
    endif()

    # Kokkos sources shipped with the LAMMPS repository.
    if(NOT LAMMPS_KOKKOS_DIR AND LAMMPS_SOURCE_DIR)
        get_filename_component(_kokkos_src "${LAMMPS_SOURCE_DIR}/../lib/kokkos" ABSOLUTE)
        if(EXISTS "${_kokkos_src}/CMakeLists.txt")
            set(LAMMPS_KOKKOS_DIR "${_kokkos_src}")
        endif()
    endif()

    # A Kokkos CMake package exported by the LAMMPS build.
    set(LAMMPS_KOKKOS_PACKAGE_HINT "")
    if(LAMMPS_BUILD_DIR AND EXISTS "${LAMMPS_BUILD_DIR}/cmake_packages/Kokkos")
        set(LAMMPS_KOKKOS_PACKAGE_HINT "${LAMMPS_BUILD_DIR}/cmake_packages/Kokkos")
    endif()

    if(LAMMPS_KOKKOS_MODE_RESOLVED STREQUAL "auto")
        if(Kokkos_ROOT OR DEFINED ENV{Kokkos_ROOT} OR Kokkos_DIR OR LAMMPS_KOKKOS_PACKAGE_HINT)
            set(LAMMPS_KOKKOS_MODE_RESOLVED "package")
        elseif(LAMMPS_KOKKOS_DIR)
            set(LAMMPS_KOKKOS_MODE_RESOLVED "source")
        else()
            set(LAMMPS_KOKKOS_MODE_RESOLVED "package")
        endif()
    endif()

endmacro()

#     setup_kokkos_from_source()
#
# Configures the Kokkos that ships with LAMMPS (<lammps>/lib/kokkos) with the
# options LAMMPS applies to it, and leaves its include directories in the
# Kokkos* variables.  Only the generated configuration headers and the include
# paths are wanted; see setup_kokkos() on why nothing is ever linked.
macro(setup_kokkos_from_source)
    if(NOT LAMMPS_KOKKOS_DIR)
        message(FATAL_ERROR
            "LAMMPS_KOKKOS_MODE=source, but the Kokkos sources that come with "
            "LAMMPS could not be found at ${LAMMPS_SOURCE_DIR}/../lib/kokkos.\n"
            "Set LAMMPS_KOKKOS_DIR to the lib/kokkos directory of the LAMMPS "
            "source tree that liblammps was built from."
        )
    endif()

    message(STATUS "Using the Kokkos sources shipped with LAMMPS: ${LAMMPS_KOKKOS_DIR}")

    # Mirror the Kokkos options LAMMPS sets in
    # cmake/Modules/Packages/KOKKOS.cmake so that Kokkos::View has the same
    # layout on both sides.  These have to be set before add_subdirectory().
    set(Kokkos_ENABLE_IMPL_VIEW_LEGACY ${LAMMPS_KOKKOS_VIEW_LEGACY_VALUE} CACHE BOOL "" FORCE)
    if(Kokkos_ENABLE_HIP)
        set(Kokkos_ENABLE_HIP_MULTIPLE_KERNEL_INSTANTIATIONS ON CACHE BOOL "" FORCE)
        set(Kokkos_ENABLE_ROCTHRUST ON CACHE BOOL "" FORCE)
    endif()
    if(Kokkos_ENABLE_SERIAL AND NOT (Kokkos_ENABLE_OPENMP OR Kokkos_ENABLE_THREADS OR
       Kokkos_ENABLE_CUDA OR Kokkos_ENABLE_HIP OR Kokkos_ENABLE_SYCL OR
       Kokkos_ENABLE_OPENMPTARGET))
        set(Kokkos_ENABLE_ATOMICS_BYPASS ON CACHE BOOL "" FORCE)
    endif()

    # EXCLUDE_FROM_ALL: we only want the generated Kokkos configuration
    # headers and the include paths, never the Kokkos libraries.
    add_subdirectory("${LAMMPS_KOKKOS_DIR}" "${CMAKE_BINARY_DIR}/lib/kokkos" EXCLUDE_FROM_ALL)

    set(kokkos_config_h "${CMAKE_BINARY_DIR}/lib/kokkos/KokkosCore_config.h")
    if(NOT EXISTS "${kokkos_config_h}")
        message(FATAL_ERROR "Kokkos did not generate ${kokkos_config_h}")
    endif()

    set(Kokkos_FOUND TRUE)
endmacro()

#     setup_kokkos_from_package()
#
# Finds an already configured Kokkos with find_package().  This is the Kokkos
# an EXTERNAL_KOKKOS build of LAMMPS was linked against, or the package a
# bundled-Kokkos LAMMPS build exports to <LAMMPS_BUILD_DIR>/cmake_packages.
macro(setup_kokkos_from_package)
    if(LAMMPS_KOKKOS_PACKAGE_HINT)
        find_package(Kokkos QUIET NO_DEFAULT_PATH HINTS "${LAMMPS_KOKKOS_PACKAGE_HINT}")
    else()
        find_package(Kokkos QUIET)
    endif()

    if(NOT Kokkos_FOUND)
        message(FATAL_ERROR
            "Could not find a Kokkos CMake package.\n"
            "If liblammps was built against a Kokkos outside of the LAMMPS "
            "source tree (-DEXTERNAL_KOKKOS=yes), set Kokkos_ROOT to that same "
            "installation. If it was built with the bundled Kokkos, either set "
            "LAMMPS_BUILD_DIR (the package is exported to "
            "<LAMMPS_BUILD_DIR>/cmake_packages/Kokkos) or use "
            "-DLAMMPS_KOKKOS_MODE=source to build against "
            "<LAMMPS_SOURCE_DIR>/../lib/kokkos directly."
        )
    endif()

    if(NOT LAMMPS_KOKKOS_PACKAGE_HINT)
        message(WARNING
            "Kokkos was found outside of the LAMMPS build directory "
            "(${Kokkos_DIR}). Make sure this is the very same Kokkos that "
            "liblammps was built against, otherwise the plugins will be binary "
            "incompatible with it."
        )
    endif()

    message(STATUS "Using the Kokkos package at ${Kokkos_DIR} (version ${Kokkos_VERSION})")

    get_target_property(_core_includes Kokkos::kokkoscore INTERFACE_INCLUDE_DIRECTORIES)
    lammps_kokkos_config_header("${_core_includes}" kokkos_config_h)
    if(NOT kokkos_config_h)
        message(FATAL_ERROR
            "Could not find KokkosCore_config.h in the include directories of "
            "the Kokkos package at ${Kokkos_DIR}. Without it the Kokkos "
            "configuration cannot be checked against liblammps."
        )
    endif()
endmacro()

#     setup_kokkos()
#
# Sets up Kokkos in whichever of the two supported layouts applies, checks it
# against the installed liblammps, and exposes it as the header-only Kokkos::src
# target.  The Kokkos libraries themselves are deliberately never linked: the
# Kokkos runtime lives inside liblammps, and pulling in a second copy would give
# the process two sets of Kokkos globals.
macro(setup_kokkos)
    select_kokkos_mode()
    probe_lammps_kokkos()

    if(LAMMPS_KOKKOS_MODE_RESOLVED STREQUAL "none")
        message(STATUS "LAMMPS_KOKKOS_MODE=none, the Kokkos plugins will not be built.")
    elseif(NOT LAMMPS_KOKKOS_FOUND)
        message(STATUS
            "This LAMMPS does not have the KOKKOS package, or `lmp` could not be "
            "run to query it. The Kokkos plugins will not be built."
        )
    else()
        message(STATUS
            "liblammps KOKKOS settings: Kokkos ${LAMMPS_KOKKOS_VERSION}, "
            "API ${LAMMPS_KOKKOS_API}, ${LAMMPS_KOKKOS_PREC} precision, "
            "${LAMMPS_KOKKOS_LAYOUT} view layout"
        )

        resolve_kokkos_view_legacy()

        if(LAMMPS_KOKKOS_MODE_RESOLVED STREQUAL "source")
            setup_kokkos_from_source()
        else()
            setup_kokkos_from_package()
        endif()

        # Neither the compiler nor the linker will ever report a Kokkos
        # configuration mismatch, so this is the only place it can be caught.
        check_kokkos_matches_lammps("${kokkos_config_h}")
        check_kokkos_config_matches_lammps("${kokkos_config_h}")

        get_target_property(KokkosCore       Kokkos::kokkoscore       INTERFACE_INCLUDE_DIRECTORIES)
        get_target_property(KokkosContainers Kokkos::kokkoscontainers INTERFACE_INCLUDE_DIRECTORIES)
        get_target_property(KokkosAlgorithms Kokkos::kokkosalgorithms INTERFACE_INCLUDE_DIRECTORIES)
        get_target_property(KokkosSIMD       Kokkos::kokkossimd       INTERFACE_INCLUDE_DIRECTORIES)
        get_target_property(KokkosCompileOptions     Kokkos::kokkoscore INTERFACE_COMPILE_OPTIONS)
        get_target_property(KokkosCompileDefinitions Kokkos::kokkoscore INTERFACE_COMPILE_DEFINITIONS)

        add_library(Kokkos_src INTERFACE)
        add_library(Kokkos::src ALIAS Kokkos_src)
        target_include_directories(Kokkos_src INTERFACE "${LAMMPS_SOURCE_DIR}/KOKKOS")
        target_include_directories(Kokkos_src INTERFACE "${KokkosCore}")
        target_include_directories(Kokkos_src INTERFACE "${KokkosContainers}")
        target_include_directories(Kokkos_src INTERFACE "${KokkosAlgorithms}")
        target_include_directories(Kokkos_src INTERFACE "${KokkosSIMD}")

        if(KokkosCompileOptions)
            set_target_properties(Kokkos_src PROPERTIES
                INTERFACE_COMPILE_OPTIONS "${KokkosCompileOptions}")
        endif()
        if(KokkosCompileDefinitions)
            set_target_properties(Kokkos_src PROPERTIES
                INTERFACE_COMPILE_DEFINITIONS "${KokkosCompileDefinitions}")
        endif()

        # LAMMPS applies these with PRIVATE scope and its exported target only
        # carries LAMMPS_SMALLBIG, so they have to be repeated here.  Getting
        # the precision wrong does not crash, it silently produces garbage.
        if(LAMMPS_KOKKOS_PREC STREQUAL "double")
            set(prec_setting "DOUBLE_DOUBLE")
        elseif(LAMMPS_KOKKOS_PREC STREQUAL "mixed")
            set(prec_setting "SINGLE_DOUBLE")
        else()
            set(prec_setting "SINGLE_SINGLE")
        endif()
        string(TOUPPER "${LAMMPS_KOKKOS_LAYOUT}" layout_setting)

        target_compile_definitions(Kokkos_src INTERFACE
            "LMP_KOKKOS_${prec_setting}"
            "LMP_KOKKOS_LAYOUT_${layout_setting}"
        )

        set(Kokkos_FOUND TRUE)
    endif()
endmacro()

setup_kokkos()
