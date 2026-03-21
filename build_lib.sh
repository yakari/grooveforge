clang++ -dynamiclib -std=c++17 -O3 \
    -Ipackages/flutter_vst3/dart_vst_host/native/include \
    -Ipackages/flutter_vst3/vst3sdk \
    -Ipackages/flutter_vst3/vst3sdk/pluginterfaces \
    -Ipackages/flutter_vst3/vst3sdk/public.sdk/source \
    -Ipackages/flutter_vst3/vst3sdk/base/thread/include \
    packages/flutter_vst3/dart_vst_host/native/src/dart_vst_host.cpp \
    packages/flutter_vst3/dart_vst_host/native/src/gfpa_dsp.cpp \
    packages/flutter_vst3/dart_vst_host/native/src/dart_vst_host_audio_mac.cpp \
    packages/flutter_vst3/dart_vst_host/native/src/dart_vst_host_editor_mac.mm \
    packages/flutter_vst3/vst3sdk/public.sdk/source/vst/hosting/module_mac.mm \
    packages/flutter_vst3/vst3sdk/public.sdk/source/common/threadchecker_mac.mm \
    packages/flutter_vst3/vst3sdk/public.sdk/source/vst/vstbus.cpp \
    packages/flutter_vst3/vst3sdk/public.sdk/source/vst/vstcomponent.cpp \
    packages/flutter_vst3/vst3sdk/public.sdk/source/vst/vstcomponentbase.cpp \
    packages/flutter_vst3/vst3sdk/public.sdk/source/vst/vsteditcontroller.cpp \
    packages/flutter_vst3/vst3sdk/public.sdk/source/vst/vstinitiids.cpp \
    packages/flutter_vst3/vst3sdk/public.sdk/source/vst/vstnoteexpressiontypes.cpp \
    packages/flutter_vst3/vst3sdk/public.sdk/source/vst/vstparameters.cpp \
    packages/flutter_vst3/vst3sdk/public.sdk/source/vst/vstpresetfile.cpp \
    packages/flutter_vst3/vst3sdk/public.sdk/source/vst/vstrepresentation.cpp \
    packages/flutter_vst3/vst3sdk/public.sdk/source/vst/hosting/hostclasses.cpp \
    packages/flutter_vst3/vst3sdk/public.sdk/source/vst/hosting/pluginterfacesupport.cpp \
    packages/flutter_vst3/vst3sdk/public.sdk/source/vst/hosting/module.cpp \
    packages/flutter_vst3/vst3sdk/public.sdk/source/common/pluginview.cpp \
    packages/flutter_vst3/vst3sdk/public.sdk/source/common/commoniids.cpp \
    packages/flutter_vst3/vst3sdk/public.sdk/source/vst/utility/stringconvert.cpp \
    packages/flutter_vst3/vst3sdk/public.sdk/source/vst/utility/sampleaccurate.cpp \
    packages/flutter_vst3/vst3sdk/public.sdk/source/vst/hosting/eventlist.cpp \
    packages/flutter_vst3/vst3sdk/public.sdk/source/vst/hosting/parameterchanges.cpp \
    packages/flutter_vst3/vst3sdk/public.sdk/source/vst/hosting/plugprovider.cpp \
    packages/flutter_vst3/vst3sdk/public.sdk/source/common/updatehandler.cpp \
    packages/flutter_vst3/vst3sdk/public.sdk/source/common/memorystream.cpp \
    packages/flutter_vst3/vst3sdk/base/thread/source/flock.cpp \
    packages/flutter_vst3/vst3sdk/base/thread/source/fcondition.cpp \
    packages/flutter_vst3/vst3sdk/public.sdk/source/vst/hosting/connectionproxy.cpp \
    packages/flutter_vst3/vst3sdk/public.sdk/source/common/commonstringconvert.cpp \
    -o libdart_vst_host.dylib \
    -framework Cocoa -framework Carbon -framework CoreFoundation -framework AudioToolbox \
    -Wno-deprecated-declarations -fobjc-arc -lc++ -Wl,-undefined,dynamic_lookup
