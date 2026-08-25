cmake_minimum_required(VERSION 3.24)

project(revc_ios LANGUAGES C CXX OBJCXX)

set(REVC_ROOT "${CMAKE_CURRENT_LIST_DIR}/../..")
set(REVC_SRC "${REVC_ROOT}/native/src")
set(REVC_VENDOR "${REVC_ROOT}/native/vendor")
set(REVC_THIRD_PARTY "${REVC_ROOT}/third_party")

# Our FindOpenGL.cmake must win over the stock module inside librw.
list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_LIST_DIR}/cmake")

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_OBJCXX_STANDARD 11)
set(CMAKE_OBJCXX_STANDARD_REQUIRED ON)

# ---------------------------------------------------------------------------
# SDL2 (iOS platform is supported out of the box)
# ---------------------------------------------------------------------------
# Static so everything links into the executable: iOS apps cannot
# load external dylibs unless they are embedded frameworks.
set(SDL_SHARED OFF CACHE BOOL "" FORCE)
set(SDL_STATIC ON CACHE BOOL "" FORCE)
set(SDL_TEST OFF CACHE BOOL "" FORCE)
set(SDL_TEST_LIBRARY OFF CACHE BOOL "" FORCE)
set(SDL_DISABLE_INSTALL ON CACHE BOOL "" FORCE)
add_subdirectory("${REVC_THIRD_PARTY}/SDL" "${CMAKE_CURRENT_BINARY_DIR}/SDL")

# ---------------------------------------------------------------------------
# librw: OpenGL ES3 backend through SDL2 context
# ---------------------------------------------------------------------------
set(LIBRW_PLATFORM GL3 CACHE STRING "" FORCE)
set(LIBRW_GL3_GFXLIB SDL2 CACHE STRING "" FORCE)
set(LIBRW_TOOLS OFF CACHE BOOL "" FORCE)
set(LIBRW_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LIBRW_INSTALL OFF CACHE BOOL "" FORCE)
add_subdirectory("${REVC_VENDOR}/librw" "${CMAKE_CURRENT_BINARY_DIR}/librw")

# ---------------------------------------------------------------------------
# OpenAL Soft built from source for iOS
# ---------------------------------------------------------------------------
include(FetchContent)
# openal-soft's old cmake_minimum_required() trips modern CMake; allow it.
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
    GIT_TAG 1.23.1
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
# Game sources (same tree as Android, but with the SDL2 + iOS skeletons)
# ---------------------------------------------------------------------------
file(GLOB_RECURSE REVC_SOURCES CONFIGURE_DEPENDS "${REVC_SRC}/*.cpp")
list(FILTER REVC_SOURCES EXCLUDE REGEX ".*/skel/android/.*")
list(FILTER REVC_SOURCES EXCLUDE REGEX ".*/skel/win/.*")
list(FILTER REVC_SOURCES EXCLUDE REGEX ".*/skel/glfw/.*")
list(FILTER REVC_SOURCES EXCLUDE REGEX ".*/audio/PoliceRadio\\.cpp$")

list(APPEND REVC_SOURCES
    "${REVC_SRC}/skel/ios/iospath.mm"
    "${REVC_SRC}/skel/ios/ios_launcher.mm"
)

set(REVC_GENERATED_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated")
file(MAKE_DIRECTORY "${REVC_GENERATED_DIR}")
file(WRITE "${REVC_GENERATED_DIR}/GitSHA1.cpp" "#define GIT_SHA1 \"ios\"\nconst char* g_GIT_SHA1 = GIT_SHA1;\n")
list(APPEND REVC_SOURCES "${REVC_GENERATED_DIR}/GitSHA1.cpp")

add_executable(revc MACOSX_BUNDLE ${REVC_SOURCES})

target_include_directories(revc PRIVATE
    "${REVC_SRC}"
    "${REVC_SRC}/core"
    "${REVC_SRC}/fakerw"
    "${REVC_SRC}/skel"
    "${REVC_SRC}/skel/ios"
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
    POSIX=1
    _POSIX=1
    GNUC
    NO_HOOK_MALLOC
    CMAKE_BUILD
)

target_compile_options(revc PRIVATE
    -fpermissive
    -funwind-tables
    -g
    -Wall
    -Wno-reorder
    -Wno-unknown-pragmas
    -Wno-unused-function
    -Wno-unused-but-set-variable
    -Wno-unused-value
    -Wno-unused-variable
)

find_library(OPENGLES_FRAMEWORK OpenGLES REQUIRED)
find_library(FOUNDATION_FRAMEWORK Foundation REQUIRED)
find_library(UIKIT_FRAMEWORK UIKit REQUIRED)
find_library(AUDIOTOOLBOX_FRAMEWORK AudioToolbox REQUIRED)
find_library(COREAUDIO_FRAMEWORK CoreAudio REQUIRED)
find_library(QUARTZCORE_FRAMEWORK QuartzCore REQUIRED)

target_link_libraries(revc PRIVATE
    librw::librw
    SDL2::SDL2main
    SDL2::SDL2
    OpenAL::OpenAL
    ${OPENGLES_FRAMEWORK}
    ${FOUNDATION_FRAMEWORK}
    ${UIKIT_FRAMEWORK}
    ${AUDIOTOOLBOX_FRAMEWORK}
    ${COREAUDIO_FRAMEWORK}
    ${QUARTZCORE_FRAMEWORK}
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

set_target_properties(revc PROPERTIES
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist.in"
    MACOSX_BUNDLE_GUI_IDENTIFIER "com.litmobile.revc"
    MACOSX_BUNDLE_BUNDLE_VERSION "0.1.0"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "0.1.0"
    XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO"
    XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY ""
    XCODE_ATTRIBUTE_IPHONEOS_DEPLOYMENT_TARGET "14.0"
    XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2"
    XCODE_ATTRIBUTE_ENABLE_BITCODE "NO"
    XCODE_ATTRIBUTE_STRIP_INSTALLED_PRODUCT "NO"
    XCODE_ATTRIBUTE_COPY_PHASE_STRIP "NO"
    XCODE_ATTRIBUTE_DEPLOYMENT_POSTPROCESSING "NO"
)

# Bundle the repository gamefiles into the app (read-only base data).
if(EXISTS "${REVC_ROOT}/gamefiles")
    add_custom_command(TARGET revc POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_directory
                "${REVC_ROOT}/gamefiles"
                "$<TARGET_BUNDLE_CONTENT_DIR:revc>/gamefiles"
        COMMENT "Bundling gamefiles into app bundle"
    )
endif()

# Mobile on-screen controls textures (same files the Android app ships)
if(EXISTS "${REVC_ROOT}/app/src/main/assets/mobileui")
    add_custom_command(TARGET revc POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_directory
                "${REVC_ROOT}/app/src/main/assets/mobileui"
                "$<TARGET_BUNDLE_CONTENT_DIR:revc>/mobileui"
        COMMENT "Bundling mobile UI textures"
    )
endif()

# Launcher artwork (taken 1:1 from the NORMSOURCE launcher) into bundle/launcher
file(GLOB REVC_LAUNCHER_ASSETS "${CMAKE_CURRENT_SOURCE_DIR}/launcher_assets/*")
if(REVC_LAUNCHER_ASSETS)
    set_source_files_properties(${REVC_LAUNCHER_ASSETS} PROPERTIES
        MACOSX_PACKAGE_LOCATION "launcher"
    )
    target_sources(revc PRIVATE ${REVC_LAUNCHER_ASSETS})
endif()
