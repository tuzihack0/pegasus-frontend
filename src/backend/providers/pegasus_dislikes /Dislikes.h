// Pegasus Frontend - Dislikes Provider
// Based on Favorites.cpp/h by Mátyás Mustoha
// Modified 2025 by <your name>

#pragma once

#include "providers/Provider.h"

#include <QMutex>
#include <QStringList>
#include <QFuture>
#include <atomic>

namespace providers {
namespace dislikes {

class Dislikes : public Provider {
    Q_OBJECT

public:
    explicit Dislikes(QString db_path, QObject* parent = nullptr);
    explicit Dislikes(QObject* parent = nullptr);
    ~Dislikes() override;

    Provider& run(SearchContext&) final;
    void onGameDislikeChanged(const std::vector<model::Game*>&) final;

    // 删除 dislikes.txt 内文件（安全：移动到 Trash）
    Q_INVOKABLE void deleteAllDislikedFilesToTrash();
    // 永久清空 Trash
    Q_INVOKABLE void purgeTrash();

signals:
    void startedWriting();
    void finishedWriting();
    void deleteStarted();
    void deleteFinished(int successCount, int failCount);
    void deleteError(const QString& message);

private:
    Q_DISABLE_COPY(Dislikes)

    const QString m_db_path;
    QStringList   m_pending_task;
    QStringList   m_active_task;
    QMutex        m_task_guard;
    QFuture<void> m_worker_future;
    std::atomic_bool m_stopping{false};

    void start_processing();

    // Helpers
    static QString default_db_path();
    static QStringList buildDislikesBatch(const std::vector<model::Game*>& game_list);
    static bool isSafeRegularFile(const QString& path);
    static QString quarantineDir();
    static QString uniqueQuarantinePath(const QString& baseName);
    bool ensureTargetDirExists() const;
    bool writeBatchAtomically(const QStringList& batch);
    bool promotePendingToActive_locked();

    void performSafeDeleteAll();
    void performPurgeTrash();
};

} // namespace dislikes
} // namespace providers
