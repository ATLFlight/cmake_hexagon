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

# Overview:
# Hexagon/QuRT apps are built in 2 parts, the part that runs on the
# application (apps) processor, and the library that is invoked on the DSP.
#
# PREREQUISITES:
#
# Environment variables:
#	HEXAGON_TOOLS_ROOT
#	HEXAGON_SDK_ROOT
#
# USAGE:
#
# For simple DSP apps that use a simple apps processor app to invoke the
# DSP lib, the QURT_BUNDLE function can be used.
#
# When the apps proc app requires its own cmake build, the RPC stub functions
# can be generated with FASTRPC_STUB_GEN. The DSP lib can be built with the
# QURT_LIB function and the apps proc app can be built with the help of the
# the FASTRPC_ARM_APP_DEPS_GEN function.
#
# Build targets to load the apps proc app and DSP libs are created from the
# rules below. Look for resulting make targets ending in -load.


set(TOOLS_ERROR_MSG 
		"The HexagonTools version 6.4.X or 7.2.X must be installed and the environment variable HEXAGON_TOOLS_ROOT must be set"
		"(e.g. export HEXAGON_TOOLS_ROOT=$ENV{HOME}/Qualcomm/HEXAGON_Tools/7.2.10/Tools)")

if ("$ENV{HEXAGON_TOOLS_ROOT}" STREQUAL "")
	message(FATAL_ERROR ${TOOLS_ERROR_MSG})
else()
	set(HEXAGON_TOOLS_ROOT $ENV{HEXAGON_TOOLS_ROOT})
endif()

if ("$ENV{HEXAGON_SDK_ROOT}" STREQUAL "")
	message(FATAL_ERROR "HEXAGON_SDK_ROOT not set")
endif()

set(HEXAGON_SDK_ROOT $ENV{HEXAGON_SDK_ROOT})

set(FASTRPC_DSP_INCLUDES
	${HEXAGON_SDK_ROOT}/inc
	${HEXAGON_SDK_ROOT}/inc/stddef
	${HEXAGON_SDK_ROOT}/lib/common/rpcmem
	${HEXAGON_SDK_ROOT}/lib/common/remote/ship/hexagon_Debug
	)

set(FASTRPC_ARM_LINUX_INCLUDES
	-I${HEXAGON_SDK_ROOT}/inc/stddef
	-I${HEXAGON_SDK_ROOT}/lib/common/rpcmem
	-I${HEXAGON_SDK_ROOT}/lib/common/adspmsgd/ship/UbuntuARM_Debug
	-I${HEXAGON_SDK_ROOT}/lib/common/remote/ship/UbuntuARM_Debug
	)

set(FASTRPC_ARM_LIBS 
	-L${HEXAGON_SDK_ROOT}/lib/common/remote/ship/UbuntuARM_Debug -ladsprpc
	${HEXAGON_SDK_ROOT}/lib/common/rpcmem/UbuntuARM_Debug/rpcmem.a
	)
	
include_directories(
	${CMAKE_CURRENT_BINARY_DIR}
	)

function(FASTRPC_STUB_GEN IDLFILE)
	get_filename_component(FASTRPC_IDL_NAME ${IDLFILE} NAME_WE)
	get_filename_component(FASTRPC_IDL_PATH ${IDLFILE} ABSOLUTE)

	# Run the IDL compiler to generate the stubs
	add_custom_command(
		OUTPUT ${FASTRPC_IDL_NAME}.h ${FASTRPC_IDL_NAME}_skel.c ${FASTRPC_IDL_NAME}_stub.c
		DEPENDS ${FASTRPC_IDL_PATH}
		COMMAND "${HEXAGON_SDK_ROOT}/tools/qaic/Ubuntu14/qaic" "-mdll" "-I" "${HEXAGON_SDK_ROOT}/inc/stddef" "${FASTRPC_IDL_PATH}"
		WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
		)

	message("Generated generate_${FASTRPC_IDL_NAME}_stubs target")

	add_custom_target(generate_${FASTRPC_IDL_NAME}_stubs ALL
		DEPENDS ${FASTRPC_IDL_NAME}.h ${FASTRPC_IDL_NAME}_skel.c ${FASTRPC_IDL_NAME}_stub.c
		)

	set_source_files_properties(
		${FASTRPC_IDL_NAME}.h
		${FASTRPC_IDL_NAME}_skel.c
		${FASTRPC_IDL_NAME}_stub.c
		PROPERTIES
		GENERATED TRUE
		)
endfunction()

include (CMakeParseArguments)

function (FASTRPC_ARM_APP_DEPS_GEN)
	set(oneValueArgs APP_NAME IDL_NAME APP_DEST)
	cmake_parse_arguments(FASTRPC_ARM_APP_DEPS_GEN "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN} )

	# Build lib that is run on the DSP invoked by RPC framework
	# Set default install path of apps processor executable
	if ("${FASTRPC_ARM_APP_DEPS_GEN_APP_DEST}" STREQUAL "")
		set(FASTRPC_ARM_APP_DEPS_GEN_APP_DEST "/home/linaro")
	endif()

	add_custom_target(build_${FASTRPC_ARM_APP_DEPS_GEN_APP_NAME}_apps ALL
		DEPENDS ${FASTRPC_ARM_APP_DEPS_GEN_APP_NAME} ${FASTRPC_ARM_APP_DEPS_GEN_IDL_NAME}_stub.c
		)
	add_dependencies(build_${FASTRPC_ARM_APP_DEPS_GEN_APP_NAME}_apps generate_${FASTRPC_ARM_APP_DEPS_GEN_IDL_NAME}_stubs)

	# Add a rule to load the files onto the target
	add_custom_target(${FASTRPC_ARM_APP_DEPS_GEN_APP_NAME}-load
		DEPENDS ${FASTRPC_ARM_APP_DEPS_GEN_APP_NAME}
		COMMAND adb wait-for-devices
		COMMAND adb push ${FASTRPC_ARM_APP_DEPS_GEN_APP_NAME} ${FASTRPC_ARM_APP_DEPS_GEN_APP_DEST}
		COMMAND echo "Pushed ${FASTRPC_ARM_APP_DEPS_GEN_APP_NAME} to ${FASTRPC_ARM_APP_DEPS_GEN_APP_DEST}"
		)
endfunction()

# Process DSP files
function (QURT_LIB)
	set(options)
	set(oneValueArgs APP_NAME IDL_NAME)
	set(multiValueArgs SOURCES LINK_LIBS INCS)
	cmake_parse_arguments(QURT_LIB "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN} )

	if ("${QURT_LIB_SOURCES}" STREQUAL "")
		message(FATAL_ERROR "QURT_LIB called without SOURCES")
	endif()

	if ("${QURT_LIB_IDL_NAME}" STREQUAL "")
		message(FATAL_ERROR "QURT_LIB called without IDL_NAME")
	endif()

	include_directories(
		${CMAKE_CURRENT_BINARY_DIR}
		${FASTRPC_DSP_INCLUDES}
		)

	message("QURT_LIB_INCS = ${QURT_LIB_INCS}")

	# Build lib that is run on the DSP
	add_library(${QURT_LIB_APP_NAME} SHARED
		${QURT_LIB_SOURCES}
		)

	if (NOT "${QURT_LIB_INCS}" STREQUAL "")
		target_include_directories(${QURT_LIB_APP_NAME} PUBLIC ${QURT_LIB_INCS})
	endif()

	message("QURT_LIB_LINK_LIBS = ${QURT_LIB_LINK_LIBS}")

	target_link_libraries(${QURT_LIB_APP_NAME}
		${QURT_LIB_LINK_LIBS}
		)

	add_dependencies(${QURT_LIB_APP_NAME} generate_${QURT_LIB_IDL_NAME}_stubs)

	add_library(${QURT_LIB_IDL_NAME}_skel MODULE
		${QURT_LIB_IDL_NAME}_skel.c
		)

	target_link_libraries(${QURT_LIB_IDL_NAME}_skel
		${QURT_LIB_APP_NAME}
		)
	add_dependencies(${QURT_LIB_IDL_NAME}_skel generate_${QURT_LIB_IDL_NAME}_stubs)

	add_custom_target(build_${QURT_LIB_APP_NAME}_dsp ALL
		DEPENDS ${QURT_LIB_IDL_NAME} ${QURT_LIB_IDL_NAME}_skel
		)

	# Add a rule to load the files onto the target that run in the DSP
	add_custom_target(lib${QURT_LIB_APP_NAME}-load
		DEPENDS ${QURT_LIB_APP_NAME}
		COMMAND adb wait-for-devices
		COMMAND adb push lib${QURT_LIB_IDL_NAME}_skel.so /usr/share/data/adsp/
		COMMAND adb push lib${QURT_LIB_APP_NAME}.so /usr/share/data/adsp/
		COMMAND echo "Pushed lib${QURT_LIB_APP_NAME}.so and dependencies to /usr/share/data/adsp/"
		)
endfunction()

# Process Apps proc app source and libs
function (QURT_APP)
	set(oneValueArgs APP_NAME IDL_NAME APP_DEST)
	set(multiValueArgs SOURCES LINK_LIBS INCS)
	cmake_parse_arguments(QURT_APP "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN} )

	if ("${QURT_APP_SOURCES}" STREQUAL "")
		message(FATAL_ERROR "QURT_APP called without SOURCES")
	endif()

	if ("${QURT_APP_IDL_NAME}" STREQUAL "")
		message(FATAL_ERROR "QURT_APP called without IDL_NAME")
	endif()

	include_directories(
		${CMAKE_CURRENT_BINARY_DIR}
		${FASTRPC_DSP_INCLUDES}
		)

	message("QURT_APP_INCS = ${QURT_APP_INCS}")

	# Build lib that is run on the DSP
	add_executable(${QURT_APP_APP_NAME}
		${QURT_APP_SOURCES}
		)

	if (NOT "${QURT_APP_INCS}" STREQUAL "")
		target_include_directories(${QURT_APP_APP_NAME} PUBLIC ${QURT_APP_INCS})
	endif()

	message("QURT_APP_LINK_LIBS = ${QURT_APP_LINK_LIBS}")

	target_link_libraries(${QURT_APP_APP_NAME}
		${QURT_APP_LINK_LIBS}
		)

	FASTRPC_ARM_APP_DEPS_GEN(
		APP_NAME ${QURT_APP_APP_NAME}
		IDL_NAME ${QURT_APP_IDL_NAME}
		APP_DEST ${QURT_APP_APP_DEST})

endfunction()

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
	set(oneValueArgs APP_NAME IDL_FILE APPS_COMPILER APP_DEST)
	set(multiValueArgs APPS_SOURCES APPS_LINK_LIBS APPS_INCS DSP_SOURCES DSP_LINK_LIBS DSP_INCS)
	cmake_parse_arguments(QURT_BUNDLE "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN} )

	if ("${QURT_BUNDLE_APP_NAME}" STREQUAL "")
		message(FATAL_ERROR "APP_NAME not specified in call to QURT_BUNDLE")
	endif()

	if ("${QURT_BUNDLE_IDL_FILE}" STREQUAL "")
		set(QURT_BUNDLE_IDL_FILE ${CMAKE_CURRENT_SOURCE_DIR}/${QURT_BUNDLE_APP_NAME}.idl)
	endif()

	FASTRPC_STUB_GEN(${QURT_BUNDLE_IDL_FILE})
	get_filename_component(QURT_BUNDLE_IDL_NAME ${QURT_BUNDLE_IDL_FILE} NAME_WE)

	message("APP_NAME = ${QURT_BUNDLE_APP_NAME}")
	message("IDL_FILE = ${QURT_BUNDLE_IDL_FILE}")

	# Process Apps processor files
	if (NOT "${QURT_BUNDLE_APPS_SOURCES}" STREQUAL "")

		# Make sure apps compiler is provided
		if ("${QURT_BUNDLE_APPS_COMPILER}" STREQUAL "")
			message(FATAL_ERROR "APPS_COMPILER not specified in call to QURT_BUNDLE")
		endif()

		set(${QURT_BUNDLE_APP_NAME}_INCLUDE_DIRS 
			-I${CMAKE_CURRENT_BINARY_DIR}
			${FASTRPC_ARM_LINUX_INCLUDES}
			${QURT_BUNDLE_APPS_INCS}
			)

		set(${QURT_BUNDLE_APP_NAME}_LINK_DIRS ${FASTRPC_ARM_LIBS})

		# Build the apps processor app and RPC stub using the provided ${QURT_BUNDLE_APPS_COMPILER}
		add_custom_command(
			OUTPUT ${QURT_BUNDLE_APP_NAME}_app
			DEPENDS generate_${QURT_BUNDLE_IDL_NAME}_stubs
			COMMAND ${QURT_BUNDLE_APPS_COMPILER}  ${${QURT_BUNDLE_APP_NAME}_INCLUDE_DIRS} -o ${CMAKE_CURRENT_BINARY_DIR}/${QURT_BUNDLE_APP_NAME}_app ${QURT_BUNDLE_APPS_SOURCES} "${CMAKE_CURRENT_BINARY_DIR}/${QURT_BUNDLE_IDL_NAME}_stub.c" ${FASTRPC_ARM_LIBS}
			WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
			)

		FASTRPC_ARM_APP_DEPS_GEN(
			APP_NAME ${QURT_BUNDLE_APP_NAME}_app
			IDL_NAME ${QURT_BUNDLE_IDL_NAME}
			APP_DEST ${QURT_BUNDLE_APP_DEST}	
			)
	endif()

	if (NOT "${QURT_BUNDLE_DSP_SOURCES}" STREQUAL "")
		QURT_LIB(APP_NAME ${QURT_BUNDLE_APP_NAME}
			IDL_NAME ${QURT_BUNDLE_IDL_NAME}
			SOURCES ${QURT_BUNDLE_DSP_SOURCES}
			LINK_LIBS ${QURT_BUNDLE_DSP_LINK_LIBS}
			INCS ${QURT_BUNDLE_DSP_INCS}
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

