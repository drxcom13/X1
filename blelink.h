#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QTimer>
#include <climits>
#include <QVariantList>
#include <QBluetoothDeviceInfo>
#include <QLowEnergyController>
#include <QLowEnergyService>

class QBluetoothDeviceDiscoveryAgent;

// BLE UART link to the vehicle.
// Supports HM-10 style modules (service FFE0, characteristic FFE1)
// and the Nordic UART Service (ESP32 BLE UART and similar).
// Every command is sent as a text line terminated with '\n'.
class BleLink : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QVariantList devices READ devices NOTIFY devicesChanged)
    Q_PROPERTY(bool scanning READ scanning NOTIFY scanningChanged)
    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QString deviceName READ deviceName NOTIFY connectedChanged)
    Q_PROPERTY(QString status READ status NOTIFY statusChanged)
    Q_PROPERTY(QString lastCommand READ lastCommand NOTIFY lastCommandChanged)

public:
    explicit BleLink(QObject *parent = nullptr);
    ~BleLink() override;

    QVariantList devices() const;
    bool scanning() const;
    bool connected() const { return m_connected; }
    bool busy() const { return m_busy; }
    QString deviceName() const { return m_deviceName; }
    QString status() const { return m_status; }
    QString lastCommand() const { return m_lastCommand; }

    Q_INVOKABLE void startScan();
    Q_INVOKABLE void stopScan();
    Q_INVOKABLE void connectToDevice(int index);
    Q_INVOKABLE void disconnectFromDevice();

    // Sends one text command immediately (buttons).
    Q_INVOKABLE void sendCommand(const QString &command);

    // Continuous controls: only the latest value is sent, at most every
    // kSendIntervalMs, and only when it actually changed.
    Q_INVOKABLE void setThrottle(int percent);        // 0..100
    Q_INVOKABLE void setSteering(int x, int y);       // -100..100 each

signals:
    void devicesChanged();
    void scanningChanged();
    void connectedChanged();
    void busyChanged();
    void statusChanged();
    void lastCommandChanged();

private:
    void doStartScan();
    void setStatus(const QString &status);
    void setBusy(bool busy);
    void setConnected(bool connected);
    void onServiceDiscoveryFinished();
    void onServiceStateChanged(QLowEnergyService::ServiceState state);
    bool flushPending();
    void writeLine(const QString &line);
    void resetConnection();

    static constexpr int kSendIntervalMs = 50;

    QBluetoothDeviceDiscoveryAgent *m_agent = nullptr;
    QList<QBluetoothDeviceInfo> m_devices;

    QLowEnergyController *m_controller = nullptr;
    QLowEnergyService *m_service = nullptr;
    QLowEnergyCharacteristic m_txChar;   // characteristic we write to
    QLowEnergyService::WriteMode m_writeMode = QLowEnergyService::WriteWithoutResponse;

    bool m_connected = false;
    bool m_busy = false;
    QString m_deviceName;
    QString m_status;
    QString m_lastCommand;

    QTimer m_sendTimer;
    int m_throttle = -1;
    int m_sentThrottle = -1;
    int m_steerX = 0;
    int m_steerY = 0;
    int m_sentSteerX = INT_MIN;
    int m_sentSteerY = INT_MIN;
};
