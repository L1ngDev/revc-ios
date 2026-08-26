cmake_minimum_required(VERSION 3.12)
project(reVC-ios C CXX)

# ---------------------------------------------------------------------------
# iOS target settings
# (these can be overridden from the command line / CI)
# ---------------------------------------------------------------------------
if(NOT CMAKE_SYSTEM_NAME)
    set(CMAKE_SYSTEM_NAME iOS)
endif()
set(CMAKE_OSX_SYSROOT iphoneos CACHE STRING "" FORCE)
set(CMAKE_OSX_ARCHITECTURES arm64 CACHE STRING "" FORCE)
set(CMAKE_XCODE_ATTRIBUTE_IPHONEOS_DEPLOYMENT_TARGET "12.0" CACHE STRING "" FORCE)
set(CMAKE_OSX_DEPLOYMENT_TARGET "12.0" CACHE STRING "" FORCE)
# We build an unsigned .app (user signs/sideloads via AltStore/Sideloadly)
set(CMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED NO CACHE STRING "" FORCE)
set(CMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY "" CACHE STRING "" FORCE)
set(CMAKE_XCODE_ATTRIBUTE_DEVELOPMENT_TEAM "" CACHE STRING "" FORCE)

set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

set(NATIVE_DIR ${CMAKE_SOURCE_DIR}/../native)
set(VENDOR_DIR ${NATIVE_DIR}/vendor)

# ---------------------------------------------------------------------------
# Rendering: librw (RenderWare reimplementation) in GL3 + SDL2 backend
# ---------------------------------------------------------------------------
set(LIBRW_PLATFORM "GL3" CACHE STRING "librw platform")
set(LIBRW_GL3_GFXLIB "SDL2" CACHE STRING "librw gfxlib")
set(LIBRW_INSTALL OFF CACHE BOOL "" FORCE)
add_subdirectory(${VENDOR_DIR}/librw librw_build)

# ---------------------------------------------------------------------------
# SDL2 (vendored, built as part of the project)
# ---------------------------------------------------------------------------
add_subdirectory(${VENDOR_DIR}/SDL SDL_build)

# ---------------------------------------------------------------------------
# Audio: system OpenAL (iOS ships OpenAL.framework)
# ---------------------------------------------------------------------------
find_library(OPENAL_LIB OpenAL)
if(NOT OPENAL_LIB)
    message(FATAL_ERROR "OpenAL.framework not found on iOS SDK")
endif()
add_library(OpenAL::OpenAL UNKNOWN IMPORTED)
set_target_properties(OpenAL::OpenAL PROPERTIES IMPORTED_LOCATION ${OPENAL_LIB})

find_package(Threads REQUIRED)

# ---------------------------------------------------------------------------
# mpg123 (vendored)
# ---------------------------------------------------------------------------
set(MPG123_BUILD_LIBOUT ON CACHE BOOL "" FORCE)
set(MPG123_ENABLE_TESTS OFF CACHE BOOL "" FORCE)
if(EXISTS "${VENDOR_DIR}/mpg123/CMakeLists.txt")
    add_subdirectory(${VENDOR_DIR}/mpg123 mpg123_build)
endif()

# ---------------------------------------------------------------------------
# reVC game sources (mirrors native/src/CMakeLists.txt globbing)
# ---------------------------------------------------------------------------
file(GLOB_RECURSE REVC_SOURCES "${NATIVE_DIR}/src/*.cpp" "${NATIVE_DIR}/src/*.h" "${NATIVE_DIR}/src/*.rc")

# generate GitSHA1 like the upstream build does
function(reVC_header_directories RETURN_LIST)
    file(GLOB_RECURSE ALL_SRCS "${NATIVE_DIR}/src/*.h" "${NATIVE_DIR}/src/*.cpp" "${NATIVE_DIR}/src/*.c")
    set(RELDIRS)
    foreach(SRC ${ALL_SRCS})
        file(RELATIVE_PATH RELSRC "${NATIVE_DIR}/src" "${SRC}")
        get_filename_component(RELDIR "${RELSRC}" DIRECTORY)
        list(APPEND RELDIRS ${RELDIR})
    endforeach()
    list(REMOVE_DUPLICATES RELDIRS)
    set(${RETURN_LIST} ${RELDIRS} PARENT_SCOPE)
endfunction()
reVC_header_directories(REVC_INCLUDES)

add_executable(reVC MACOSX_BUNDLE ${REVC_SOURCES})

target_include_directories(reVC
    PRIVATE
        ${NATIVE_DIR}/src
        ${REVC_INCLUDES}
        ${VENDOR_DIR}/librw/include
        ${VENDOR_DIR}/openal-soft/include
        ${VENDOR_DIR}/mpg123/include
        ${VENDOR_DIR}/ogg/include
        ${VENDOR_DIR}/opus/include
        ${VENDOR_DIR}/opusfile/include
)

target_compile_definitions(reVC
    PRIVATE
        LIBRW
        AUDIO_OAL
        CMAKE_BUILD
        USE_OUR_VERSIONING
        $<IF:$<CONFIG:DEBUG>,DEBUG,NDEBUG>
        CMAKE_NO_AUTOLINK
)

target_link_libraries(reVC
    PRIVATE
        librw::librw
        SDL2::SDL2
        OpenAL::OpenAL
        Threads::Threads
)

# GitSHA1 stub (used only for the version string in the UI)
set(GITSHA1_CPP ${CMAKE_CURRENT_BINARY_DIR}/GitSHA1.cpp)
file(WRITE ${GITSHA1_CPP}
"#include \"GitSHA1.h\"\nconst char* GetGitSHA1(){ return \"ios-build\"; }\n")
target_sources(reVC PRIVATE ${GITSHA1_CPP})

if(TARGET MPG123::libmpg123)
    target_link_libraries(reVC PRIVATE MPG123::libmpg123)
elseif(TARGET mpg123)
    target_link_libraries(reVC PRIVATE mpg123)
endif()

# ---------------------------------------------------------------------------
# Bundle setup: icon + Info.plist + copy game data next to the executable
# ---------------------------------------------------------------------------
set_target_properties(reVC PROPERTIES
    MACOSX_BUNDLE TRUE
    MACOSX_BUNDLE_INFO_PLIST ${CMAKE_SOURCE_DIR}/Info.plist
    XCODE_ATTRIBUTE_ASSETCATALOG_COMPILER_APPICON_NAME "AppIcon"
    XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "com.litmobile.revc"
    XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2"
)

# Copy the asset catalog (AppIcon) into the bundle resources
set(APPICON_DIR ${CMAKE_SOURCE_DIR}/Assets.xcassets)
target_sources(reVC PRIVATE ${APPICON_DIR})
set_source_files_properties(${APPICON_DIR}
    PROPERTIES MACOSX_PACKAGE_LOCATION Resources)

# Copy reVC gamefiles (reVC-specific files) into the bundle so the game can find them
if(EXISTS "${NATIVE_DIR}/../gamefiles")
    add_custom_command(TARGET reVC POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_directory
            "${NATIVE_DIR}/../gamefiles"
            "$<TARGET_FILE_DIR:reVC>/gamefiles"
        COMMENT "Copying reVC gamefiles into app bundle"
    )
endif()
