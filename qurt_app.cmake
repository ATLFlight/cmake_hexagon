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

set(TOOLS_ERROR_MSG 
		"The HexagonTools version 6.4.X or 7.2.X must be installed and the environment variable HEXAGON_TOOLS_ROOT must be set"
		"(e.g. export HEXAGON_TOOLS_ROOT=${HOME}/Qualcomm/HEXAGON_Tools/7.2.10/Tools)")

if ("$ENV{HEXAGON_TOOLS_ROOT}" STREQUAL "")
	message(FATAL_ERROR ${TOOLS_ERROR_MSG})
else()
	set(HEXAGON_TOOLS_ROOT $ENV{HEXAGON_TOOLS_ROOT})
endif()

if ("$ENV{HEXAGON_SDK_ROOT}" STREQUAL "")
	message(FATAL_ERROR "HEXAGON_SDK_ROOT not set")
endif()

set(HEXAGON_SDK_ROOT $ENV{HEXAGON_SDK_ROOT})

include_directories(
	${CMAKE_CURRENT_BINARY_DIR}
	${HEXAGON_SDK_ROOT}/inc
	${HEXAGON_SDK_ROOT}/inc/stddef
	${HEXAGON_SDK_ROOT}/lib/common/rpcmem
	${HEXAGON_SDK_ROOT}/lib/common/remote/ship/hexagon_Debug
	)

include (CMakeParseArguments)

#
# Hexagon apps are started from an app running on the apps processor 
# of the SoC. An RPC mechanism is used to load the app on the DSP and
# the RPC stubs are generated from a IDL complier (qaic). The RTOS on
# the DSP is QuRT but is often abstraced by the DSPAL APIs.
#
# The default idl file is <APP_NAME>.idl
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
	set(oneValueArgs APP_NAME IDL_FILE APPS_COMPILER APPS_DEST)
	set(multiValueArgs APPS_SOURCES APPS_LINK_LIBS APPS_INCS DSP_SOURCES DSP_LINK_LIBS DSP_INCS)
	cmake_parse_arguments(QURT_BUNDLE "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN} )

	if ("${QURT_BUNDLE_APP_NAME}" STREQUAL "")
		message(FATAL_ERROR "APP_NAME not specified in call to QURT_BUNDLE")
	endif()

	if ("${QURT_BUNDLE_IDL_FILE}" STREQUAL "")
		set(QURT_BUNDLE_IDL_FILE ${CMAKE_CURRENT_SOURCE_DIR}/${QURT_BUNDLE_APP_NAME}.idl)
	endif()

	get_filename_component(QURT_BUNDLE_IDL_NAME ${QURT_BUNDLE_IDL_FILE} NAME_WE)
	get_filename_component(QURT_BUNDLE_IDL_PATH ${QURT_BUNDLE_IDL_FILE} ABSOLUTE)

	message("APP_NAME = ${QURT_BUNDLE_APP_NAME}")

	# Run the IDL compiler to generate the stubs
	add_custom_command(
		OUTPUT ${QURT_BUNDLE_IDL_NAME}.h ${QURT_BUNDLE_IDL_NAME}_skel.c ${QURT_BUNDLE_IDL_NAME}_stub.c
		DEPENDS ${QURT_BUNDLE_IDL_FILE}
		COMMAND "${HEXAGON_SDK_ROOT}/tools/qaic/Ubuntu14/qaic" "-mdll" "-I" "${HEXAGON_SDK_ROOT}/inc/stddef" "${QURT_BUNDLE_IDL_PATH}"
		WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
		)

	add_custom_target(generate_${QURT_BUNDLE_IDL_NAME}_stubs ALL
		DEPENDS ${QURT_BUNDLE_IDL_NAME}.h ${QURT_BUNDLE_IDL_NAME}_skel.c ${QURT_BUNDLE_IDL_NAME}_stub.c
		)

	set_source_files_properties(
		${QURT_BUNDLE_IDL_NAME}.h
		${QURT_BUNDLE_IDL_NAME}_skel.c
		${QURT_BUNDLE_IDL_NAME}_stub.c
		PROPERTIES
		GENERATED TRUE
		)

	# Process Apps processor files
	if (NOT "${QURT_BUNDLE_APPS_SOURCES}" STREQUAL "")
		# Build lib that is run on the DSP invoked by RPC framework
		# Set default install path of apps processor executable
		if ("${QURT_BUNDLE_APPS_DEST}" STREQUAL "")
			set(QURT_BUNDLE_APPS_DEST "/home/linaro")
		endif()

		# Make sure apps compiler is provided
		if ("${QURT_BUNDLE_APPS_COMPILER}" STREQUAL "")
			message(FATAL_ERROR "APPS_COMPILER not specified in call to QURT_BUNDLE")
		endif()

		set(${QURT_BUNDLE_APP_NAME}_INCLUDE_DIRS 
			-I${CMAKE_CURRENT_BINARY_DIR}
			-I${HEXAGON_SDK_ROOT}/inc/stddef
			-I${HEXAGON_SDK_ROOT}/lib/common/rpcmem
			-I${HEXAGON_SDK_ROOT}/lib/common/adspmsgd/ship/UbuntuARM_Debug
			-I${HEXAGON_SDK_ROOT}/lib/common/remote/ship/UbuntuARM_Debug
			${QURT_BUNDLE_APPS_INCS}
			)
		set(${QURT_BUNDLE_APP_NAME}_LINK_DIRS -L${HEXAGON_SDK_ROOT}/lib/common/remote/ship/UbuntuARM_Debug -ladsprpc)

		# Build the apps processor app and RPC stub using the provided ${QURT_BUNDLE_APPS_COMPILER}
		add_custom_command(
			OUTPUT ${QURT_BUNDLE_APP_NAME}_app
			DEPENDS generate_${QURT_BUNDLE_IDL_NAME}_stubs
			COMMAND ${QURT_BUNDLE_APPS_COMPILER}  ${${QURT_BUNDLE_APP_NAME}_INCLUDE_DIRS} -o ${CMAKE_CURRENT_BINARY_DIR}/${QURT_BUNDLE_APP_NAME}_app ${QURT_BUNDLE_APPS_SOURCES} "${CMAKE_CURRENT_BINARY_DIR}/${QURT_BUNDLE_IDL_NAME}_stub.c" ${${QURT_BUNDLE_APP_NAME}_LINK_DIRS}
			WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
			)

		add_custom_target(build_${QURT_BUNDLE_APP_NAME}_apps ALL
			DEPENDS ${QURT_BUNDLE_APP_NAME}_app ${QURT_BUNDLE_IDL_NAME}_stub.c
			)
		add_dependencies(build_${QURT_BUNDLE_APP_NAME}_apps generate_${QURT_BUNDLE_IDL_NAME}_stubs)

		# Add a rule to load the files onto the target
		add_custom_target(${QURT_BUNDLE_APP_NAME}_app-load
			DEPENDS ${QURT_BUNDLE_APP_NAME}_app
			COMMAND adb wait-for-devices
			COMMAND adb push ${QURT_BUNDLE_APP_NAME}_app ${QURT_BUNDLE_APPS_DEST}
			COMMAND echo "Pushed ${QURT_BUNDLE_APP_NAME}_app to ${QURT_BUNDLE_APPS_DEST}"
			)
	endif()

	# Process DSP files
	if (NOT "${QURT_BUNDLE_DSP_SOURCES}" STREQUAL "")
		message("DSP_INCS = ${QURT_BUNDLE_DSP_INCS}")

		# Build lib that is run on the DSP
		add_library(${QURT_BUNDLE_APP_NAME} SHARED
			${QURT_BUNDLE_DSP_SOURCES}
			)

		if (NOT "${QURT_BUNDLE_DSP_INCS}" STREQUAL "")
			target_include_directories(${QURT_BUNDLE_APP_NAME} PUBLIC ${QURT_BUNDLE_DSP_INCS})
		endif()

		message("QURT_BUNDLE_DSP_LINK_LIBS = ${QURT_BUNDLE_DSP_LINK_LIBS}")
		target_link_libraries(${QURT_BUNDLE_APP_NAME}
			${QURT_BUNDLE_DSP_LINK_LIBS}
			)

		add_dependencies(${QURT_BUNDLE_APP_NAME} generate_${QURT_BUNDLE_IDL_NAME}_stubs)

		add_library(${QURT_BUNDLE_IDL_NAME}_skel SHARED
			${QURT_BUNDLE_IDL_NAME}_skel.c
			)

		target_link_libraries(${QURT_BUNDLE_IDL_NAME}_skel
			${QURT_BUNDLE_APP_NAME}
			)
		add_dependencies(${QURT_BUNDLE_IDL_NAME}_skel generate_${QURT_BUNDLE_IDL_NAME}_stubs)

		add_custom_target(build_${QURT_BUNDLE_APP_NAME}_dsp ALL
			DEPENDS ${QURT_BUNDLE_APP_NAME} ${QURT_BUNDLE_IDL_NAME}_skel
			)

		# Add a rule to load the files onto the target
		add_custom_target(lib${QURT_BUNDLE_APP_NAME}-load
			DEPENDS ${QURT_BUNDLE_APP_NAME}
			COMMAND adb wait-for-devices
			COMMAND adb push lib${QURT_BUNDLE_IDL_NAME}_skel.so /usr/share/data/adsp/
			COMMAND adb push lib${QURT_BUNDLE_APP_NAME}.so /usr/share/data/adsp/
			COMMAND adb push ${TOOLSLIB}/libgcc.so /usr/share/data/adsp/
			COMMAND adb push ${TOOLSLIB}/libc.so /usr/share/data/adsp/
			COMMAND echo "Pushed lib${QURT_BUNDLE_APP_NAME}.so and dependencies to /usr/share/data/adsp/"
			)
		endif()

	# Create a target to load both Apps and DSP code on the target
	if ((NOT "${QURT_BUNDLE_APPS_SOURCES}" STREQUAL "") AND (NOT "${QURT_BUNDLE_DSP_SOURCES}" STREQUAL ""))
		# Add a rule to load the files onto the target
		add_custom_target(${QURT_BUNDLE_APP_NAME}-load
			DEPENDS ${QURT_BUNDLE_APP_NAME}_app-load lib${QURT_BUNDLE_APP_NAME}-load
			COMMAND echo "Pushed ${QURT_BUNDLE_APP_NAME}"
			)
	endif()

endfunction()

