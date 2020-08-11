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

include(hexagon_sdk)

if("${RELEASE}" STREQUAL "")
	set(RELEASE Debug)
endif()

if(NOT ("${RELEASE}" STREQUAL "Debug" OR "${RELEASE}" STREQUAL "Release"))
	message(FATAL "RELEASE must be set to Debug or Release")
endif()

# Set paths depending on version of SDK in use
if ("$ENV{HEXAGON_SDK_ROOT}" MATCHES "/Hexagon_SDK/3.0")
	set(QAIC_PATH "${HEXAGON_SDK_ROOT}/tools/qaic/Linux/qaic" "-mdll" "-I" "${HEXAGON_SDK_ROOT}/${SDKINC}/stddef")
	set(HEXAGON_RPC_LIB "hexagon_${RELEASE}")

elseif("$ENV{HEXAGON_SDK_ROOT}" MATCHES "/Hexagon_SDK/3.1")
	set(QAIC_PATH "${HEXAGON_SDK_ROOT}/tools/qaic/Linux/qaic" "-mdll" "-I" "${HEXAGON_SDK_ROOT}/${SDKINC}/stddef")
	# set(HEXAGON_RPC_LIB "hexagon_${RELEASE}") # TODO

elseif("$ENV{HEXAGON_SDK_ROOT}" MATCHES "/Hexagon_SDK/3.3")
	set(QAIC_PATH "${HEXAGON_SDK_ROOT}/tools/qaic/Ubuntu14/qaic" "-mdll" "-I" "${HEXAGON_SDK_ROOT}/${SDKINC}/stddef")
	set(HEXAGON_RPC_LIB "hexagon_Debug_toolv81_v60")

elseif("$ENV{HEXAGON_SDK_ROOT}" MATCHES "/Hexagon_SDK/3.4")
	set(QAIC_PATH "${HEXAGON_SDK_ROOT}/tools/qaic/Ubuntu16/qaic" "-mdll" "-I" "${HEXAGON_SDK_ROOT}/${SDKINC}/stddef")
	# set(HEXAGON_RPC_LIB "hexagon_${RELEASE}") # TODO

else()
	set(QAIC_PATH "${HEXAGON_SDK_ROOT}/tools/qaic/Ubuntu18/qaic" "-mdll" "-I" "${HEXAGON_SDK_ROOT}/${SDKINC}/stddef")
	# set(HEXAGON_RPC_LIB "hexagon_${RELEASE}") # TODO
endif()

set(FASTRPC_DSP_INCLUDES
	${HEXAGON_SDK_INCLUDES}
	${HEXAGON_SDK_ROOT}/${SDKLIB}/common/rpcmem
	# ${HEXAGON_SDK_ROOT}/${SDKLIB}/common/remote/ship/hexagon_${RELEASE}
	${HEXAGON_SDK_ROOT}/${SDKLIB}/common/remote/ship/${HEXAGON_RPC_LIB}
	)

set(FASTRPC_ARM_LINUX_INCLUDES
	${HEXAGON_SDK_INCLUDES}
	${HEXAGON_SDK_ROOT}/${SDKLIB}/common/rpcmem
	# ${HEXAGON_SDK_ROOT}/${SDKLIB}/common/adspmsgd/ship/UbuntuARM_${RELEASE} # doesn't exist in 3.3.3
	${HEXAGON_SDK_ROOT}/${SDKLIB}/common/remote/ship/UbuntuARM_${RELEASE}
	)

if ("${DSP_TYPE}" STREQUAL "ADSP")
	set(ADSPRPC -L${HEXAGON_SDK_ROOT}/${SDKLIB}/common/remote/ship/UbuntuARM_${RELEASE} -ladsprpc)
elseif("${DSP_TYPE}" STREQUAL "SLPI")
	set(ADSPRPC -L${HEXAGON_SDK_ROOT}/${SDKLIB}/common/remote/ship/UbuntuARM_${RELEASE} -lsdsprpc)

else()
	message(FATAL_ERROR "DSP_TYPE not defined")
endif()

# what's this for? -- internet says it's for logging, doesn't appear to be used
# set(ADSPMSGD ${HEXAGON_SDK_ROOT}/${SDKLIB}/common/adspmsgd/ship/UbuntuARM_${RELEASE}/adspmsgd.a)

set(FASTRPC_ARM_LIBS
	${ADSPRPC}
	)


include_directories(
	${CMAKE_CURRENT_BINARY_DIR}
	)

function(FASTRPC_STUB_GEN IDLFILE)
	get_filename_component(FASTRPC_IDL_NAME ${IDLFILE} NAME_WE)
	get_filename_component(FASTRPC_IDL_PATH ${IDLFILE} ABSOLUTE)
	set (IDLINCS ${ARGN})

	# prepend -I in front of QAIC include dirs
	set(QAIC_INCLUDE_DIRS)
	foreach(inc ${IDLINCS})
		string(SUBSTRING ${inc} 0 1 absolute_path_character)
		if (absolute_path_character STREQUAL "/")
			list(APPEND QAIC_INCLUDE_DIRS -I${inc})
			message("QAIC include directory: -I${inc}")
		else()
			list(APPEND QAIC_INCLUDE_DIRS -I${CMAKE_CURRENT_SOURCE_DIR}/${inc})
			message("QAIC include directory: -I${CMAKE_CURRENT_SOURCE_DIR}/${inc}")
		endif()
	endforeach()



	# Run the IDL compiler to generate the stubs
	add_custom_command(
		OUTPUT ${FASTRPC_IDL_NAME}.h ${FASTRPC_IDL_NAME}_skel.c ${FASTRPC_IDL_NAME}_stub.c
		DEPENDS ${FASTRPC_IDL_PATH}
		COMMAND ${QAIC_PATH} ${QAIC_INCLUDE_DIRS} ${FASTRPC_IDL_PATH} # for 3.5.1
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

