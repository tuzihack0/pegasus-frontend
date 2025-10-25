#pragma once
#include <QString>
#include <QStringList>

namespace android {

// 已有的声明（如果有）……

// 新增：尝试在应用内启动（支持 --display）；成功返回空串，失败返回错误字符串
QString start_activity_from_am_args(const QStringList& args);

} // namespace android
