# SPDX-License-Identifier: GPL-3.0-or-later
cmake_minimum_required(VERSION 3.20)
project(ExtFS VERSION 0.9.2 LANGUAGES C)

add_library(extfs STATIC core/extfs.c)
target_include_directories(extfs PUBLIC include)
target_compile_features(extfs PUBLIC c_std_11)

add_executable(extfs-tool tools/extfs-tool.c)
target_link_libraries(extfs-tool PRIVATE extfs)

add_executable(extfs-mutate-test tests/mutate_image.c)
target_link_libraries(extfs-mutate-test PRIVATE extfs)

enable_testing()
add_executable(test-extfs tests/test_extfs.c)
target_link_libraries(test-extfs PRIVATE extfs)
add_test(NAME extfs-unit COMMAND test-extfs)
