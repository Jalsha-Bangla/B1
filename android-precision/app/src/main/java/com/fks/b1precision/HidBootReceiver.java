package com.fks.b1precision;

import android.Manifest;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Build;
import android.util.Log;

/** Best-effort restart after phone reboot/app update, only if user opted in. */
public final class HidBootReceiver extends BroadcastReceiver {
    private static final String TAG = "B1HidBoot";
    @Override public void onReceive(Context context, Intent intent) {
        String action = intent == null ? "" : intent.getAction();
        if (!Intent.ACTION_BOOT_COMPLETED.equals(action)
                && !Intent.ACTION_MY_PACKAGE_REPLACED.equals(action)) return;
        if (!context.getSharedPreferences(HidConnectionService.PREFS, Context.MODE_PRIVATE)
                .getBoolean(HidConnectionService.KEEP_RUNNING, false)) return;
        if (Build.VERSION.SDK_INT >= 31 &&
                context.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT)
                        != PackageManager.PERMISSION_GRANTED) return;
        Intent service = new Intent(context, HidConnectionService.class);
        service.setAction(HidConnectionService.ACTION_AUTO);
        try {
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(service);
            else context.startService(service);
        } catch (RuntimeException e) {
            // OEM background-start restrictions can block auto-start. User opening
            // the app must always remain a safe recovery path.
            Log.w(TAG, "Automatic service startup blocked by OS", e);
        }
    }
}
