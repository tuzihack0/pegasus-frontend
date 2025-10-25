// Pegasus Frontend
// Copyright (C) ...
// GPLv3-or-later

package org.pegasus_frontend.android;

import android.app.Activity;
import android.app.ActivityOptions;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.hardware.display.DisplayManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.util.Log;
import android.view.Display;

import java.net.URISyntaxException;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedList;

final class IntentHelper {
    private static final String TAG = "IntentHelper";
    /** 我们自用的 extra，用于在启动阶段读取目标显示屏 id */
    private static final String EXTRA_PEGASUS_DISPLAY_ID = "pegasus_launch_display_id";

    // 基于 AOSP 的 Intent.parseCommandArgs，适配并裁剪
    public static Intent parseIntentCommand(LinkedList<String> args) throws URISyntaxException {
        Intent intent = new Intent();
        Intent baseIntent = intent;
        boolean hasIntentInfo = false;

        Uri data = null;
        String type = null;
        int displayId = -1; // 未指定

        while (!args.isEmpty()) {
            final String opt = args.pop();
            switch (opt) {
                case "-a":
                    intent.setAction(args.pop());
                    if (intent == baseIntent) hasIntentInfo = true;
                    break;
                case "-d":
                    data = Uri.parse(args.pop());
                    if (intent == baseIntent) hasIntentInfo = true;
                    break;
                case "-t":
                    type = args.pop();
                    if (intent == baseIntent) hasIntentInfo = true;
                    break;
                case "-i":
                    intent.setIdentifier(args.pop());
                    if (intent == baseIntent) hasIntentInfo = true;
                    break;
                case "-c":
                    intent.addCategory(args.pop());
                    if (intent == baseIntent) hasIntentInfo = true;
                    break;

                // ---- extras ----
                case "-e":
                case "--es": {
                    String key = args.pop();
                    String value = args.pop();
                    intent.putExtra(key, value);
                    break;
                }
                case "--esn": {
                    String key = args.pop();
                    intent.putExtra(key, (String) null);
                    break;
                }
                case "--ei": {
                    String key = args.pop();
                    String value = args.pop();
                    intent.putExtra(key, Integer.decode(value));
                    break;
                }
                case "--eu": {
                    String key = args.pop();
                    String value = args.pop();
                    intent.putExtra(key, Uri.parse(value));
                    break;
                }
                case "--ecn": {
                    String key = args.pop();
                    String value = args.pop();
                    ComponentName cn = ComponentName.unflattenFromString(value);
                    if (cn == null) throw new IllegalArgumentException("Bad component name: " + value);
                    intent.putExtra(key, cn);
                    break;
                }
                case "--eia": {
                    String key = args.pop();
                    String value = args.pop();
                    String[] strings = value.split(",");
                    int[] list = new int[strings.length];
                    for (int i = 0; i < strings.length; i++) list[i] = Integer.decode(strings[i]);
                    intent.putExtra(key, list);
                    break;
                }
                case "--eial": {
                    String key = args.pop();
                    String value = args.pop();
                    String[] strings = value.split(",");
                    ArrayList<Integer> list = new ArrayList<>(strings.length);
                    for (int i = 0; i < strings.length; i++) list.add(Integer.decode(strings[i]));
                    intent.putExtra(key, list);
                    break;
                }
                case "--el": {
                    String key = args.pop();
                    String value = args.pop();
                    intent.putExtra(key, Long.valueOf(value));
                    break;
                }
                case "--ela": {
                    String key = args.pop();
                    String value = args.pop();
                    String[] strings = value.split(",");
                    long[] list = new long[strings.length];
                    for (int i = 0; i < strings.length; i++) list[i] = Long.valueOf(strings[i]);
                    intent.putExtra(key, list);
                    hasIntentInfo = true;
                    break;
                }
                case "--elal": {
                    String key = args.pop();
                    String value = args.pop();
                    String[] strings = value.split(",");
                    ArrayList<Long> list = new ArrayList<>(strings.length);
                    for (int i = 0; i < strings.length; i++) list.add(Long.valueOf(strings[i]));
                    intent.putExtra(key, list);
                    hasIntentInfo = true;
                    break;
                }
                case "--ef": {
                    String key = args.pop();
                    String value = args.pop();
                    intent.putExtra(key, Float.valueOf(value));
                    hasIntentInfo = true;
                    break;
                }
                case "--efa": {
                    String key = args.pop();
                    String value = args.pop();
                    String[] strings = value.split(",");
                    float[] list = new float[strings.length];
                    for (int i = 0; i < strings.length; i++) list[i] = Float.valueOf(strings[i]);
                    intent.putExtra(key, list);
                    hasIntentInfo = true;
                    break;
                }
                case "--efal": {
                    String key = args.pop();
                    String value = args.pop();
                    String[] strings = value.split(",");
                    ArrayList<Float> list = new ArrayList<>(strings.length);
                    for (int i = 0; i < strings.length; i++) list.add(Float.valueOf(strings[i]));
                    intent.putExtra(key, list);
                    hasIntentInfo = true;
                    break;
                }
                case "--esa": {
                    String key = args.pop();
                    String value = args.pop();
                    // 以未转义逗号切分，并反转义 \, 与 \\
                    String[] strings = value.split("(?<!\\\\),");
                    for (int i = 0; i < strings.length; i++) {
                        strings[i] = strings[i].replace("\\,", ",").replace("\\\\", "\\");
                    }
                    intent.putExtra(key, strings);
                    hasIntentInfo = true;
                    break;
                }
                case "--esal": {
                    String key = args.pop();
                    String value = args.pop();
                    String[] strings = value.split("(?<!\\\\),");
                    ArrayList<String> list = new ArrayList<>(strings.length);
                    for (int i = 0; i < strings.length; i++) {
                        list.add(strings[i].replace("\\,", ",").replace("\\\\", "\\"));
                    }
                    intent.putExtra(key, list);
                    hasIntentInfo = true;
                    break;
                }
                case "--ez": {
                    String key = args.pop();
                    String value = args.pop().toLowerCase();
                    boolean arg;
                    if ("true".equals(value) || "t".equals(value)) arg = true;
                    else if ("false".equals(value) || "f".equals(value)) arg = false;
                    else {
                        try { arg = Integer.decode(value) != 0; }
                        catch (NumberFormatException ex) {
                            throw new IllegalArgumentException("Invalid boolean value: " + value);
                        }
                    }
                    intent.putExtra(key, arg);
                    break;
                }

                // ---- 目标/包名/flags ----
                case "-n": {
                    String str = args.pop();
                    ComponentName cn = ComponentName.unflattenFromString(str);
                    if (cn == null) throw new IllegalArgumentException("Bad component name: " + str);
                    intent.setComponent(cn);
                    if (intent == baseIntent) hasIntentInfo = true;
                    break;
                }
                case "-p": {
                    String str = args.pop();
                    intent.setPackage(str);
                    if (intent == baseIntent) hasIntentInfo = true;
                    break;
                }
                case "-f":
                    String str = args.pop();
                    intent.setFlags(Integer.decode(str));
                    break;

                case "--grant-read-uri-permission":  intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION); break;
                case "--grant-write-uri-permission": intent.addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION); break;
                case "--grant-persistable-uri-permission": intent.addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION); break;
                case "--grant-prefix-uri-permission": intent.addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION); break;
                case "--exclude-stopped-packages": intent.addFlags(Intent.FLAG_EXCLUDE_STOPPED_PACKAGES); break;
                case "--include-stopped-packages": intent.addFlags(Intent.FLAG_INCLUDE_STOPPED_PACKAGES); break;
                case "--debug-log-resolution": intent.addFlags(Intent.FLAG_DEBUG_LOG_RESOLUTION); break;
                case "--activity-brought-to-front": intent.addFlags(Intent.FLAG_ACTIVITY_BROUGHT_TO_FRONT); break;
                case "--activity-clear-top": intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP); break;
                case "--activity-clear-when-task-reset": intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_WHEN_TASK_RESET); break;
                case "--activity-exclude-from-recents": intent.addFlags(Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS); break;
                case "--activity-launched-from-history": intent.addFlags(Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY); break;
                case "--activity-multiple-task": intent.addFlags(Intent.FLAG_ACTIVITY_MULTIPLE_TASK); break;
                case "--activity-no-animation": intent.addFlags(Intent.FLAG_ACTIVITY_NO_ANIMATION); break;
                case "--activity-no-history": intent.addFlags(Intent.FLAG_ACTIVITY_NO_HISTORY); break;
                case "--activity-no-user-action": intent.addFlags(Intent.FLAG_ACTIVITY_NO_USER_ACTION); break;
                case "--activity-previous-is-top": intent.addFlags(Intent.FLAG_ACTIVITY_PREVIOUS_IS_TOP); break;
                case "--activity-reorder-to-front": intent.addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT); break;
                case "--activity-reset-task-if-needed": intent.addFlags(Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED); break;
                case "--activity-single-top": intent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP); break;
                case "--activity-clear-task": intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TASK); break;
                case "--activity-task-on-home": intent.addFlags(Intent.FLAG_ACTIVITY_TASK_ON_HOME); break;
                case "--activity-match-external": intent.addFlags(Intent.FLAG_ACTIVITY_MATCH_EXTERNAL); break;
                case "--receiver-registered-only": intent.addFlags(Intent.FLAG_RECEIVER_REGISTERED_ONLY); break;
                case "--receiver-replace-pending": intent.addFlags(Intent.FLAG_RECEIVER_REPLACE_PENDING); break;
                case "--receiver-foreground": intent.addFlags(Intent.FLAG_RECEIVER_FOREGROUND); break;
                case "--receiver-no-abort": intent.addFlags(Intent.FLAG_RECEIVER_NO_ABORT); break;

                case "--selector":
                    intent.setDataAndType(data, type);
                    intent = new Intent();
                    break;

                // am 自身的选项，保持为 extra 以便上层决定
                case "-D":
                case "-N":
                case "-W":
                case "-S":
                case "--streaming":
                case "--track-allocation":
                case "--task-overlay":
                case "--lock-task":
                case "--allow-background-activity-starts":
                    intent.putExtra("am_flag_" + opt, true);
                    break;

                // ---- 真正支持的 --display ----
                case "--display": {
                    String v = args.pop();
                    try {
                        displayId = Integer.parseInt(v);
                    } catch (NumberFormatException e) {
                        throw new IllegalArgumentException("Invalid --display value: " + v);
                    }
                    // 不 putExtra("am_opt_--display")，保存到本地变量，启动阶段再转成 ActivityOptions
                    break;
                }

                // 其它保留信息（系统不会自动识别）
                case "-P":
                case "--start-profiler":
                case "--sampling":
                case "--attach-agent":
                case "--attach-agent-bind":
                case "-R":
                case "--user":
                case "--receiver-permission":
                case "--windowingMode":
                case "--activityType":
                case "--task": {
                    String v = args.pop();
                    intent.putExtra("am_opt_" + opt, v);
                    break;
                }

                default:
                    throw new IllegalArgumentException("Unknown option: " + opt);
            }
        }

        intent.setDataAndType(data, type);

        final boolean hasSelector = intent != baseIntent;
        if (hasSelector) {
            baseIntent.setSelector(intent);
            intent = baseIntent;
        }

        String arg = args.isEmpty() ? null : args.pop();
        baseIntent = null;
        if (arg == null) {
            if (hasSelector) {
                baseIntent = new Intent(Intent.ACTION_MAIN);
                baseIntent.addCategory(Intent.CATEGORY_LAUNCHER);
            }
        } else if (arg.indexOf(':') >= 0) {
            baseIntent = Intent.parseUri(arg, Intent.URI_INTENT_SCHEME
                    | Intent.URI_ANDROID_APP_SCHEME | Intent.URI_ALLOW_UNSAFE);
        } else if (arg.indexOf('/') >= 0) {
            baseIntent = new Intent(Intent.ACTION_MAIN);
            baseIntent.addCategory(Intent.CATEGORY_LAUNCHER);
            baseIntent.setComponent(ComponentName.unflattenFromString(arg));
        } else {
            baseIntent = new Intent(Intent.ACTION_MAIN);
            baseIntent.addCategory(Intent.CATEGORY_LAUNCHER);
            baseIntent.setPackage(arg);
        }
        if (baseIntent != null) {
            Bundle extras = intent.getExtras();
            intent.replaceExtras((Bundle) null);
            Bundle uriExtras = baseIntent.getExtras();
            baseIntent.replaceExtras((Bundle) null);
            if (intent.getAction() != null && baseIntent.getCategories() != null) {
                HashSet<String> cats = new HashSet<>(baseIntent.getCategories());
                for (String c : cats) baseIntent.removeCategory(c);
            }
            intent.fillIn(baseIntent, Intent.FILL_IN_COMPONENT | Intent.FILL_IN_SELECTOR);
            if (extras == null) {
                extras = uriExtras;
            } else if (uriExtras != null) {
                uriExtras.putAll(extras);
                extras = uriExtras;
            }
            intent.replaceExtras(extras);
            hasIntentInfo = true;
        }

        if (!hasIntentInfo) throw new IllegalArgumentException("No intent supplied");

        // 把 displayId 存入 extra，供启动阶段读取
        if (displayId >= 0) intent.putExtra(EXTRA_PEGASUS_DISPLAY_ID, displayId);

        return intent;
    }

    /**
     * 根据 EXTRA_PEGASUS_DISPLAY_ID，尽可能在指定 Display 启动。
     * - API >= 26 使用 ActivityOptions#setLaunchDisplayId
     * - 非 Activity 上下文自动添加 NEW_TASK/MULTIPLE_TASK
     * - 目标显示不存在或系统策略不允许时自动降级在默认屏启动
     */
    public static void startActivityWithOptions(Context context, Intent intent) {
        int displayId = intent.getIntExtra(EXTRA_PEGASUS_DISPLAY_ID, -1);

        // 1) 校验目标 Display 是否存在
        if (displayId >= 0) {
            try {
                DisplayManager dm = (DisplayManager) context.getSystemService(Context.DISPLAY_SERVICE);
                Display target = (dm != null) ? dm.getDisplay(displayId) : null;
                if (target == null) {
                    Log.w(TAG, "Target displayId " + displayId + " not found; fallback to default");
                    displayId = -1;
                } else {
                    try {
                        // 打印 flags（辅助判断是否为 Presentation/Private）
                        int flags = (int) Display.class.getMethod("getFlags").invoke(target);
                        Log.d(TAG, "Display#" + displayId + " flags=0x" + Integer.toHexString(flags));
                    } catch (Throwable ignore) {}
                }
            } catch (Throwable t) {
                Log.w(TAG, "Display check failed: " + t);
            }
        }

        // 2) 非 Activity 上下文 => 强制新任务，降低被合并回主屏概率
        if (!(context instanceof Activity)) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            intent.addFlags(Intent.FLAG_ACTIVITY_MULTIPLE_TASK);
            // 如需更“决绝”，可按需启用清任务：
            // intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TASK);
        }

        // 3) 传入 ActivityOptions（API 26+）
        Bundle opts = null;
        if (displayId >= 0 && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                ActivityOptions ao = ActivityOptions.makeBasic();
                ao.setLaunchDisplayId(displayId);
                opts = ao.toBundle();
            } catch (Throwable t) {
                Log.w(TAG, "setLaunchDisplayId not honored: " + t);
            }
        }

        // 4) 启动 & 兜底
        try {
            if (opts != null) context.startActivity(intent, opts);
            else context.startActivity(intent);
        } catch (Throwable t) {
            Log.e(TAG, "startActivity failed: " + t);
            try { context.startActivity(intent); } catch (Throwable ignore) {}
        }
    }
}
