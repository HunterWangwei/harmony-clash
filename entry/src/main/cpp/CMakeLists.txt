cmake_minimum_required(VERSION 3.5.0)
project(clashbridge)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

# Prebuilt Go core, produced by tools/build-core.js into entry/libs/<abi>/.
add_library(mihomo SHARED IMPORTED)
set_target_properties(mihomo PROPERTIES
    IMPORTED_LOCATION ${NATIVERENDER_ROOT_PATH}/../../../libs/${OHOS_ARCH}/libmihomo.so)

add_library(clashbridge SHARED napi_init.cpp)
target_include_directories(clashbridge PRIVATE ${NATIVERENDER_ROOT_PATH}/include)
target_link_libraries(clashbridge PUBLIC libace_napi.z.so libhilog_ndk.z.so mihomo)
