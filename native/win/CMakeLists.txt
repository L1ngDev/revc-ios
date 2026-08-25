cmake_minimum_required(VERSION 3.24)

project(revc_win LANGUAGES C CXX)

set(REVC_ROOT "${CMAKE_CURRENT_LIST_DIR}/../..")
set(REVC_SRC "${REVC_ROOT}/native/src")
set(REVC_VENDOR "${REVC_ROOT}/native/vendor")
set(REVC_THIRD_PARTY "${REVC_ROOT}/third_party")

# Our FindOpenGL.cmake must win over the stock module inside librw.
list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_LIST_DIR}/cmake")

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# ---------------------------------------------------------------------------
# SDL2 (static)
# ---------------------------------------------------------------------------
set(SDL_SHARED OFF CACHE BOOL "" FORCE)
set(SDL_STATIC ON CACHE BOOL "" FORCE)
set(SDL_TEST OFF CACHE BOOL "" FORCE)
set(SDL_TEST_LIBRARY OFF CACHE BOOL "" FORCE)
set(SDL_DISABLE_INSTALL ON CACHE BOOL "" FORCE)
set(SDL_LIBC ON CACHE BOOL "" FORCE)
add_subdirectory("${REVC_THIRD_PARTY}/SDL" "${CMAKE_CURRENT_BINARY_DIR}/SDL")

# ---------------------------------------------------------------------------
# librw: desktop OpenGL through SDL2
# ---------------------------------------------------------------------------
set(LIBRW_PLATFORM GL3 CACHE STRING "" FORCE)
set(LIBRW_GL3_GFXLIB SDL2 CACHE STRING "" FORCE)
set(LIBRW_TOOLS OFF CACHE BOOL "" FORCE)
set(LIBRW_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LIBRW_INSTALL OFF CACHE BOOL "" FORCE)
add_subdirectory("${REVC_VENDOR}/librw" "${CMAKE_CURRENT_BINARY_DIR}/librw")

# ---------------------------------------------------------------------------
# OpenAL Soft built from source
# ---------------------------------------------------------------------------
include(FetchContent)
set(CMAKE_POLICY_VERSION_MINIMUM 3.5)
set(LIBTYPE STATIC CACHE STRING "" FORCE)
set(ALSOFT_UTILS OFF CACHE BOOL "" FORCE)
set(ALSOFT_NO_CONFIG_UTIL ON CACHE BOOL "" FORCE)
set(ALSOFT_EXAMPLES OFF CACHE BOOL "" FORCE)
set(ALSOFT_TESTS OFF CACHE BOOL "" FORCE)
set(ALSOFT_INSTALL OFF CACHE BOOL "" FORCE)
set(ALSOFT_INSTALL_CONFIG OFF CACHE BOOL "" FORCE)
set(ALSOFT_INSTALL_EXAMPLES OFF CACHE BOOL "" FORCE)
set(ALSOFT_INSTALL_UTILS OFF CACHE BOOL "" FORCE)
set(ALSOFT_UPDATE_BUILD_VERSION OFF CACHE BOOL "" FORCE)
FetchContent_Declare(
    openal
    GIT_REPOSITORY https://github.com/kcat/openal-soft.git
    GIT_TAG 1.24.3
    GIT_SHALLOW TRUE
)
FetchContent_MakeAvailable(openal)

# ---------------------------------------------------------------------------
# mpg123 (mp3/adf radio streams)
# ---------------------------------------------------------------------------
FetchContent_Declare(
    mpg123
    GIT_REPOSITORY https://github.com/madebr/mpg123.git
    GIT_TAG master
    GIT_SHALLOW TRUE
    SOURCE_SUBDIR ports/cmake
)
set(BUILD_PROGRAMS OFF CACHE BOOL "" FORCE)
set(BUILD_LIBOUT123 OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(mpg123)

# ---------------------------------------------------------------------------
# Game sources (SDL2 skeleton, desktop GL)
# ---------------------------------------------------------------------------
file(GLOB_RECURSE REVC_SOURCES CONFIGURE_DEPENDS "${REVC_SRC}/*.cpp")
list(FILTER REVC_SOURCES EXCLUDE REGEX ".*/skel/android/.*")
list(FILTER REVC_SOURCES EXCLUDE REGEX ".*/skel/win/.*")
list(FILTER REVC_SOURCES EXCLUDE REGEX ".*/skel/glfw/.*")
list(FILTER REVC_SOURCES EXCLUDE REGEX ".*/skel/ios/.*")
list(FILTER REVC_SOURCES EXCLUDE REGEX ".*/audio/PoliceRadio\\.cpp$")

set(REVC_GENERATED_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated")
file(MAKE_DIRECTORY "${REVC_GENERATED_DIR}")
file(WRITE "${REVC_GENERATED_DIR}/GitSHA1.cpp" "#define GIT_SHA1 \"win\"\nconst char* g_GIT_SHA1 = GIT_SHA1;\n")
list(APPEND REVC_SOURCES "${REVC_GENERATED_DIR}/GitSHA1.cpp")

add_executable(revc WIN32 ${REVC_SOURCES})

target_include_directories(revc PRIVATE
    "${REVC_SRC}"
    "${REVC_SRC}/core"
    "${REVC_SRC}/fakerw"
    "${REVC_SRC}/skel"
    "${REVC_SRC}/renderer"
    "${REVC_SRC}/math"
    "${REVC_SRC}/rw"
    "${REVC_SRC}/control"
    "${REVC_SRC}/buildings"
    "${REVC_SRC}/animation"
    "${REVC_SRC}/objects"
    "${REVC_SRC}/entities"
    "${REVC_SRC}/modelinfo"
    "${REVC_SRC}/weapons"
    "${REVC_SRC}/collision"
    "${REVC_SRC}/peds"
    "${REVC_SRC}/vehicles"
    "${REVC_SRC}/text"
    "${REVC_SRC}/audio"
    "${REVC_SRC}/audio/eax"
    "${REVC_SRC}/extras"
    "${REVC_SRC}/save"
    "${REVC_VENDOR}/librw"
    "${REVC_THIRD_PARTY}/SDL/include"
    "${REVC_VENDOR}/openal-soft/include"
    "${REVC_VENDOR}/mpg123/include"
)

target_compile_definitions(revc PRIVATE
    RW_GL3
    LIBRW_SDL2
    LIBRW
    AUDIO_OAL
    AUDIO_OAL_USE_MPG123
    USE_OUR_VERSIONING
    NO_HOOK_MALLOC
    CMAKE_BUILD
    _CRT_SECURE_NO_WARNINGS
    _WINDOWS
    WINVER=0x0601
    NOMINMAX
)

if(MSVC)
    target_compile_options(revc PRIVATE /Zc:sizedDealloc- /W3)
else()
    target_compile_options(revc PRIVATE
        -fpermissive
        -g
        -Wall
        -Wno-reorder
        -Wno-unknown-pragmas
        -Wno-unused-function
        -Wno-unused-but-set-variable
        -Wno-unused-value
        -Wno-unused-variable
        -Wno-narrowing
        -static-libgcc
        -static-libstdc++
    )
    target_link_options(revc PRIVATE -static -static-libgcc -static-libstdc++)
endif()

find_package(OpenGL REQUIRED)

target_link_libraries(revc PRIVATE
    librw::librw
    SDL2::SDL2main
    SDL2::SDL2
    OpenAL::OpenAL
    OpenGL::GL
    winmm
    imm32
    version
    setupapi
    shell32
)

if(TARGET libmpg123)
    target_link_libraries(revc PRIVATE libmpg123)
elseif(TARGET MPG123::libmpg123)
    target_link_libraries(revc PRIVATE MPG123::libmpg123)
elseif(TARGET mpg123)
    target_link_libraries(revc PRIVATE mpg123)
else()
    message(FATAL_ERROR "No mpg123 target found")
endif()

# Bundle gamefiles next to the exe for local testing
if(EXISTS "${REVC_ROOT}/../gamefiles")
    add_custom_command(TARGET revc POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_directory
                "${REVC_ROOT}/../gamefiles"
                "$<TARGET_FILE_DIR:revc>/gamefiles"
        COMMENT "Copying gamefiles next to exe"
    )
endif()
