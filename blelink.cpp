#include "blelink.h"

#include <QBluetoothDeviceDiscoveryAgent>
#include <QBluetoothUuid>
#include <QCoreApplication>
#if QT_CONFIG(permissions)
#include <QPermissions>
#endif

namespace {
// HM-10 / HM-11 / CC2541 / many clones
const QBluetoothUuid kHm10Service(QStringLiteral("0000ffe0-0000-1000-8000-00805f9b34fb"));
const QBluetoothUuid kHm10Char(QStringLiteral("0000ffe1-0000-1000-8000-00805f9b34fb"));
// Nordic UART Service (ESP32 BLE UART, nRF modules)
const QBluetoothUuid kNusService(QStringLiteral("6e400001-b5a3-f393-e0a9-e50e24dcca9e"));
const QBluetoothUuid kNusRxChar(QStringLiteral("6e400002-b5a3-f393-e0a9-e50e24dcca9e")); // app -> device

// Default ATT MTU leaves 20 bytes of payload per write
constexpr int kChunkSize = 20;
}

BleLink::BleLink(QObject *parent)
    : QObject(parent)
{
    m_sendTimer.setInterval(kSendIntervalMs);
    connect(&m_sendTimer, &QTimer::timeout, this, [this] {
        if (!flushPending())
            m_sendTimer.stop();
    });
    setStatus(tr("Not connected"));
}

BleLink::~BleLink()
{
    resetConnection();
}

QVariantList BleLink::devices() const
{
    QVariantList list;
    for (const QBluetoothDeviceInfo &info : m_devices) {
        const QString address = info.address().isNull()
                ? info.deviceUuid().toString(QUuid::WithoutBraces)
                : info.address().toString();
        list.append(QVariantMap{
            { QStringLiteral("name"), info.name().isEmpty() ? tr("(no name)") : info.name() },
            { QStringLiteral("address"), address },
            { QStringLiteral("rssi"), info.rssi() },
        });
    }
    return list;
}

bool BleLink::scanning() const
{
    return m_agent && m_agent->isActive();
}

void BleLink::startScan()
{
#if QT_CONFIG(permissions)
    QBluetoothPermission permission;
    permission.setCommunicationModes(QBluetoothPermission::Access);
    switch (qApp->checkPermission(permission)) {
    case Qt::PermissionStatus::Undetermined:
        qApp->requestPermission(permission, this, [this](const QPermission &p) {
            if (p.status() == Qt::PermissionStatus::Granted)
                doStartScan();
            else
                setStatus(tr("Bluetooth permission denied"));
        });
        return;
    case Qt::PermissionStatus::Denied:
        setStatus(tr("Bluetooth permission denied"));
        return;
    case Qt::PermissionStatus::Granted:
        break;
    }
#endif
    doStartScan();
}

void BleLink::doStartScan()
{
    if (!m_agent) {
        m_agent = new QBluetoothDeviceDiscoveryAgent(this);
        m_agent->setLowEnergyDiscoveryTimeout(8000);

        connect(m_agent, &QBluetoothDeviceDiscoveryAgent::deviceDiscovered, this,
                [this](const QBluetoothDeviceInfo &info) {
            if (!(info.coreConfigurations() & QBluetoothDeviceInfo::LowEnergyCoreConfiguration))
                return;
            for (const QBluetoothDeviceInfo &known : std::as_const(m_devices)) {
                if (known.address() == info.address() && known.deviceUuid() == info.deviceUuid())
                    return;
            }
            m_devices.append(info);
            emit devicesChanged();
        });
        connect(m_agent, &QBluetoothDeviceDiscoveryAgent::finished, this, [this] {
            setStatus(m_devices.isEmpty() ? tr("No BLE devices found")
                                          : tr("Scan finished, select a device"));
            emit scanningChanged();
        });
        connect(m_agent, &QBluetoothDeviceDiscoveryAgent::canceled, this,
                &BleLink::scanningChanged);
        connect(m_agent, &QBluetoothDeviceDiscoveryAgent::errorOccurred, this, [this] {
            setStatus(tr("Scan error: %1").arg(m_agent->errorString()));
            emit scanningChanged();
        });
    }

    if (m_agent->isActive())
        return;

    m_devices.clear();
    emit devicesChanged();
    setStatus(tr("Scanning..."));
    m_agent->start(QBluetoothDeviceDiscoveryAgent::LowEnergyMethod);
    emit scanningChanged();
}

void BleLink::stopScan()
{
    if (m_agent && m_agent->isActive())
        m_agent->stop();
}

void BleLink::connectToDevice(int index)
{
    if (index < 0 || index >= m_devices.size())
        return;

    stopScan();
    resetConnection();

    const QBluetoothDeviceInfo info = m_devices.at(index);
    m_deviceName = info.name();
    setBusy(true);
    setStatus(tr("Connecting to %1...").arg(m_deviceName));

    m_controller = QLowEnergyController::createCentral(info, this);

    connect(m_controller, &QLowEnergyController::connected, this, [this] {
        setStatus(tr("Discovering services..."));
        m_controller->discoverServices();
    });
    connect(m_controller, &QLowEnergyController::discoveryFinished,
            this, &BleLink::onServiceDiscoveryFinished);
    connect(m_controller, &QLowEnergyController::disconnected, this, [this] {
        resetConnection();
        setStatus(tr("Disconnected"));
    });
    connect(m_controller, &QLowEnergyController::errorOccurred, this, [this] {
        const QString error = m_controller ? m_controller->errorString() : QString();
        resetConnection();
        setStatus(tr("Connection error: %1").arg(error));
    });

    m_controller->connectToDevice();
}

void BleLink::disconnectFromDevice()
{
    resetConnection();
    setStatus(tr("Disconnected"));
}

void BleLink::onServiceDiscoveryFinished()
{
    QBluetoothUuid serviceUuid;
    const QList<QBluetoothUuid> services = m_controller->services();
    if (services.contains(kNusService))
        serviceUuid = kNusService;
    else if (services.contains(kHm10Service))
        serviceUuid = kHm10Service;

    if (serviceUuid.isNull()) {
        resetConnection();
        setStatus(tr("Device has no BLE UART service (FFE0 / Nordic UART)"));
        return;
    }

    m_service = m_controller->createServiceObject(serviceUuid, this);
    if (!m_service) {
        resetConnection();
        setStatus(tr("Cannot open UART service"));
        return;
    }

    connect(m_service, &QLowEnergyService::stateChanged,
            this, &BleLink::onServiceStateChanged);
    connect(m_service, &QLowEnergyService::errorOccurred, this,
            [this](QLowEnergyService::ServiceError error) {
        setStatus(tr("Service error %1").arg(int(error)));
    });
    m_service->discoverDetails();
}

void BleLink::onServiceStateChanged(QLowEnergyService::ServiceState state)
{
    if (state != QLowEnergyService::RemoteServiceDiscovered)
        return;

    const QBluetoothUuid charUuid =
            m_service->serviceUuid() == kNusService ? kNusRxChar : kHm10Char;
    m_txChar = m_service->characteristic(charUuid);

    if (!m_txChar.isValid()) {
        resetConnection();
        setStatus(tr("UART characteristic not found"));
        return;
    }

    const auto props = m_txChar.properties();
    if (props & QLowEnergyCharacteristic::WriteNoResponse)
        m_writeMode = QLowEnergyService::WriteWithoutResponse;
    else if (props & QLowEnergyCharacteristic::Write)
        m_writeMode = QLowEnergyService::WriteWithResponse;
    else {
        resetConnection();
        setStatus(tr("UART characteristic is not writable"));
        return;
    }

    setBusy(false);
    setConnected(true);
    setStatus(tr("Connected to %1").arg(m_deviceName));

    // Send the current control state right after connecting
    m_sentThrottle = -1;
    m_sentSteerX = INT_MIN;
    m_sentSteerY = INT_MIN;
    flushPending();
}

void BleLink::sendCommand(const QString &command)
{
    writeLine(command);
}

void BleLink::setThrottle(int percent)
{
    m_throttle = qBound(0, percent, 100);
    if (!m_sendTimer.isActive()) {
        flushPending();
        m_sendTimer.start();
    }
}

void BleLink::setSteering(int x, int y)
{
    m_steerX = qBound(-100, x, 100);
    m_steerY = qBound(-100, y, 100);
    if (!m_sendTimer.isActive()) {
        flushPending();
        m_sendTimer.start();
    }
}

bool BleLink::flushPending()
{
    bool sent = false;
    if (m_throttle >= 0 && m_throttle != m_sentThrottle) {
        writeLine(QStringLiteral("THR:%1").arg(m_throttle));
        m_sentThrottle = m_throttle;
        sent = true;
    }
    if (m_steerX != m_sentSteerX || m_steerY != m_sentSteerY) {
        writeLine(QStringLiteral("STR:%1,%2").arg(m_steerX).arg(m_steerY));
        m_sentSteerX = m_steerX;
        m_sentSteerY = m_steerY;
        sent = true;
    }
    return sent;
}

void BleLink::writeLine(const QString &line)
{
    if (m_lastCommand != line) {
        m_lastCommand = line;
        emit lastCommandChanged();
    }

    if (!m_connected || !m_service || !m_txChar.isValid())
        return;

    const QByteArray data = line.toUtf8() + '\n';
    for (qsizetype i = 0; i < data.size(); i += kChunkSize)
        m_service->writeCharacteristic(m_txChar, data.mid(i, kChunkSize), m_writeMode);
}

void BleLink::resetConnection()
{
    setConnected(false);
    setBusy(false);
    m_txChar = QLowEnergyCharacteristic();

    if (m_service) {
        m_service->disconnect(this);
        m_service->deleteLater();
        m_service = nullptr;
    }
    if (m_controller) {
        m_controller->disconnect(this);
        m_controller->disconnectFromDevice();
        m_controller->deleteLater();
        m_controller = nullptr;
    }
}

void BleLink::setStatus(const QString &status)
{
    if (m_status == status)
        return;
    m_status = status;
    emit statusChanged();
}

void BleLink::setBusy(bool busy)
{
    if (m_busy == busy)
        return;
    m_busy = busy;
    emit busyChanged();
}

void BleLink::setConnected(bool connected)
{
    if (m_connected == connected)
        return;
    m_connected = connected;
    emit connectedChanged();
}
