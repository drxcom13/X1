cmake_minimum_required(VERSION 3.16)

project(X1 VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 REQUIRED COMPONENTS Quick Svg Bluetooth Multimedia)

qt_standard_project_setup(REQUIRES 6.8)

qt_add_executable(appX1
    main.cpp
)

set_source_files_properties(Theme.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(appX1
    URI X1
    QML_FILES
        Main.qml
        Joystick.qml
        SetupDialog.qml
        VideoView.qml
        Theme.qml
    SOURCES
        blelink.h
        blelink.cpp
    RESOURCES
        icons/light.svg
        icons/horn.svg
        icons/stop.svg
        icons/setup.svg
        icons/start.svg
        icons/x1_logo.png
)

# Qt for iOS sets MACOSX_BUNDLE_GUI_IDENTIFIER automatically since Qt 6.1.
# If you are developing for iOS or macOS you should consider setting an
# explicit, fixed bundle identifier manually though.
set_target_properties(appX1 PROPERTIES
#    MACOSX_BUNDLE_GUI_IDENTIFIER com.example.appX1
    MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION}
    MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}
    MACOSX_BUNDLE TRUE
    WIN32_EXECUTABLE TRUE
    # Android manifest and resources (launcher icon in res/mipmap-*)
    QT_ANDROID_PACKAGE_SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/android
)

target_link_libraries(appX1
    PRIVATE Qt6::Quick Qt6::Svg Qt6::Bluetooth Qt6::Multimedia
)

include(GNUInstallDirs)
install(TARGETS appX1
    BUNDLE DESTINATION .
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
