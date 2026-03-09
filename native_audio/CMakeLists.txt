cmake_minimum_required(VERSION 3.10)
project(audio_input C)

set(CMAKE_C_STANDARD 99)

# Build a shared library that Dart can load via FFI
add_library(audio_input SHARED audio_input.c)

find_package(Threads REQUIRED)
target_link_libraries(audio_input PRIVATE Threads::Threads)

if (ANDROID)
    find_library(log-lib log)
    target_link_libraries(audio_input PRIVATE m ${log-lib})
elseif (APPLE)
    find_library(COREAUDIO_LIB CoreAudio)
    find_library(COREFOUNDATION_LIB CoreFoundation)
    find_library(AUDIOUNIT_LIB AudioUnit)
    target_link_libraries(audio_input PRIVATE 
        ${COREAUDIO_LIB} 
        ${COREFOUNDATION_LIB} 
        ${AUDIOUNIT_LIB}
        m
    )
elseif (UNIX AND NOT APPLE)
    find_library(M_LIB m)
    find_library(DL_LIB dl)
    target_link_libraries(audio_input PRIVATE ${M_LIB} ${DL_LIB})
endif()
