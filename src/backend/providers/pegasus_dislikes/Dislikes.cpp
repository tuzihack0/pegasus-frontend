// Pegasus Frontend - Dislikes Provider
// Based on Favorites.cpp/h by Mátyás Mustoha
// Modified 2025 by <your name>

#include "Dislikes.h"

#include "AppSettings.h"
#include "Log.h"
#include "Paths.h"
#include "model/gaming/Game.h"
#include "model/gaming/GameFile.h"
#include "providers/SearchContext.h"
#include "utils/PathTools.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QSaveFile>
#include <QTextStream>
#include <QtConcurrent/QtConcurrent>
#include <QDateTime>

namespace {
QString default_db_path()
{
    return paths::writableConfigDir() + QStringLiteral("/dislikes.txt");
}
} // namespace

namespace providers {
namespace dislikes {

Dislikes::Dislikes(QObject* parent)
    : Dislikes(default_db_path(), parent)
{}

Dislikes::Dislikes(QString db_path, QObject* parent)
    : Provider(QLatin1String("pegasus_dislikes"),
               QStringLiteral("Pegasus Dislikes"),
               PROVIDER_FLAG_INTERNAL | PROVIDER_FLAG_HIDE_PROGRESS,
               parent)
    , m_db_path(std::move(db_path))
{}

Dislikes::~Dislikes()
{
    m_stopping.store(true, std::memory_order_relaxed);
    if (m_worker_future.isRunning())
        m_worker_future.waitForFinished();
}

Provider& Dislikes::run(SearchContext& sctx)
{
    if (!QFileInfo::exists(m_db_path))
        return *this;

    QFile db_file(m_db_path);
    if (!db_file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        Log::error(display_name(), LOGMSG("Could not open `%1` for reading, dislikes not loaded").arg(m_db_path));
        return *this;
    }

    const QDir base_dir = QFileInfo(m_db_path).dir();
    QTextStream db_stream(&db_file);
#if QT_VERSION >= QT_VERSION_CHECK(6,0,0)
    db_stream.setEncoding(QStringConverter::Utf8);
#else
    db_stream.setCodec("UTF-8");
#endif

    QString line;
    while (db_stream.readLineInto(&line)) {
        if (line.startsWith('#') || line.trimmed().isEmpty())
            continue;

        model::Game* game_ptr = sctx.game_by_uri(line);
        if (!game_ptr) {
            const QString path = ::clean_abs_path(QFileInfo(base_dir, line));
            game_ptr = sctx.game_by_filepath(path);
        }

        if (game_ptr)
            game_ptr->setDisliked(true); // 在 Game 中新增该属性
    }

    return *this;
}

QStringList Dislikes::buildDislikesBatch(const std::vector<model::Game*>& game_list)
{
    QStringList out;
    out << QStringLiteral("# List of disliked files, one path per line") << QString();

    const QDir config_dir(paths::writableConfigDir());
    for (const model::Game* game : game_list) {
        if (!game || !game->isDisliked())
            continue;

        for (const model::GameFile* file : game->filesModel()->entries()) {
            QString path;
            if (!file->fileinfo().exists()) {
                path = QDir::cleanPath(file->path());
            } else {
                const QString full_path = ::clean_abs_path(file->fileinfo());
                path = AppSettings::general.portable
                    ? config_dir.relativeFilePath(full_path)
                    : full_path;
                path = QDir::cleanPath(path);
            }
            if (!path.isEmpty())
                out << path;
        }
    }

    out.removeDuplicates();
    return out;
}

void Dislikes::onGameDislikeChanged(const std::vector<model::Game*>& game_list)
{
    QStringList new_task = buildDislikesBatch(game_list);

    bool need_start = false;
    {
        QMutexLocker lock(&m_task_guard);
        m_pending_task = std::move(new_task);
        need_start = m_active_task.isEmpty();
    }

    if (need_start)
        start_processing();
}

bool Dislikes::ensureTargetDirExists() const
{
    QDir dir = QFileInfo(m_db_path).dir();
    return dir.mkpath(QStringLiteral("."));
}

bool Dislikes::writeBatchAtomically(const QStringList& batch)
{
    if (!ensureTargetDirExists()) return false;

    QSaveFile file(m_db_path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text))
        return false;

    QTextStream out(&file);
#if QT_VERSION >= QT_VERSION_CHECK(6,0,0)
    out.setEncoding(QStringConverter::Utf8);
#else
    out.setCodec("UTF-8");
#endif

    for (const auto& line : batch)
        out << line << '\n';

    return file.commit();
}

bool Dislikes::promotePendingToActive_locked()
{
    if (m_active_task.isEmpty() && !m_pending_task.isEmpty()) {
        m_active_task = m_pending_task;
        m_pending_task.clear();
        return true;
    }
    return !m_active_task.isEmpty();
}

void Dislikes::start_processing()
{
    {
        QMutexLocker lock(&m_task_guard);
        if (!promotePendingToActive_locked())
            return;
    }

    m_worker_future = QtConcurrent::run([this]{
        emit startedWriting();

        while (!m_stopping.load(std::memory_order_relaxed)) {
            QStringList batch;
            {
                QMutexLocker lock(&m_task_guard);
                batch = m_active_task;
            }
            if (batch.isEmpty()) break;

            if (!writeBatchAtomically(batch)) {
                Log::error(display_name(), LOGMSG("Failed to write `%1`").arg(m_db_path));
                break;
            }

            bool has_more = false;
            {
                QMutexLocker lock(&m_task_guard);
                m_active_task.clear();
                has_more = promotePendingToActive_locked();
            }
            if (!has_more) break;
        }

        emit finishedWriting();
    });
}

bool Dislikes::isSafeRegularFile(const QString& path)
{
    if (path.trimmed().isEmpty()) return false;
    QFileInfo fi(path);
    return fi.exists() && fi.isFile();
}

QString Dislikes::quarantineDir()
{
    return QDir::cleanPath(paths::writableConfigDir() + QStringLiteral("/Trash"));
}

QString Dislikes::uniqueQuarantinePath(const QString& baseName)
{
    QDir qdir(quarantineDir());
    qdir.mkpath(QStringLiteral("."));
    QString candidate = qdir.filePath(baseName);
    if (!QFileInfo::exists(candidate)) return candidate;

    QString stamp = QDateTime::currentDateTimeUtc().toString("yyyyMMdd_HHmmsszzz");
    return qdir.filePath(baseName + "." + stamp);
}

void Dislikes::deleteAllDislikedFilesToTrash()
{
    QtConcurrent::run([this]{
        emit deleteStarted();

        QStringList paths;
        {
            QFile db(m_db_path);
            if (db.open(QIODevice::ReadOnly | QIODevice::Text)) {
                QTextStream in(&db);
#if QT_VERSION >= QT_VERSION_CHECK(6,0,0)
                in.setEncoding(QStringConverter::Utf8);
#else
                in.setCodec("UTF-8");
#endif
                const QDir base = QFileInfo(m_db_path).dir();
                QString line;
                while (in.readLineInto(&line)) {
                    if (line.startsWith('#') || line.trimmed().isEmpty())
                        continue;
                    const QString abs = ::clean_abs_path(QFileInfo(base, line));
                    paths << QDir::cleanPath(abs);
                }
            }
        }

        int ok = 0, fail = 0;
        QDir qdir(quarantineDir());
        qdir.mkpath(QStringLiteral("."));

        for (const auto& p : paths) {
            if (!isSafeRegularFile(p)) { ++fail; continue; }

            QFileInfo fi(p);
            const QString dst = uniqueQuarantinePath(fi.fileName());

            if (QFile::rename(p, dst)) { ++ok; continue; }
            if (QFile::copy(p, dst) && QFile::remove(p)) { ++ok; }
            else { if (QFileInfo::exists(dst)) QFile::remove(dst); ++fail; }
        }

        emit deleteFinished(ok, fail);
    });
}

void Dislikes::purgeTrash()
{
    QtConcurrent::run([this]{
        QDir qdir(quarantineDir());
        if (!qdir.exists()) return;

        int ok = 0, fail = 0;
        for (const QFileInfo& fi : qdir.entryInfoList(QDir::Files | QDir::NoDotAndDotDot)) {
            if (QFile::remove(fi.absoluteFilePath())) ++ok;
            else ++fail;
        }

        emit deleteFinished(ok, fail);
    });
}

} // namespace dislikes
} // namespace providers
