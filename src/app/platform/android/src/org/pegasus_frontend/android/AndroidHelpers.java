package org.pegasus_frontend.android;

import android.app.Activity;
import android.app.ActivityOptions;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.hardware.display.DisplayManager;
import android.os.Build;
import android.util.Log;
import android.view.Display;

import org.qtproject.qt5.android.QtNative;

import java.util.Arrays;
import java.util.LinkedList;
import java.util.ListIterator;

public final class AndroidHelpers {
    private static final String TAG = "AndroidHelpers";

    /* ===================== 工具：获取 Qt 提供的 Context ===================== */
    private static Context getQtContext() {
        Activity act = QtNative.activity();
        if (act != null) return act;
        Service svc = QtNative.service();
        if (svc != null) return svc;
        return null;
    }

    /* ===================== 工具：从 am 参数中提取 --display N ===================== */
    /** 如果存在 --display N（或 -display N），返回该 N，并**从参数列表中移除这两个 token**；否则返回 null。 */
    private static Integer extractDisplayIdFromArgs(LinkedList<String> args) {
        if (args == null) return null;
        ListIterator<String> it = args.listIterator();
        while (it.hasNext()) {
            String tok = it.next();
            if ("--display".equals(tok) || "-display".equals(tok)) {
                if (it.hasNext()) {
                    String val = it.next();
                    try {
                        int id = Integer.parseInt(val);
                        // 移除这两个 token
                        it.remove();                // 移除数值
                        // 回到前一个元素的位置，删除 "--display"
                        int pos = it.previousIndex();
                        if (pos >= 0) {
                            args.remove(pos);       // 移除开关
                        }
                        return id;
                    } catch (NumberFormatException e) {
                        Log.w(TAG, "Bad --display value: " + val);
                        return null;
                    }
                }
                return null;
            }
        }
        return null;
    }

    /* ===================== 工具：选择最佳显示器 ===================== */
    /**
     * 优先级：
     * 1) 如果 preferredDisplayId 非空，且当前存在该显示器 -> 使用它；
     * 2) 如果系统存在多个显示器 -> 选择第一个「非主屏」的显示器；
     * 3) 其他情况 -> 使用主屏（displays[0]）。
     */
    private static int chooseBestDisplayId(Context ctx, Integer preferredDisplayId) {
    DisplayManager dm = (DisplayManager) ctx.getSystemService(Context.DISPLAY_SERVICE);
    Display[] displays = (dm != null) ? dm.getDisplays() : new Display[0];

    if (displays.length == 0) {
        Log.w(TAG, "No displays reported by DisplayManager; fallback to 0");
        return 0;
    }

    int currentDisplayId = 0;
    // 获取当前 context 所在的 display（API 17+）
    try {
        Display current = ctx.getDisplay();
        if (current != null) currentDisplayId = current.getDisplayId();
    } catch (Throwable ignored) {}

    // 打印调试信息
    for (Display d : displays) {
        Log.d(TAG, "Display id=" + d.getDisplayId() + " name=" + d.getName());
    }

    // 1) 如果显式给了 --display N 且存在，就优先用
    if (preferredDisplayId != null) {
        for (Display d : displays) {
            if (d.getDisplayId() == preferredDisplayId) return preferredDisplayId;
        }
        Log.w(TAG, "Preferred displayId not found: " + preferredDisplayId);
    }

    // 2) 若有多个屏幕，优先选一个 != 当前屏幕 的显示器
    if (displays.length > 1) {
        for (Display d : displays) {
            if (d.getDisplayId() != currentDisplayId) {
                Log.i(TAG, "Switching display from " + currentDisplayId + " to " + d.getDisplayId());
                return d.getDisplayId();
            }
        }
    }

    // 3) 否则仍在当前屏幕启动
    return currentDisplayId;
}

    /* ===================== 启动：自动选择显示器并启动 Activity ===================== */
    private static void startActivityAutoDisplay(Context ctx, Intent intent, Integer preferredDisplayId) {
        // Service 上下文需要 NEW_TASK
        if (!(ctx instanceof Activity)) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        }

        // API < 26 无法设置 launch display，直接普通启动
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            Log.i(TAG, "API < 26, start on default display");
            ctx.startActivity(intent);
            return;
        }

        int targetDisplay = chooseBestDisplayId(ctx, preferredDisplayId);
        Log.i(TAG, "Launching on display " + targetDisplay +
                (preferredDisplayId != null ? " (preferred=" + preferredDisplayId + ")" : ""));

        try {
            ActivityOptions opts = ActivityOptions.makeBasic();
            // API 26+ 可用
            opts.setLaunchDisplayId(targetDisplay);
            ctx.startActivity(intent, opts.toBundle());
        } catch (Throwable t) {
            Log.w(TAG, "startActivity with display failed: " + t + " -> fallback to normal start");
            ctx.startActivity(intent);
        }
    }

    /* ===================== 外部入口：am 参数解析并启动 ===================== */
    /**
     * 把 `am start ...` 的参数在应用内解析为 Intent，并尽量在非主屏启动。
     * @param args 传入 "am","start" 之后的所有参数；如果不小心把 "start" 也传进来了，也会被自动忽略。
     * @return 空串表示成功；非空表示错误字符串（供上层回退到外部 am）
     */
    public static String startActivityFromAmArgs(String[] args) {
        try {
            // 1) 解析原始参数
            LinkedList<String> list = new LinkedList<>(Arrays.asList(args));

            // 1.1) 兼容：如果第一个 token 是 "start"，先剔除
            if (!list.isEmpty() && "start".equalsIgnoreCase(list.peekFirst())) {
                list.removeFirst();
            }

            // 1.2) 先提取（并移除）--display N，如果有则优先用
            Integer preferredDisplayId = extractDisplayIdFromArgs(list);

            // 2) 交给你现有的解析器把参数 → Intent
            Intent intent = IntentHelper.parseIntentCommand(list);

            // 3) 自动选择显示器并启动
            Context ctx = getQtContext();
            if (ctx == null) return "No context available";
            startActivityAutoDisplay(ctx, intent, preferredDisplayId);

            return ""; // 成功
        } catch (Throwable t) {
            Log.w(TAG, "startActivityFromAmArgs failed: " + t);
            return t.toString();
        }
    }
}
