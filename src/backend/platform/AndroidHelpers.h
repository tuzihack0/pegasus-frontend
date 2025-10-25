// Pegasus Frontend
// Copyright ...
// GPLv3-or-later
#pragma once

#include <QString>
#include <QStringList>   // 新增：需要 QStringList
#include <functional>    // 新增：request_saf_permission 的 std::function

namespace android {

const char* jni_classname();

QString primary_storage_path();
QStringList storage_paths();
bool has_external_storage_access();

QStringList granted_paths();
void request_saf_permission(const std::function<void()>&);

// 旧有接口
QString run_am_call(const QStringList&);
QString to_content_uri(const QString&);
QString to_document_uri(const QString&);

// 新增接口：把 "am start" 的参数在应用内解析并启动（支持 --display）
// 成功返回空串；失败返回错误字符串（可回退到 run_am_call）
QString start_activity_from_am_args(const QStringList& args);

} // namespace android
