############################################################################
#
# Copyright (c) 2015 Mark Charlebois. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in
#    the documentation and/or other materials provided with the
#    distribution.
# 3. Neither the name PX4 nor the names of its contributors may be
#    used to endorse or promote products derived from this software
#    without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
# FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
# COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
# BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS
# OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED
# AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
# ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#
############################################################################

if ("${HEXAGON_TOOLS_ROOT}" STREQUAL "")
	message( FATAL_ERROR "HEXAGON_TOOLS_ROOT not set")
endif()

if ("$ENV{HEXAGON_SDK_ROOT}" STREQUAL "")
	message( FATAL_ERROR "HEXAGON_SDK_ROOT not set")
endif()

set(HEXAGON_SDK_ROOT $ENV{HEXAGON_SDK_ROOT})

include_directories(
	${CMAKE_CURRENT_BINARY_DIR}
	${HEXAGON_SDK_ROOT}/inc/stddef
	${HEXAGON_SDK_ROOT}/lib/common/remote/ship/hexagon_Debug
	)

include (CMakeParseArguments)

#
# Hexagon apps are started from an app running on the apps processor 
# of the SoC. An RPC mechanism is used to load the app on the DSP and
# the RPC stubs are generated from a IDL complier (qaic). The RTOS on
# the DSP is QuRT but is often abstraced by the DSPAL APIs.
#
# QURT_BUNDLE is used to specify the files and libraries to build
# in the DSP lib and in the apps application. The generated stubs are
# automatically build into the appropriate target.
#
# For an app named testapp, the result will be:
#    testapp_app     - Run on apps processor
#    testapp.so      - copy to target at /usr/share/date/adsp/
#    testapp_skel.so - copy to target at /usr/share/date/adsp/
#
function(QURT_BUNDLE)
	set(options)
	set(oneValueArgs APP_NAME APPS_COMPILER)
	set(multiValueArgs APPS_SOURCES APPS_LINK_LIBS DSP_SOURCES DSP_LINK_LIBS)
	cmake_parse_arguments(QURT_BUNDLE "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN} )

	message("APP_NAME = ${QURT_BUNDLE_APP_NAME}")

	add_custom_command(
		OUTPUT ${QURT_BUNDLE_APP_NAME}.h ${QURT_BUNDLE_APP_NAME}_skel.c ${QURT_BUNDLE_APP_NAME}_stub.c
		DEPENDS ${QURT_BUNDLE_APP_NAME}.idl
		COMMAND "${HEXAGON_SDK_ROOT}/tools/qaic/Ubuntu14/qaic" "-mdll" "-I" "${HEXAGON_SDK_ROOT}/inc/stddef" "${CMAKE_CURRENT_SOURCE_DIR}/${QURT_BUNDLE_APP_NAME}.idl"
		WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
		)

	add_custom_target(generate_${QURT_BUNDLE_APP_NAME}_stubs ALL
		DEPENDS ${QURT_BUNDLE_APP_NAME}.h ${QURT_BUNDLE_APP_NAME}_skel.c ${QURT_BUNDLE_APP_NAME}_stub.c
		)

	set_source_files_properties(
		${QURT_BUNDLE_APP_NAME}.h
		${QURT_BUNDLE_APP_NAME}_skel.c
		${QURT_BUNDLE_APP_NAME}_stub.c
		PROPERTIES
		GENERATED TRUE
		)

	# Build lib that is run on the DSP
	add_library(${QURT_BUNDLE_APP_NAME} SHARED
		${QURT_BUNDLE_DSP_SOURCES}
		)

	add_dependencies(${QURT_BUNDLE_APP_NAME} generate_${QURT_BUNDLE_APP_NAME}_stubs)

	# Build lib that is run on the DSP invoked by RPC framework
	add_library(${QURT_BUNDLE_APP_NAME}_skel SHARED
		${QURT_BUNDLE_APP_NAME}_skel.c
		)

	set(${APP_APP_NAME}_INCLUDE_DIRS 
		-I${CMAKE_CURRENT_BINARY_DIR}
		-I${HEXAGON_SDK_ROOT}/inc/stddef
		-I${HEXAGON_SDK_ROOT}/lib/common/remote/ship/UbuntuARM_Debug
		)
	set(${APP_APP_NAME}_LINK_DIRS -L${HEXAGON_SDK_ROOT}/lib/common/remote/ship/UbuntuARM_Debug -ladsprpc)

	# Build the apps processor app and RPC stub
	add_custom_command(
		OUTPUT ${QURT_BUNDLE_APP_NAME}_app
		DEPENDS generate_${QURT_BUNDLE_APP_NAME}_stubs
		COMMAND ${QURT_BUNDLE_APPS_COMPILER}  ${${APP_APP_NAME}_INCLUDE_DIRS} -o ${CMAKE_CURRENT_BINARY_DIR}/${QURT_BUNDLE_APP_NAME}_app ${QURT_BUNDLE_APPS_SOURCES} "${CMAKE_CURRENT_BINARY_DIR}/${QURT_BUNDLE_APP_NAME}_stub.c" ${${APP_APP_NAME}_LINK_DIRS}
		WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
		)

	add_custom_target(build_${QURT_BUNDLE_APP_NAME}_apps ALL
		DEPENDS ${QURT_BUNDLE_APP_NAME}_app ${QURT_BUNDLE_APP_NAME}_stub.c
		)

	add_dependencies(${QURT_BUNDLE_APP_NAME}_skel generate_${QURT_BUNDLE_APP_NAME}_stubs build_${QURT_BUNDLE_APP_NAME}_apps)

	add_custom_target(${QURT_BUNDLE_APP_NAME}-load ALL
		DEPENDS ${QURT_BUNDLE_APP_NAME}_app ${QURT_BUNDLE_APP_NAME}
		)
endfunction()

