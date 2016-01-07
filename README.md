# CMake Rules for QuRT Applications

Hexagon apps are started from an app running on the apps processor 
of the SoC. A RPC mechanism is used to load a shared library on the DSP and
the RPC stubs are generated from a IDL complier (qaic). The RTOS on
the DSP is QuRT but is often abstraced by the DSPAL APIs.

QURT_BUNDLE is used to specify the files and libraries to build
into the DSP lib and into the apps application. The generated stubs are
automatically build into the appropriate target.

The CMakeLists.txt file calls QURT_BUNDLE and requires that the file <appname>.idl
exists for the IDL interface between the apps processor app and the DSP library.

QURT_BUNDLE(APP_NAME testapp
	DSP_SOURCES testapp_dsp.c
	APPS_SOURCES testapp.c
	APPS_INCS "-Iinclude"
	APPS_COMPILER arm-linux-gnueabihf-gcc
	)

For an app named testapp, the result will be:
- testapp_app        - Run on apps processor
- libtestapp.so      - copy to target at /usr/share/date/adsp/
- libtestapp_skel.so - copy to target at /usr/share/date/adsp/

The file testapp.idl is used in this example to create the stub functions that automatically
get linked in to the app and DSP lib.

QURT_BUNDLE adds a rule to load the app onto the DSP (<appname>-load).

To load the testapp application to the target you can run the 
following command from inside the build tree:

```
cd build
make testapp-load
```

