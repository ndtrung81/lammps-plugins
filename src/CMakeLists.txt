# -*- CMake -*- file for plugin examples.
# The is meant to be used as a template for plugins that are
# distributed independent from the LAMMPS package.
##########################################

cmake_minimum_required(VERSION 3.16)

# enforce out-of-source build
if(${CMAKE_SOURCE_DIR} STREQUAL ${CMAKE_BINARY_DIR})
  message(FATAL_ERROR "In-source builds are not allowed. You must create and use a build directory. "
    "Please remove CMakeCache.txt and CMakeFiles first.")
endif()

project(plugins VERSION 1.0 LANGUAGES C)

set(PROJECT_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake/Modules")
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${PROJECT_MODULE_PATH})

include("${PROJECT_MODULE_PATH}/FetchCPM.cmake")
include("${PROJECT_MODULE_PATH}/FindLAMMPSTools.cmake")

# when this file is included as subdirectory in the LAMMPS build, many settings are directly imported
if(LAMMPS_SOURCE_DIR)
  set(LAMMPS_HEADER_DIR ${LAMMPS_SOURCE_DIR})
else()
  # NOTE: the next line should be commented out when used outside of the LAMMPS package
  #get_filename_component(LAMMPS_SOURCE_DIR ${PROJECT_SOURCE_DIR}/../../src ABSOLUTE)
  set(LAMMPS_HEADER_DIR ${LAMMPS_SOURCE_DIR} CACHE PATH "Location of LAMMPS headers")
  if(NOT LAMMPS_HEADER_DIR)
    message(FATAL_ERROR "Must set LAMMPS_HEADER_DIR")
  endif()
  # by default, install into $HOME/.local (not /usr/local),
  # so that no root access (and sudo) is needed
  if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
    set(CMAKE_INSTALL_PREFIX "$ENV{HOME}/.local" CACHE PATH "Default install path" FORCE)
  endif()
  # ugly hacks for MSVC which by default always reports an old C++ standard in the __cplusplus macro
  # and prints lots of pointless warnings about "unsafe" functions
  if(MSVC)
    if(CMAKE_CXX_COMPILER_ID STREQUAL "MSVC")
      add_compile_options(/Zc:__cplusplus)
      add_compile_options(/wd4244)
      add_compile_options(/wd4267)
      add_compile_options(/wd4250)
      add_compile_options(/EHsc)
    endif()
    add_compile_definitions(_CRT_SECURE_NO_WARNINGS)
  endif()
endif()

# find the build directory where liblammps.so is located
if(NOT LAMMPS_BUILD_DIR)
  # when built inside of the LAMMPS package LAMMPS_BUILD_DIR is the same as the build directory
  get_filename_component(LAMMPS_BUILD_DIR ${CMAKE_BUILD_DIRECTORY} ABSOLUTE)
else()
  # when built outside of the LAMMPS package LAMMPS_BUILD_DIR needs to be specified
  message(STATUS "LAMMPS build directory specified: ${LAMMPS_BUILD_DIR}")
endif()

# C++17 is required
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Need -restrict with Intel compilers
if(CMAKE_CXX_COMPILER_ID STREQUAL "Intel")
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -restrict")
endif()

set(CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR})
include(CheckIncludeFileCXX)
if(NOT LAMMPS_SOURCE_DIR)
  include(LAMMPSInterfaceCXX)
endif()

##########################
# building the plugins

if (NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE RelWithDebInfo CACHE STRING "Choose the type of build, options are: None Debug Release RelWithDebInfo MinSizeRel." FORCE)
endif()

add_library(morse2plugin MODULE morse2plugin.cpp pair_morse2.cpp pair_morse2_omp.cpp)
target_include_directories(morse2plugin PRIVATE "${LAMMPS_HEADER_DIR}")
target_include_directories(morse2plugin PRIVATE "${LAMMPS_HEADER_DIR}/OPENMP")
target_link_libraries(morse2plugin PRIVATE "${LAMMPS_BUILD_DIR}/liblammps.so")
target_include_directories(morse2plugin PRIVATE ${MPI_CXX_INCLUDE_DIRS})

add_library(lj2plugin MODULE lj2plugin.cpp pair_lj_cut2_kokkos.cpp)
target_link_libraries(lj2plugin PUBLIC LAMMPS::src LAMMPS::lammps)

if (Kokkos_FOUND)
   get_target_property(KokkosCompileOptions     Kokkos::src INTERFACE_COMPILE_OPTIONS)
   message(STATUS "Kokkos compile options: ${KokkosCompileOptions}")
   target_link_libraries(lj2plugin PUBLIC Kokkos::src)
   target_compile_options(lj2plugin PRIVATE ${KokkosCompileOptions})

#if ("CUDA_LAMBDA" IN_LIST Kokkos_OPTIONS)
#  message(STATUS "Kokkos with CUDA backend with --extended-lambda")
#  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} --extended-lambda -Wext-lambda-captures-this -arch=sm_60 -std=c++17")
#  set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} --extended-lambda -Wext-lambda-captures-this -arch=sm_60 -std=c++17")
#  set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG}  --extended-lambda -Wext-lambda-captures-this -arch=sm_60 -std=c++17")
#endif()
endif()

set_target_properties(morse2plugin lj2plugin PROPERTIES PREFIX "" SUFFIX ".so")

# MacOS seems to need this
if(CMAKE_SYSTEM_NAME STREQUAL Darwin)
  set_target_properties(morse2plugin lj2plugin
    PROPERTIES LINK_FLAGS "-Wl,-undefined,dynamic_lookup")
elseif(CMAKE_SYSTEM_NAME STREQUAL "Windows")
# tell CMake to export all symbols to a .dll on Windows with special case for MinGW cross-compilers
  set_target_properties(morse2plugin lj2plugin
    PROPERTIES WINDOWS_EXPORT_ALL_SYMBOLS TRUE)
  if(CMAKE_CROSSCOMPILING)
    set_target_properties(morse2plugin lj2plugin
      PROPERTIES LINK_FLAGS "-Wl,--export-all-symbols")
  endif()
else()
  set_target_properties(morse2plugin lj2plugin PROPERTIES
    LINK_FLAGS "-rdynamic")
endif()

add_custom_target(plugins ALL ${CMAKE_COMMAND} -E echo "Building Plugins"
  DEPENDS morse2plugin lj2plugin)
