##############################################################################
# This is a gross abuse of CMake to download and build artifacts that we will
# use for testing. It's in CMake because plain Makefiles were getting pretty
# nasty, and CMake's ExternalProject fits what we want to do fairly well.
##############################################################################

cmake_minimum_required(VERSION 3.6)
project(crossenv-artifacts NONE)
include(ExternalProject)

set(DOWNLOAD_DIR "downloads"
    CACHE STRING "cached")
set(HOST_GNU_TRIPLE "aarch64-buildroot-linux-musl"
    CACHE STRING "cached")
set(SHORT_ARCH "aarch64"
    CACHE STRING "cached")
set(BUILD_GNU_TRIPLE "x86_64-linux-gnu"
    CACHE STRING "cached")

##############################################################################
# Toolchain - download and unpack
#
# Doesn't seem to play nice with out-of-source builds, so we'll do it in
# source. Multiple make invokations to avoid redownloading everything for
# each architecture.
#
# A few customizations are stored in musl-cross-make.mk, and we will also
# adjust the dynamic loader's symlink to be a relative path. This way we
# can run it with qemu.
##############################################################################

set(TOOLCHAIN_URL       "NOTSET"
    CACHE STRING "toolchain url")
set(TOOLCHAIN_HASH      "NOTSET"
    CACHE STRING "toolchain hash")
set(TOOLCHAIN           ${CMAKE_INSTALL_PREFIX}/toolchain
    CACHE STRING "toolchain")
set(TOOLCHAIN_BIN       ${TOOLCHAIN}/bin
    CACHE STRING "toolchain")
set(TOOLCHAIN_SYSROOT   ${TOOLCHAIN}/${HOST_GNU_TRIPLE}/sysroot
    CACHE STRING "toolchain")
set(TOOLCHAIN_PATCH     ln -sf libc.so ${TOOLCHAIN_SYSROOT}/lib/ld-musl-${SHORT_ARCH}.so.1
    CACHE STRING "toolchain")
ExternalProject_Add(toolchain
    URL                 ${TOOLCHAIN_URL}
    URL_HASH            ${TOOLCHAIN_HASH}
    DOWNLOAD_DIR        ${DOWNLOAD_DIR}
    SOURCE_DIR          ${TOOLCHAIN}
    CONFIGURE_COMMAND   ""
    BUILD_COMMAND       ${TOOLCHAIN_PATCH}
    INSTALL_COMMAND     ""
)

##############################################################################
# Add some things to the musl toolchain sysroot.
#
# The separate zlib-source is a trick we'll use to avoid downloading the
# project multiple times. A blank DOWNLOAD_COMMAND and the correct DEPENDS
# entry in the later zlib-* targets lets us get around CMake's restriction
# against a nonexistant SOURCE_DIR.
##############################################################################

set(ZLIB_URL    https://www.zlib.net/zlib-1.2.11.tar.gz
    CACHE STRING "cached")
set(ZLIB_HASH   SHA256=c3e5e9fdd5004dcb542feda5ee4f0ff0744628baf8ed2dd5d66f8ca1197cb1a1
    CACHE STRING "cached")
ExternalProject_Add(zlib
    URL                 ${ZLIB_URL}
    URL_HASH            ${ZLIB_HASH}
    DOWNLOAD_DIR        ${DOWNLOAD_DIR}
    INSTALL_DIR         ${TOOLCHAIN_SYSROOT}/usr
    CONFIGURE_COMMAND   ${CMAKE_COMMAND} -E env
                            PATH=${TOOLCHAIN_BIN}:$ENV{PATH}
                            CHOST=${HOST_GNU_TRIPLE}
                            CFLAGS=-fPIC
                        <SOURCE_DIR>/configure
                            --prefix=<INSTALL_DIR>
    BUILD_COMMAND       ${CMAKE_COMMAND} -E env
                            PATH=${TOOLCHAIN_BIN}:$ENV{PATH}
                        make -j8
    INSTALL_COMMAND     ${CMAKE_COMMAND} -E env
                            PATH=${TOOLCHAIN_BIN}:$ENV{PATH}
                        make install
    DEPENDS             toolchain
)

# For libuuid
set(UTIL_LINUX_URL  https://mirrors.edge.kernel.org/pub/linux/utils/util-linux/v2.35/util-linux-2.35.1.tar.xz
    CACHE STRING "cached")
set(UTIL_LINUX_HASH SHA256=d9de3edd287366cd908e77677514b9387b22bc7b88f45b83e1922c3597f1d7f9
    CACHE STRING "cached")
ExternalProject_Add(util-linux
    URL                 ${UTIL_LINUX_URL}
    URL_HASH            ${UTIL_LINUX_HASH}
    DOWNLOAD_DIR        ${DOWNLOAD_DIR}
    INSTALL_DIR         ${TOOLCHAIN_SYSROOT}/usr
    CONFIGURE_COMMAND   ${CMAKE_COMMAND} -E env
                            PATH=${TOOLCHAIN_BIN}:$ENV{PATH}
                        <SOURCE_DIR>/configure
                            --host=${HOST_GNU_TRIPLE}
                            --build=${BUILD_GNU_TRIPLE}
                            --prefix=<INSTALL_DIR>
                            --disable-all-programs
                            --disable-bash-completion
                            --enable-libuuid
    BUILD_COMMAND       ${CMAKE_COMMAND} -E env
                            PATH=${TOOLCHAIN_BIN}:$ENV{PATH}
                        make -j8
    INSTALL_COMMAND     ${CMAKE_COMMAND} -E env
                            PATH=${TOOLCHAIN_BIN}:$ENV{PATH}
                        make install
    DEPENDS             toolchain
)

# for ssl
set(OPENSSL_URL     https://www.openssl.org/source/openssl-1.1.1d.tar.gz
    CACHE STRING "cached")
set(OPENSSL_HASH    SHA256=1e3a91bc1f9dfce01af26026f856e064eab4c8ee0a8f457b5ae30b40b8b711f2
    CACHE STRING "cached")
set(OPENSSL_ARCH    linux-${SHORT_ARCH}
    CACHE STRING "cached")
ExternalProject_Add(openssl
    URL                 ${OPENSSL_URL}
    URL_HASH            ${OPENSSL_HASH}
    DOWNLOAD_DIR        ${DOWNLOAD_DIR}
    INSTALL_DIR         ${TOOLCHAIN_SYSROOT}/usr
    CONFIGURE_COMMAND   ${CMAKE_COMMAND} -E env
                            PATH=${TOOLCHAIN_BIN}:$ENV{PATH}
                        <SOURCE_DIR>/Configure
                            shared
                            zlib-dynamic
                            --prefix=<INSTALL_DIR>
                            ${OPENSSL_ARCH}
    BUILD_COMMAND       ${CMAKE_COMMAND} -E env
                            PATH=${TOOLCHAIN_BIN}:$ENV{PATH}
                            make -j8 CROSS_COMPILE=${HOST_GNU_TRIPLE}-
    INSTALL_COMMAND     ${CMAKE_COMMAND} -E env
                            PATH=${TOOLCHAIN_BIN}:$ENV{PATH}
                        make install_sw install_ssldirs
    DEPENDS             toolchain
                        zlib
)

# for ctypes
set(LIBFFI_URL  https://github.com/libffi/libffi/releases/download/v3.3/libffi-3.3.tar.gz
    CACHE STRING "cached")
set(LIBFFI_HASH SHA256=72fba7922703ddfa7a028d513ac15a85c8d54c8d67f55fa5a4802885dc652056
    CACHE STRING "cached")
ExternalProject_Add(libffi
    URL                 ${LIBFFI_URL}
    URL_HASH            ${LIBFFI_HASH}
    DOWNLOAD_DIR        ${DOWNLOAD_DIR}
    INSTALL_DIR         ${TOOLCHAIN_SYSROOT}/usr
    CONFIGURE_COMMAND   ${CMAKE_COMMAND} -E env
                            PATH=${TOOLCHAIN_BIN}:$ENV{PATH}
                        <SOURCE_DIR>/configure
                            --host=${HOST_GNU_TRIPLE}
                            --build=${BUILD_GNU_TRIPLE}
                            --prefix=<INSTALL_DIR>
                            --disable-static
    BUILD_COMMAND       ${CMAKE_COMMAND} -E env
                            PATH=${TOOLCHAIN_BIN}:$ENV{PATH}
                        make -j8
    INSTALL_COMMAND     ${CMAKE_COMMAND} -E env
                            PATH=${TOOLCHAIN_BIN}:$ENV{PATH}
                        make install
    DEPENDS             toolchain
)

add_custom_target(host-depends
    DEPENDS toolchain
            libffi
            zlib
            openssl
            util-linux
)

##############################################################################
# Python! Finally!
#
# We're using the same download/source trick, but grouping the download step
# as part of build-python
##############################################################################

set(PYTHON_VERSION "3.9.4"
    CACHE STRING "cached")
set(PYTHON_URL "https://www.python.org/ftp/python/3.9.4/Python-3.9.4.tar.xz"
    CACHE STRING "cached")
set(PYTHON_HASH "MD5=2a3dba5fc75b695c45cf1806156e1a97"
    CACHE STRING "cached")
set(PY_INSTALL "${CMAKE_INSTALL_PREFIX}/python/${PYTHON_VERSION}"
    CACHE STRING "cached")
set(BUILD_INSTALL "${PY_INSTALL}/build"
    CACHE STRING "cached")
set(HOST_INSTALL "${PY_INSTALL}/${HOST_GNU_TRIPLE}"
    CACHE STRING "cached")
set(OBJ_DIR "${PY_INSTALL}/obj")
set(HOST_BUILD_DIR ${OBJ_DIR}/${HOST_GNU_TRIPLE})
set(BUILD_BUILD_DIR ${OBJ_DIR}/build)

ExternalProject_Add(python-source
    URL                 ${PYTHON_URL}
    URL_HASH            ${PYTHON_HASH}
    DOWNLOAD_DIR        ${DOWNLOAD_DIR}
    SOURCE_DIR          python-source
    CONFIGURE_COMMAND   ""
    BUILD_COMMAND       ""
    INSTALL_COMMAND     ""
)

ExternalProject_Add(build-python
    INSTALL_DIR         ${BUILD_INSTALL}
    SOURCE_DIR          python-source
    BINARY_DIR          ${BUILD_BUILD_DIR}
    DOWNLOAD_COMMAND    ""
    CONFIGURE_COMMAND   <SOURCE_DIR>/configure
                            --prefix=<INSTALL_DIR>
    BUILD_COMMAND       make -j8
    INSTALL_COMMAND     make install
    DEPENDS             python-source
)

file(RELATIVE_PATH rpath_lib ${HOST_INSTALL}/bin ${TOOLCHAIN_SYSROOT}/lib)
file(RELATIVE_PATH rpath_usrlib ${HOST_INSTALL}/bin ${TOOLCHAIN_SYSROOT}/usr/lib)
set(rpaths
    -Wl,-rpath='\$\${ORIGIN}/${rpath_lib}'
    -Wl,-rpath='\$\${ORIGIN}/${rpath_usrlib}'
    -Wl,-rpath='\$\${ORIGIN}/../lib'
)
string(REPLACE ";" " " rpaths "${rpaths}") # join ;-list with " "

set(BUILD_PYTHON_PATH ${TOOLCHAIN_BIN}:${BUILD_INSTALL}/bin:$ENV{PATH})
ExternalProject_Add(host-python
    INSTALL_DIR         ${HOST_INSTALL}
    DOWNLOAD_COMMAND    ""
    SOURCE_DIR          python-source
    BINARY_DIR          ${HOST_BUILD_DIR}
    CONFIGURE_COMMAND   ${CMAKE_COMMAND} -E env PATH=${BUILD_PYTHON_PATH}
                        <SOURCE_DIR>/configure
                            --prefix=<INSTALL_DIR>
                            --enable-shared
                            --host=${HOST_GNU_TRIPLE}
                            --build=${BUILD_GNU_TRIPLE}
                            --without-ensurepip
                            ac_cv_buggy_getaddrinfo=no
                            ac_cv_file__dev_ptmx=yes
                            ac_cv_file__dev_ptc=no
                            "LDFLAGS=${rpaths}"
    BUILD_COMMAND       ${CMAKE_COMMAND} -E env PATH=${BUILD_PYTHON_PATH}
                        make -j8
    INSTALL_COMMAND     ${CMAKE_COMMAND} -E env PATH=${BUILD_PYTHON_PATH}
                        make install
    DEPENDS             host-depends
                        build-python
)
