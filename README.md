# CMake Rules for QuRT Applications

Hexagon apps are started from an app running on the apps processor 
of the SoC. A RPC mechanism is used to load the app on the DSP and
the RPC stubs are generated from a IDL complier (qaic). The RTOS on
the DSP is QuRT but is often abstraced by the DSPAL APIs.

QURT_BUNDLE is used to specify the files and libraries to build
in the DSP lib and in the apps application. The generated stubs are
automatically build into the appropriate target.

For an app named testapp, the result will be:
- testapp_app     - Run on apps processor
- testapp.so      - copy to target at /usr/share/date/adsp/
- testapp_skel.so - copy to target at /usr/share/date/adsp/

