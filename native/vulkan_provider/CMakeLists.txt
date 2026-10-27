cmake_minimum_required(VERSION 3.23)
project(godauldron_native_vulkan_provider LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

option(GODAULDRON_RD_ONLY "Build backend-neutral native RD workload without Vulkan diagnostics" OFF)
find_package(Python3 REQUIRED COMPONENTS Interpreter)

include(FetchContent)
# A released, backwards-compatible C++ binding target; no copied Godot source.
set(GODOTCPP_API_VERSION "4.7" CACHE STRING "Godot extension API target" FORCE)
FetchContent_Declare(godot_cpp
  GIT_REPOSITORY https://github.com/godotengine/godot-cpp.git
  GIT_TAG 10.0.0-stable
  GIT_SHALLOW TRUE)
FetchContent_MakeAvailable(godot_cpp)

set(GENERATED_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated")
file(MAKE_DIRECTORY "${GENERATED_DIR}")

if(GODAULDRON_RD_ONLY)
  execute_process(
    COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/pinned_spirv.py"
      decode "${CMAKE_CURRENT_SOURCE_DIR}/embedded/persistent_image.spv.b64"
      "${GENERATED_DIR}/persistent_image.spv"
    RESULT_VARIABLE RD_SPIRV_DECODE_RESULT
    COMMAND_ERROR_IS_FATAL ANY)
  execute_process(
    COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/embed_spirv.py"
      "${GENERATED_DIR}/persistent_image.spv" "${GENERATED_DIR}/persistent_compute_spirv.h"
      "kPersistentComputeSpirv"
    RESULT_VARIABLE RD_SPIRV_EMBED_RESULT
    COMMAND_ERROR_IS_FATAL ANY)
  add_library(godauldron_native_rd_workload SHARED
    native_rd_workload.cpp native_rd_workload.h register_rd_types.cpp
    "${GENERATED_DIR}/persistent_compute_spirv.h")
  target_include_directories(godauldron_native_rd_workload PRIVATE "${GENERATED_DIR}")
  target_compile_features(godauldron_native_rd_workload PRIVATE cxx_std_23)
  target_link_libraries(godauldron_native_rd_workload PRIVATE godot-cpp)
  set_target_properties(godauldron_native_rd_workload PROPERTIES
    OUTPUT_NAME "godauldron_native_rd_workload")
  if(MSVC)
    target_compile_options(godauldron_native_rd_workload PRIVATE /W4)
  else()
    target_compile_options(godauldron_native_rd_workload PRIVATE -Wall -Wextra -Wpedantic)
  endif()
  return()
endif()

find_package(Vulkan REQUIRED)
find_program(GLSLANG_VALIDATOR glslangValidator REQUIRED)
add_custom_command(
  OUTPUT "${GENERATED_DIR}/compute.spv"
  COMMAND "${GLSLANG_VALIDATOR}" -V -S comp
    -o "${GENERATED_DIR}/compute.spv" "${CMAKE_CURRENT_SOURCE_DIR}/compute.comp"
  DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/compute.comp"
  VERBATIM)
add_custom_command(
  OUTPUT "${GENERATED_DIR}/compute_spirv.h"
  COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/embed_spirv.py"
    "${GENERATED_DIR}/compute.spv" "${GENERATED_DIR}/compute_spirv.h"
  DEPENDS "${GENERATED_DIR}/compute.spv" "${CMAKE_CURRENT_SOURCE_DIR}/embed_spirv.py"
  VERBATIM)
add_custom_command(
  OUTPUT "${GENERATED_DIR}/engine_image.spv"
  COMMAND "${GLSLANG_VALIDATOR}" -V -S comp
    -o "${GENERATED_DIR}/engine_image.spv" "${CMAKE_CURRENT_SOURCE_DIR}/engine_image.comp"
  DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/engine_image.comp"
  VERBATIM)
add_custom_command(
  OUTPUT "${GENERATED_DIR}/engine_compute_spirv.h"
  COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/embed_spirv.py"
    "${GENERATED_DIR}/engine_image.spv" "${GENERATED_DIR}/engine_compute_spirv.h"
    "kEngineComputeSpirv"
  DEPENDS "${GENERATED_DIR}/engine_image.spv" "${CMAKE_CURRENT_SOURCE_DIR}/embed_spirv.py"
  VERBATIM)
add_custom_command(
  OUTPUT "${GENERATED_DIR}/persistent_image.spv"
  COMMAND "${GLSLANG_VALIDATOR}" -V -S comp
    -o "${GENERATED_DIR}/persistent_image.spv" "${CMAKE_CURRENT_SOURCE_DIR}/persistent_image.comp"
  DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/persistent_image.comp"
  VERBATIM)
add_custom_command(
  OUTPUT "${GENERATED_DIR}/persistent_compute_spirv.h"
  COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/embed_spirv.py"
    "${GENERATED_DIR}/persistent_image.spv" "${GENERATED_DIR}/persistent_compute_spirv.h"
    "kPersistentComputeSpirv"
  DEPENDS "${GENERATED_DIR}/persistent_image.spv" "${CMAKE_CURRENT_SOURCE_DIR}/embed_spirv.py"
  VERBATIM)
add_library(godauldron_native_vulkan_provider SHARED
  native_gpu_probe.cpp native_gpu_probe.h register_types.cpp
  native_rd_workload.cpp native_rd_workload.h
  "${GENERATED_DIR}/compute_spirv.h"
  "${GENERATED_DIR}/engine_compute_spirv.h"
  "${GENERATED_DIR}/persistent_compute_spirv.h")
target_include_directories(godauldron_native_vulkan_provider PRIVATE "${GENERATED_DIR}")
target_compile_features(godauldron_native_vulkan_provider PRIVATE cxx_std_23)
target_link_libraries(godauldron_native_vulkan_provider PRIVATE godot-cpp Vulkan::Vulkan)
set_target_properties(godauldron_native_vulkan_provider PROPERTIES
  PREFIX "lib" OUTPUT_NAME "godauldron_native_vulkan_provider")
if(MSVC)
  target_compile_options(godauldron_native_vulkan_provider PRIVATE /W4)
else()
  target_compile_options(godauldron_native_vulkan_provider PRIVATE -Wall -Wextra -Wpedantic)
endif()
