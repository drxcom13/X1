#include <QGuiApplication>
#include <QQmlApplicationEngine>

#ifdef Q_OS_ANDROID
#include <QJniObject>
#include <QtCore/qnativeinterface.h>

// android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
static constexpr jint FLAG_KEEP_SCREEN_ON = 0x00000080;

// Keep the screen on while the app is in front: the operator may watch the
// video for a long time without touching the screen. (Landscape is locked
// in AndroidManifest.xml.)
static void keepScreenOn()
{
    QNativeInterface::QAndroidApplication::runOnAndroidMainThread([] {
        QJniObject activity = QNativeInterface::QAndroidApplication::context();
        QJniObject window = activity.callObjectMethod("getWindow", "()Landroid/view/Window;");
        if (window.isValid())
            window.callMethod<void>("addFlags", "(I)V", FLAG_KEEP_SCREEN_ON);
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
    keepScreenOn();
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
