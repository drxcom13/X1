#include <QGuiApplication>
#include <QQmlApplicationEngine>

#ifdef Q_OS_ANDROID
#include <QJniObject>
#include <QtCore/qnativeinterface.h>

// android.content.pm.ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
static constexpr jint SCREEN_ORIENTATION_SENSOR_LANDSCAPE = 6;

// Lock the activity to landscape (either side, follows the sensor).
static void lockLandscape()
{
    QNativeInterface::QAndroidApplication::runOnAndroidMainThread([] {
        QJniObject activity = QNativeInterface::QAndroidApplication::context();
        activity.callMethod<void>("setRequestedOrientation", "(I)V",
                                  SCREEN_ORIENTATION_SENSOR_LANDSCAPE);
    });
}
#endif

int main(int argc, char *argv[])
{
#ifdef Q_OS_ANDROID
    // The on-disk shader cache goes stale on some Android GPU drivers after
    // an app update, which renders garbage; compile shaders on every start.
    qputenv("QT_DISABLE_SHADER_DISK_CACHE", "1");
#endif
    QGuiApplication app(argc, argv);
    // Needed by QML Settings (stores the RTSP address)
    QCoreApplication::setOrganizationName(QStringLiteral("X1"));
    QCoreApplication::setApplicationName(QStringLiteral("X1"));

#ifdef Q_OS_ANDROID
    lockLandscape();
#endif

    QQmlApplicationEngine engine;
    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &app,
        []() { QCoreApplication::exit(-1); },
        Qt::QueuedConnection);
    engine.loadFromModule("X1", "Main");

    return app.exec();
}
