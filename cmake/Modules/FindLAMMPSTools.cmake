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
# An installed LAMMPS ships neither the Kokkos headers nor a Kokkos CMake
# package, so the settings cannot be read out of the install tree directly.
# They can, however, be obtained from the two things the user already provides:
#
#   * LAMMPS_SOURCE_DIR -> ../lib/kokkos holds the exact Kokkos sources that
#     were compiled into liblammps, so the version can never drift.
#   * the installed `lmp` binary reports its Kokkos version, precision and view
#     layout when started with `-k on`, so the configuration can be recovered
#     from the install alone.
#
# LAMMPS_BUILD_DIR is therefore not required.  When it happens to be given, the
# generated KokkosCore_config.h is compared as well, which is the only fully
# airtight check.

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

#     check_kokkos_config_matches_lammps(include_dirs)
#
# Optional belt-and-braces check, only possible when LAMMPS_BUILD_DIR is given:
# byte-compares the generated KokkosCore_config.h the plugins will use against
# the one that went into liblammps.
function(check_kokkos_config_matches_lammps include_dirs)
    if(NOT LAMMPS_BUILD_DIR)
        return()
    endif()

    set(lammps_config "${LAMMPS_BUILD_DIR}/lib/kokkos/KokkosCore_config.h")
    if(NOT EXISTS "${lammps_config}")
        return()
    endif()

    unset(plugin_config)
    foreach(dir ${include_dirs})
        if(EXISTS "${dir}/KokkosCore_config.h")
            set(plugin_config "${dir}/KokkosCore_config.h")
            break()
        endif()
    endforeach()
    if(NOT plugin_config)
        return()
    endif()

    execute_process(
        COMMAND ${CMAKE_COMMAND} -E compare_files "${plugin_config}" "${lammps_config}"
        RESULT_VARIABLE config_differs OUTPUT_QUIET ERROR_QUIET
    )
    if(config_differs)
        execute_process(
            COMMAND ${CMAKE_COMMAND} -E compare_files --ignore-eol "${plugin_config}" "${lammps_config}"
            RESULT_VARIABLE config_differs OUTPUT_QUIET ERROR_QUIET
        )
    endif()

    if(config_differs)
        message(FATAL_ERROR
            "The Kokkos configuration used for the plugins does not match the "
            "one compiled into liblammps:\n"
            "    plugins  : ${plugin_config}\n"
            "    liblammps: ${lammps_config}\n"
            "Diff them to see which Kokkos option differs, and pass the same "
            "value on the plugin command line. Building against a mismatched "
            "Kokkos succeeds silently and then crashes at run time."
        )
    endif()

    message(STATUS "Kokkos configuration matches the one used by liblammps")
endfunction()

#     setup_kokkos()
#
# Configures the Kokkos that ships with LAMMPS, using the settings recovered
# from the installed `lmp`, and exposes it as the header-only Kokkos::src
# target.  The Kokkos libraries themselves are deliberately never linked: the
# Kokkos runtime lives inside liblammps, and pulling in a second copy would give
# the process two sets of Kokkos globals.
macro(setup_kokkos)
    probe_lammps_kokkos()

    if(NOT LAMMPS_KOKKOS_FOUND)
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

        if(NOT LAMMPS_KOKKOS_DIR)
            get_filename_component(LAMMPS_KOKKOS_DIR
                "${LAMMPS_SOURCE_DIR}/../lib/kokkos" ABSOLUTE)
        endif()
        if(NOT EXISTS "${LAMMPS_KOKKOS_DIR}/CMakeLists.txt")
            message(FATAL_ERROR
                "Could not find the Kokkos sources that LAMMPS was built with at\n"
                "    ${LAMMPS_KOKKOS_DIR}\n"
                "Set LAMMPS_KOKKOS_DIR to the lib/kokkos directory of the LAMMPS "
                "source tree that liblammps was built from."
            )
        endif()

        # Mirror the Kokkos options LAMMPS sets in
        # cmake/Modules/Packages/KOKKOS.cmake so that Kokkos::View has the same
        # layout on both sides.  These have to be set before add_subdirectory().
        if(LAMMPS_KOKKOS_LAYOUT STREQUAL "legacy")
            set(Kokkos_ENABLE_IMPL_VIEW_LEGACY ON  CACHE BOOL "" FORCE)
        else()
            set(Kokkos_ENABLE_IMPL_VIEW_LEGACY OFF CACHE BOOL "" FORCE)
        endif()
        if(Kokkos_ENABLE_HIP)
            set(Kokkos_ENABLE_HIP_MULTIPLE_KERNEL_INSTANTIATIONS ON CACHE BOOL "" FORCE)
            set(Kokkos_ENABLE_ROCTHRUST ON CACHE BOOL "" FORCE)
        endif()

        # EXCLUDE_FROM_ALL: we only want the generated Kokkos configuration
        # headers and the include paths, never the Kokkos libraries.
        add_subdirectory("${LAMMPS_KOKKOS_DIR}" "${CMAKE_BINARY_DIR}/lib/kokkos" EXCLUDE_FROM_ALL)

        # Kokkos sets Kokkos_VERSION only in its own directory scope, so read the
        # version out of the configuration header it just generated instead.
        set(kokkos_config_h "${CMAKE_BINARY_DIR}/lib/kokkos/KokkosCore_config.h")
        if(NOT EXISTS "${kokkos_config_h}")
            message(FATAL_ERROR "Kokkos did not generate ${kokkos_config_h}")
        endif()
        file(STRINGS "${kokkos_config_h}" version_line REGEX "^#define KOKKOS_VERSION ")
        string(REGEX MATCH "([0-9]+)$" _ "${version_line}")
        set(plugin_kokkos_version "${CMAKE_MATCH_1}")

        string(REPLACE "." ";" v "${LAMMPS_KOKKOS_VERSION}")
        list(GET v 0 v_major)
        list(GET v 1 v_minor)
        list(GET v 2 v_patch)
        math(EXPR lammps_kokkos_version "${v_major} * 10000 + ${v_minor} * 100 + ${v_patch}")

        if(NOT plugin_kokkos_version EQUAL lammps_kokkos_version)
            message(FATAL_ERROR
                "Kokkos version mismatch: liblammps reports ${LAMMPS_KOKKOS_VERSION} "
                "(${lammps_kokkos_version}) but ${LAMMPS_KOKKOS_DIR} is "
                "${plugin_kokkos_version}. Point LAMMPS_SOURCE_DIR (or "
                "LAMMPS_KOKKOS_DIR) at the LAMMPS source tree that liblammps was "
                "actually built from."
            )
        endif()

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
            if(Kokkos_ENABLE_${backend})
                set(plugin_has TRUE)
            else()
                set(plugin_has FALSE)
            endif()

            if(lammps_has AND NOT plugin_has)
                message(FATAL_ERROR
                    "liblammps was built with the Kokkos ${name} backend but this "
                    "plugin build was not. Add -DKokkos_ENABLE_${backend}=on (and "
                    "the matching -DKokkos_ARCH_... for a GPU backend). liblammps "
                    "reports: ${LAMMPS_KOKKOS_API}"
                )
            elseif(plugin_has AND NOT lammps_has)
                message(FATAL_ERROR
                    "This plugin build enables the Kokkos ${name} backend but "
                    "liblammps was not built with it. liblammps reports: "
                    "${LAMMPS_KOKKOS_API}"
                )
            endif()
        endforeach()

        get_target_property(KokkosCore       Kokkos::kokkoscore       INTERFACE_INCLUDE_DIRECTORIES)
        get_target_property(KokkosContainers Kokkos::kokkoscontainers INTERFACE_INCLUDE_DIRECTORIES)
        get_target_property(KokkosAlgorithms Kokkos::kokkosalgorithms INTERFACE_INCLUDE_DIRECTORIES)
        get_target_property(KokkosSIMD       Kokkos::kokkossimd       INTERFACE_INCLUDE_DIRECTORIES)
        get_target_property(KokkosCompileOptions     Kokkos::kokkoscore INTERFACE_COMPILE_OPTIONS)
        get_target_property(KokkosCompileDefinitions Kokkos::kokkoscore INTERFACE_COMPILE_DEFINITIONS)

        check_kokkos_config_matches_lammps("${KokkosCore}")

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
