package org.pegasus_frontend.android;

import android.app.Activity;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.util.Log;

import org.qtproject.qt5.android.QtNative;

import java.util.Arrays;
import java.util.LinkedList;

public final class AndroidHelpers {
    private static final String TAG = "AndroidHelpers";

    // 统一安全获取 Qt 提供的 Context（Qt 5.15 没有 QtNative.context()）
    private static Context getQtContext() {
        Activity act = QtNative.activity();
        if (act != null) return act;
        Service svc = QtNative.service();
        if (svc != null) return svc;
        return null;
    }

    /**
     * 把 `am start ...` 的参数在应用内解析为 Intent，并尽量在指定 Display 启动。
     * @param args 传入 "am","start" 之后的所有参数（不包含前两个 token）
     * @return 空串表示成功；非空表示错误字符串（供上层回退到外部 am）
     */
    public static String startActivityFromAmArgs(String[] args) {
        try {
        // 1) 解析参数 -> Intent（支持 --display 等）
        LinkedList<String> list = new LinkedList<>(Arrays.asList(args));
        // 兼容两种调用：如果第一个 token 是 "start"，剔除之
        if (!list.isEmpty() && "start".equalsIgnoreCase(list.peekFirst())) {
            list.removeFirst();
        }
        // （可选）调试：打印剩余参数
        Log.d(TAG, "am args after trim: " + list);
            Intent intent = IntentHelper.parseIntentCommand(list);

            // 2) 选择一个可用的 Context（Qt Activity 优先）
            Context ctx = getQtContext();
            if (ctx == null) return "No context available";

            // 3) 用带 ActivityOptions 的方式启动（内部会处理 NEW_TASK/MULTIPLE_TASK/Display 校验）
            IntentHelper.startActivityWithOptions(ctx, intent);
            return ""; // 成功
        } catch (Throwable t) {
            Log.w(TAG, "startActivityFromAmArgs failed: " + t);
            return t.toString();
        }
    }
}
