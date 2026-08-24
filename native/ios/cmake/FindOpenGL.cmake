# Minimal OpenGL "found" shim for iOS.
# There is no OpenGL.framework on iOS, rendering goes through OpenGLES.
# This provides the targets librw expects (OpenGL::GL) so that
# find_package(OpenGL) succeeds inside librw's CMakeLists.txt.

find_library(OPENGLES_FRAMEWORK NAMES OpenGLES)

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(OpenGL
    REQUIRED_VARS OPENGLES_FRAMEWORK
)

if(OpenGL_FOUND AND NOT TARGET OpenGL::GL)
    add_library(OpenGL::GL INTERFACE IMPORTED)
    set_property(TARGET OpenGL::GL PROPERTY INTERFACE_LINK_LIBRARIES
        "${OPENGLES_FRAMEWORK}"
    )
endif()

if(OpenGL_FOUND AND NOT TARGET OpenGL::OpenGL)
    add_library(OpenGL::OpenGL INTERFACE IMPORTED)
    set_property(TARGET OpenGL::OpenGL PROPERTY INTERFACE_LINK_LIBRARIES
        "${OPENGLES_FRAMEWORK}"
    )
endif()

if(OpenGL_FOUND AND NOT TARGET OpenGL::EGL)
    add_library(OpenGL::EGL INTERFACE IMPORTED)
    set_property(TARGET OpenGL::EGL PROPERTY INTERFACE_LINK_LIBRARIES
        "${OPENGLES_FRAMEWORK}"
    )
endif()
