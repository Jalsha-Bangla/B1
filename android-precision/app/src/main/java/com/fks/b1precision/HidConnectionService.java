package com.fks.b1precision;

import android.Manifest;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.bluetooth.BluetoothAdapter;
import android.content.BroadcastReceiver;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.ServiceInfo;
import android.os.Binder;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.util.Log;

/** Owns the ONLY BluetoothHidDevice registration beyond an Activity lifecycle.
 *  Foreground connectedDevice service is best-effort, NOT an OS guarantee. */
public final class HidConnectionService extends Service {
    public static final String ACTION_START = "com.fks.b1precision.START_HID";
    public static final String ACTION_STOP = "com.fks.b1precision.STOP_HID";
    public static final String ACTION_AUTO = "com.fks.b1precision.AUTO_START_HID";
    static final String PREFS = "hid_service_pref";
    static final String KEEP_RUNNING = "keep_running_until_disconnect";
    private static final int NOTICE_ID = 1202;
    private static final String CHANNEL_ID = "b1_hid_background";
    private static final String TAG = "B1PrecisionService";
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final IBinder binder = new LocalBinder();
    private HidTransport hid;
    private UiListener uiListener;
    private boolean active;
    private boolean receiverRegistered;
    private boolean connected;
    private String currentState = "BLUETOOTH_STARTING";
    private int priorNotificationState = -1;

    public interface UiListener { void onStatus(String state, boolean connected); }
    public final class LocalBinder extends Binder {
        public HidConnectionService getService() { return HidConnectionService.this; }
    }
    public HidTransport transport() { return hid; }
    public boolean isEnabled() { return active; }
    public void setUiListener(UiListener listener) {
        uiListener = listener;
        if (uiListener != null) uiListener.onStatus(currentState, connected);
    }

    private final Runnable healthCheck = new Runnable() {
        @Override public void run() {
            if (!active) return;
            if (hid != null && !hid.isConnected()) {
                // A powered-off B1 should recover when it next becomes available.
                // HID connect never creates a bond or reopens pairing dialogs on purpose.
                hid.retryRegistration();
            }
            handler.postDelayed(this, 30000);
        }
    };

    private final BroadcastReceiver bluetoothReceiver = new BroadcastReceiver() {
        @Override public void onReceive(Context context, Intent intent) {
            if (!active || hid == null) return;
            if (BluetoothAdapter.ACTION_STATE_CHANGED.equals(intent.getAction())) {
                int state = intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR);
                if (state == BluetoothAdapter.STATE_ON) {
                    handler.postDelayed(() -> {
                        if (active && hid != null) hid.retryRegistration();
                    }, 1800);
                } else if (state == BluetoothAdapter.STATE_OFF) {
                    onTransportState("PHONE_BLUETOOTH_OFF", false);
                }
            }
        }
    };

    @Override public void onCreate() {
        super.onCreate();
        createChannel();
        hid = new HidTransport(getApplicationContext(), this::onTransportState);
        IntentFilter filter = new IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED);
        try {
            if (Build.VERSION.SDK_INT >= 33) {
                // Bluetooth broadcasts may come from privileged, non-system UID.
                registerReceiver(bluetoothReceiver, filter, Context.RECEIVER_EXPORTED);
            } else registerReceiver(bluetoothReceiver, filter);
            receiverRegistered = true;
        } catch (RuntimeException ex) {
            Log.w(TAG, "Bluetooth state receiver not available", ex);
        }
    }

    private void onTransportState(String state, boolean nowConnected) {
        currentState = state;
        connected = nowConnected;
        if (uiListener != null) uiListener.onStatus(state, nowConnected);
        if (active) refreshNotification();
    }

    private void createChannel() {
        NotificationManager nm = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
        if (nm == null) return;
        NotificationChannel channel = new NotificationChannel(CHANNEL_ID,
                "AA TV Bluetooth Remote", NotificationManager.IMPORTANCE_LOW);
        channel.setDescription("Keeps your paired B1 HID remote connected while locked");
        nm.createNotificationChannel(channel);
    }

    private Notification notification() {
        Intent open = new Intent(this, MainActivity.class);
        PendingIntent tap = PendingIntent.getActivity(this, 0, open,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        Intent disconnect = new Intent(this, HidConnectionService.class);
        disconnect.setAction(ACTION_STOP);
        PendingIntent stop = PendingIntent.getService(this, 1, disconnect,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        Notification.Builder b = new Notification.Builder(this, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
                .setContentTitle("AA TV Remote")
                .setContentText(connected ? "Connected — works while locked" : "Ready — reconnecting when B1 is available")
                .setContentIntent(tap)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .addAction(new Notification.Action.Builder(null, "Disconnect", stop).build());
        return b.build();
    }

    private void refreshNotification() {
        int state = connected ? 1 : 0;
        if (state == priorNotificationState) return;
        priorNotificationState = state;
        NotificationManager nm = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
        if (nm != null) nm.notify(NOTICE_ID, notification());
    }

    private boolean promoteToForeground() {
        try {
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(NOTICE_ID, notification(),
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE);
            } else startForeground(NOTICE_ID, notification());
            priorNotificationState = connected ? 1 : 0;
            return true;
        } catch (RuntimeException ex) {
            Log.e(TAG, "Cannot run connectedDevice foreground service", ex);
            onTransportState("BACKGROUND_SERVICE_ERROR_" + ex.getClass().getSimpleName(), false);
            return false;
        }
    }

    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        String action = intent == null ? ACTION_AUTO : intent.getAction();
        if (ACTION_STOP.equals(action)) {
            stopByUser();
            return START_NOT_STICKY;
        }
        boolean savedEnabled = getSharedPreferences(PREFS, MODE_PRIVATE)
                .getBoolean(KEEP_RUNNING, false);
        if (ACTION_AUTO.equals(action) && !savedEnabled) {
            stopSelf(startId);
            return START_NOT_STICKY;
        }
        if (!ACTION_AUTO.equals(action)) {
            getSharedPreferences(PREFS, MODE_PRIVATE).edit()
                    .putBoolean(KEEP_RUNNING, true).apply();
        }
        if (!active) {
            active = true;
            if (!promoteToForeground()) {
                active = false;
                stopSelf(startId);
                return START_NOT_STICKY;
            }
            if (hid != null) hid.onForeground();
            handler.removeCallbacks(healthCheck);
            handler.postDelayed(healthCheck, 30000);
        } else if (hid != null && !hid.isConnected()) hid.retryRegistration();
        return START_STICKY;
    }

    public void stopByUser() {
        getSharedPreferences(PREFS, MODE_PRIVATE).edit()
                .putBoolean(KEEP_RUNNING, false).apply();
        active = false;
        handler.removeCallbacks(healthCheck);
        if (hid != null) hid.release();
        onTransportState("DISCONNECTED_BY_USER", false);
        stopForeground(STOP_FOREGROUND_REMOVE);
        stopSelf();
    }

    @Override public IBinder onBind(Intent intent) { return binder; }

    @Override public void onDestroy() {
        active = false;
        handler.removeCallbacks(healthCheck);
        if (receiverRegistered) {
            try { unregisterReceiver(bluetoothReceiver); } catch (RuntimeException ignored) {}
        }
        if (hid != null) hid.release();
        uiListener = null;
        super.onDestroy();
    }
}
