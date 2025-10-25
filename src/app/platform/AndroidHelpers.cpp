#include "platform/AndroidHelpers.h"

#include <QAndroidJniEnvironment>
#include <QAndroidJniObject>

namespace android {

QString start_activity_from_am_args(const QStringList& args)
{
    QAndroidJniEnvironment env;

    // 构造 String[]
    jclass stringClass = env->FindClass("java/lang/String");
    jobjectArray jArgs = env->NewObjectArray(args.size(), stringClass, nullptr);
    for (int i = 0; i < args.size(); ++i) {
        QAndroidJniObject jstr = QAndroidJniObject::fromString(args.at(i));
        env->SetObjectArrayElement(jArgs, i, jstr.object<jstring>());
    }

    // 调用 AndroidHelpers.startActivityFromAmArgs(String[] args) : String
    QAndroidJniObject res = QAndroidJniObject::callStaticObjectMethod(
        "org/pegasus_frontend/android/AndroidHelpers",
        "startActivityFromAmArgs",
        "([Ljava/lang/String;)Ljava/lang/String;",
        jArgs
    );

    if (env->ExceptionCheck()) {
        env->ExceptionDescribe();
        env->ExceptionClear();
        return QStringLiteral("Java exception");
    }
    return res.isValid() ? res.toString() : QString();
}

} // namespace android
