package com.fks.b1precision;

import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothHidDevice;
import android.bluetooth.BluetoothHidDeviceAppSdpSettings;
import android.bluetooth.BluetoothManager;
import android.bluetooth.BluetoothProfile;
import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import java.util.Set;

/** Experimental native HID keyboard/mouse transport, isolated from existing BLE remote. */
@SuppressWarnings("MissingPermission")
final class HidTransport {
    interface Listener { void onState(String state, boolean connected); }
    private static final String TAG = "B1PrecisionHID";
    private static final int KEYBOARD = 1, MOUSE = 2, CONSUMER = 3;
    private static final byte[] DESCRIPTOR = new byte[] {
        // Keyboard report ID 1, 8 bytes
        0x05,0x01,0x09,0x06,(byte)0xA1,0x01,(byte)0x85,0x01,
        0x05,0x07,0x19,(byte)0xE0,0x29,(byte)0xE7,0x15,0x00,0x25,0x01,
        0x75,0x01,(byte)0x95,0x08,(byte)0x81,0x02,
        (byte)0x95,0x01,0x75,0x08,(byte)0x81,0x01,
        (byte)0x95,0x06,0x75,0x08,0x15,0x00,0x25,0x65,
        0x05,0x07,0x19,0x00,0x29,0x65,(byte)0x81,0x00,(byte)0xC0,
        // Relative mouse report ID 2, buttons + X/Y; zero scroll
        0x05,0x01,0x09,0x02,(byte)0xA1,0x01,(byte)0x85,0x02,0x09,0x01,(byte)0xA1,0x00,
        0x05,0x09,0x19,0x01,0x29,0x03,0x15,0x00,0x25,0x01,
        (byte)0x95,0x03,0x75,0x01,(byte)0x81,0x02,
        (byte)0x95,0x01,0x75,0x05,(byte)0x81,0x01,
        0x05,0x01,0x09,0x30,0x09,0x31,0x15,(byte)0x81,0x25,0x7f,
        0x75,0x08,(byte)0x95,0x02,(byte)0x81,0x06,(byte)0xC0,(byte)0xC0,
        // Consumer control report ID 3, 16-bit usage; Volume +/-/Mute/AC Home
        0x05,0x0c,0x09,0x01,(byte)0xA1,0x01,(byte)0x85,0x03,
        0x15,0x00,0x26,(byte)0xff,0x03,0x19,0x00,
        0x2a,(byte)0xff,0x03,0x75,0x10,(byte)0x95,0x01,
        (byte)0x81,0x00,(byte)0xC0
    };
    private final Context context;
    private final Listener listener;
    private final Handler handler = new Handler(Looper.getMainLooper());
    private BluetoothAdapter adapter;
    private BluetoothHidDevice hid;
    private BluetoothDevice host;
    private BluetoothDevice preferred;
    private boolean registered;
    private boolean connected;
    private boolean foreground;
    private boolean proxyPending;
    private boolean registrationPending;
    private int foregroundRetries;
    private int reconnectAttempts;
    private boolean mouseButtonHeld;
    private final Runnable mouseRelease = () -> {
        mouseButtonHeld = false;
        send(MOUSE, new byte[]{0,0,0});
    };
    private static final int MAX_RECONNECT_ATTEMPTS = 3;
    private static final String PREF_NAME = "b1_precision_hid";
    private static final String PREF_B1_ADDR = "verified_b1_host_address";
    private final Runnable reconnectTask = new Runnable() {
        @Override public void run() {
        if (!foreground || !registered || isConnected()) return;
        if (reconnectAttempts >= MAX_RECONNECT_ATTEMPTS) {
            state("HID_RECONNECT_PAUSED_TAP_ORANGE");
            return;
        }
        BluetoothDevice target = rememberedB1();
        if (target == null) {
            state("HID_REGISTERED_PAIR_WITH_B1");
            return;
        }
        reconnectAttempts++;
        try {
            if (!hid.connect(target)) state("HID_RECONNECT_REQUEST_REJECTED");
            else state("HID_RECONNECTING_B1_" + reconnectAttempts);
        } catch (RuntimeException e) {
            state("HID_RECONNECT_ERROR_" + e.getClass().getSimpleName());
        }
        if (!isConnected() && reconnectAttempts < MAX_RECONNECT_ATTEMPTS) {
            handler.postDelayed(this, 1900);
        }
        }
    };

    private BluetoothDevice rememberedB1() {
        if (adapter == null) return null;
        if (preferred != null && "B1".equalsIgnoreCase(safeName(preferred))
                && preferred.getBondState() == BluetoothDevice.BOND_BONDED) return preferred;
        String address = context.getSharedPreferences(PREF_NAME,Context.MODE_PRIVATE)
                .getString(PREF_B1_ADDR, null);
        if (address == null) return null;
        try {
            BluetoothDevice device = adapter.getRemoteDevice(address);
            if (!"B1".equalsIgnoreCase(safeName(device))
                    || device.getBondState() != BluetoothDevice.BOND_BONDED) return null;
            preferred = device;
            return device;
        } catch (RuntimeException ignored) { return null; }
    }
    private void queueReconnect(long delayMs) {
        handler.removeCallbacks(reconnectTask);
        if (foreground && registered && !isConnected() && rememberedB1() != null) {
            handler.postDelayed(reconnectTask, delayMs);
        }
    }

    HidTransport(Context context, Listener listener) { this.context = context; this.listener = listener; }

    void start() {
        if (proxyPending || registrationPending || registered) return;
        if (hid != null) { register(); return; }
        try {
            BluetoothManager bm = (BluetoothManager) context.getSystemService(Context.BLUETOOTH_SERVICE);
            adapter = bm == null ? null : bm.getAdapter();
            if (adapter == null) { state("NO_BLUETOOTH_ADAPTER"); return; }
            if (!adapter.isEnabled()) { state("BLUETOOTH_OFF"); return; }
            state("REQUESTING_HID_DEVICE_PROFILE");
            proxyPending = true;
            if (!adapter.getProfileProxy(context, new BluetoothProfile.ServiceListener() {
                @Override public void onServiceConnected(int profile, BluetoothProfile proxy) {
                    proxyPending = false;
                    if (!(proxy instanceof BluetoothHidDevice)) { state("HID_PROXY_UNAVAILABLE"); return; }
                    hid = (BluetoothHidDevice) proxy;
                    register();
                }
                @Override public void onServiceDisconnected(int profile) {
                    proxyPending = false;
                    registrationPending = false;
                    connected = false; registered = false; host = null; hid = null; state("HID_PROFILE_DISCONNECTED");
                }
            }, BluetoothProfile.HID_DEVICE)) {
                proxyPending = false;
                state("HID_DEVICE_UNSUPPORTED_ON_PHONE");
            }
        } catch (SecurityException e) { proxyPending = false; state("BLUETOOTH_PERMISSION_DENIED"); }
        catch (Exception e) { proxyPending = false; state("HID_PROFILE_ERROR:"+e.getClass().getSimpleName()); }
    }

    private void register() {
        if (hid == null || registered || registrationPending) return;
        registrationPending = true;
        try {
            BluetoothHidDeviceAppSdpSettings sdp = new BluetoothHidDeviceAppSdpSettings(
                "B1 Precision Remote", "Keyboard and relative mouse HID test", "FKS",
                BluetoothHidDevice.SUBCLASS1_COMBO, DESCRIPTOR);
            boolean accepted = hid.registerApp(sdp, null, null, context.getMainExecutor(), new BluetoothHidDevice.Callback() {
                @Override public void onAppStatusChanged(BluetoothDevice pluggedDevice, boolean isRegistered) {
                    registrationPending = false;
                    registered = isRegistered;
                    if (isRegistered) {
                        foregroundRetries = 0;
                        reconnectAttempts = 0;
                        state("HID_REGISTERED_PAIR_WITH_B1");
                        queueReconnect(300);
                    } else {
                        connected = false;
                        host = null;
                        state(foreground ? "HID_UNREGISTERED_RETRYING" : "HID_RELEASED_IN_BACKGROUND");
                        // Android unregisters HID Device apps that leave foreground.
                        // Retry only after returning to the foreground, with a strict cap.
                        if (foreground && foregroundRetries < 2) {
                            foregroundRetries++;
                            handler.postDelayed(() -> {
                                if (foreground && !registered && !registrationPending) register();
                            }, 650);
                        }
                    }
                }
                @Override public void onConnectionStateChanged(BluetoothDevice device, int newState) {
                    connected = newState == BluetoothProfile.STATE_CONNECTED;
                    if (connected) {
                        host = device;
                        handler.removeCallbacks(reconnectTask);
                        reconnectAttempts = 0;
                        // Persist only a confirmed B1 bond, never headphones.
                        if ("B1".equalsIgnoreCase(safeName(device))) {
                            preferred = device;
                            context.getSharedPreferences(PREF_NAME,Context.MODE_PRIVATE)
                                    .edit().putString(PREF_B1_ADDR,device.getAddress()).apply();
                        }
                        state("HID_CONNECTED_TO_" + safeName(device));
                    } else {
                        host = null;
                        state("HID_CONNECTION_STATE_" + newState);
                        if (newState == BluetoothProfile.STATE_DISCONNECTED) queueReconnect(700);
                    }
                }
            });
            if (!accepted) {
                registrationPending = false;
                state("HID_REGISTER_REQUEST_REJECTED");
            }
        } catch (Exception e) {
            registrationPending = false;
            state("HID_REGISTER_EXCEPTION:"+e.getClass().getSimpleName());
        }
    }

    /** Re-register after the system's Bluetooth discoverability UI returns. */
    void onForeground() {
        foreground = true;
        foregroundRetries = 0;
        if (!registered && !registrationPending) start();
        else if (registered && !isConnected()) queueReconnect(350);
    }
    void onBackground() {
        foreground = false;
        handler.removeCallbacks(reconnectTask);
    }
    void retryRegistration() {
        reconnectAttempts = 0;
        if (registered) { queueReconnect(0); return; }
        foregroundRetries = 0;
        start();
    }

    Set<BluetoothDevice> bondedDevices() { return adapter == null ? java.util.Collections.emptySet() : adapter.getBondedDevices(); }
    String safeName(BluetoothDevice device) {
        try { String name = device.getName(); return name == null ? device.getAddress() : name; }
        catch(Exception ignored) { return "Bluetooth host"; }
    }
    void connect(BluetoothDevice device) {
        if ("B1".equalsIgnoreCase(safeName(device))) preferred = device;
        if (!registered || hid == null) { state("HID_NOT_REGISTERED"); return; }
        handler.removeCallbacks(reconnectTask);
        reconnectAttempts = 0;
        try { state(hid.connect(device) ? "HID_CONNECTING_TO_" + safeName(device) : "HID_CONNECT_REQUEST_REJECTED"); }
        catch(Exception e) { state("HID_CONNECT_EXCEPTION:"+e.getClass().getSimpleName()); }
    }
    void reconnect() {
        BluetoothDevice target = rememberedB1();
        if (target != null) connect(target);
        else state("PAIR_B1_AND_SELECT_HOST");
    }
    boolean isConnected() { return connected && host != null && hid != null; }
    boolean isRegistered() { return registered; }

    private boolean send(int reportId, byte[] data) {
        if (!isConnected()) return false;
        try { return hid.sendReport(host, reportId, data); }
        catch (Exception e) { Log.w(TAG,"sendReport",e); state("HID_SEND_FAILED"); return false; }
    }
    void key(int usage) {
        if (!isConnected()) { state("CONNECT_B1_HID_FIRST"); return; }
        byte[] b = new byte[8]; b[2] = (byte) usage;
        send(KEYBOARD,b);
        handler.postDelayed(() -> send(KEYBOARD,new byte[8]),55);
    }
    /** HID Consumer AC Back maps to Android KEYCODE_BACK on standard key layouts. */
    void back() { consumer(0x224); }
    void consumer(int usage) {
        if (!isConnected()) { state("CONNECT_B1_HID_FIRST"); return; }
        send(CONSUMER,new byte[]{ (byte)usage,(byte)(usage >> 8)});
        handler.postDelayed(() -> send(CONSUMER,new byte[]{0,0}),55);
    }
    void mouse(int dx,int dy,boolean click) {
        send(MOUSE,new byte[]{(byte)((click || mouseButtonHeld) ? 1 : 0),
                (byte)Math.max(-127,Math.min(127,dx)),
                (byte)Math.max(-127,Math.min(127,dy))});
    }
    void mouseClick() {
        // Keep the button down during gyro movement frames until release.
        handler.removeCallbacks(mouseRelease);
        mouseButtonHeld = true;
        mouse(0,0,true);
        handler.postDelayed(mouseRelease,85);
    }
    void release() {
        foreground = false;
        handler.removeCallbacks(reconnectTask);
        handler.removeCallbacks(mouseRelease);
        mouseButtonHeld = false;
        try { if (hid != null && registered) hid.unregisterApp(); }
        catch (Exception ignored) {}
        if(adapter != null && hid != null) adapter.closeProfileProxy(BluetoothProfile.HID_DEVICE,hid);
        hid = null; host = null; connected = false; registered = false;
        proxyPending = false; registrationPending = false; foreground = false;
    }
    private void state(String s) { handler.post(() -> listener.onState(s, isConnected())); }
}
