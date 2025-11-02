// Pegasus Frontend
// Copyright (C) 2017
// License: GPLv3-or-later

#include "FrontendLayer.h"

#include "Paths.h"
#include <QGuiApplication>
#include "imggen/BlurhashProvider.h"
#include "utils/DiskCachedNAM.h"

#ifdef Q_OS_ANDROID
#include "platform/AndroidAppIconProvider.h"
#endif

#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQmlNetworkAccessManagerFactory>
#include <QNetworkAccessManager>

namespace {

class DiskCachedNAMFactory : public QQmlNetworkAccessManagerFactory {
public:
    QNetworkAccessManager* create(QObject* parent) override {
        return utils::create_disc_cached_nam(parent);
    }
};

} // namespace

FrontendLayer::FrontendLayer(QObject* const api_public,
                             QObject* const api_private,
                             QObject* parent)
    : QObject(parent)
    , m_api_public(api_public)
    , m_api_private(api_private)
    , m_engine(nullptr)
{
    // Note: the pointer to the Api is non-owning and constant during the runtime
}

void FrontendLayer::rebuild()
{
    // 幂等：已有引擎在跑就不重建，直接宣布完成，避免闪烁
    // Q_ASSERT(!m_engine);
    if (m_engine) {
        emit rebuildComplete();
        return;
    }

    m_engine = new QQmlApplicationEngine(this);
    m_engine->addImportPath(QStringLiteral("lib/qml"));
    m_engine->addImportPath(QStringLiteral("qml"));
    m_engine->setNetworkAccessManagerFactory(new DiskCachedNAMFactory);

    m_engine->addImageProvider(QStringLiteral("blurhash"), new BlurhashProvider);
#ifdef Q_OS_ANDROID
    m_engine->addImageProvider(QStringLiteral("androidicons"), new AndroidAppIconProvider);
#endif

    m_engine->rootContext()->setContextProperty(QStringLiteral("api"), m_api_public);
    m_engine->rootContext()->setContextProperty(QStringLiteral("Api"), m_api_public);
    m_engine->rootContext()->setContextProperty(QStringLiteral("Internal"), m_api_private);
    m_engine->load(QUrl(QStringLiteral("qrc:/frontend/main.qml")));

    emit rebuildComplete();
}

void FrontendLayer::teardown()
{
    // 多屏：谁调用 teardown 都不真正销毁引擎，直接宣布完成，避免“拆了又建”
    const bool multi_screen = QGuiApplication::screens().size() > 1;
    if (multi_screen) {
        emit teardownComplete();
        return;
    }

    // 单屏幂等：若当前没有引擎（例如已被拆过），也直接宣布完成
    // Q_ASSERT(m_engine);
    if (!m_engine) {
        emit teardownComplete();
        return;
    }

    // 正常单屏 teardown：销毁并在 destroyed 时转发完成信号
    connect(m_engine, &QQmlApplicationEngine::destroyed,
            this, &FrontendLayer::teardownComplete);

    m_engine->deleteLater();
    m_engine = nullptr;
}

void FrontendLayer::clearCache()
{
    Q_ASSERT(m_engine);
    m_engine->clearComponentCache();
}
