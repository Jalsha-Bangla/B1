package com.fks.b1precision;

import android.Manifest;
import android.app.Activity;
import android.app.AlertDialog;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.content.Intent;
import android.content.Context;
import android.content.ComponentName;
import android.content.ServiceConnection;
import android.os.IBinder;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.hardware.Sensor;
import android.hardware.SensorEvent;
import android.hardware.SensorEventListener;
import android.hardware.SensorManager;
import android.os.Build;
import android.os.Bundle;
import android.os.SystemClock;
import android.view.Gravity;
import android.view.HapticFeedbackConstants;
import android.view.KeyEvent;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.PopupMenu;
import android.widget.TextView;
import android.widget.Toast;
import java.util.ArrayList;
import java.util.List;

/** Separate experimental APK, not an in-place update to the working v1.1.0 app. */
@SuppressWarnings("MissingPermission")
public final class MainActivity extends Activity implements SensorEventListener {
    private static final int BG = 0xff303135, SURFACE = 0xff222326, TEXT = 0xfff7f7fa;
    private static final int GREEN=0xff65dd91, ORANGE=0xffffb151;
    private HidTransport hid;
    private HidConnectionService hidService;
    private boolean serviceBound;
    private final ServiceConnection serviceConnection = new ServiceConnection() {
        @Override public void onServiceConnected(ComponentName name, IBinder binder) {
            hidService = ((HidConnectionService.LocalBinder) binder).getService();
            hid = hidService.transport();
            hidService.setUiListener(MainActivity.this::showConnectionStatus);
        }
        @Override public void onServiceDisconnected(ComponentName name) {
            hid = null;
            hidService = null;
            showConnectionStatus("SERVICE_DISCONNECTED", false);
        }
    };
    private void showConnectionStatus(String message, boolean connected) {
        if (btButton != null) {
            btButton.setTextColor(connected ? GREEN : ORANGE);
            btButton.setText("●");
        }
        if (stateText != null) stateText.setText(message);
    }
    private void startAndBindHidService() {
        Intent serviceIntent = new Intent(this, HidConnectionService.class);
        serviceIntent.setAction(HidConnectionService.ACTION_START);
        try {
            if (Build.VERSION.SDK_INT >= 26) startForegroundService(serviceIntent);
            else startService(serviceIntent);
            if (!serviceBound) {
                serviceBound = bindService(new Intent(this,HidConnectionService.class),
                        serviceConnection,Context.BIND_AUTO_CREATE);
            }
        } catch (RuntimeException ex) {
            showConnectionStatus("HID_SERVICE_START_FAILED_" + ex.getClass().getSimpleName(),false);
        }
    }
    private ControlPad pad;
    private SensorManager sensors;
    private Sensor gyro;
    private TextView btButton, stateText, title;
    private long lastGyroNs;
    private boolean active;
    private Haptics haptics;
    private boolean gyroTapMouse;
    private float gyroSensitivity, filteredDx, filteredDy;

    private int dp(float x){return (int)(getResources().getDisplayMetrics().density*x+.5f);}
    private GradientDrawable bg(int color,int r){GradientDrawable d=new GradientDrawable();d.setColor(color);d.setCornerRadius(dp(r));return d;}
    private TextView txt(String s,int sp){ TextView t=new TextView(this);t.setText(s);t.setTextSize(sp);t.setGravity(Gravity.CENTER);t.setTextColor(TEXT);t.setIncludeFontPadding(false);return t; }
    private LinearLayout.LayoutParams lp(int w,int h){return new LinearLayout.LayoutParams(w<0?w:dp(w),h<0?h:dp(h));}
    private void toast(String s){Toast.makeText(this,s,Toast.LENGTH_SHORT).show();}
    private void vibrate(View v){haptics.tick(v);}
    private void chooseGyroSensitivity(){
        final String[] labels={"Precise (0.85x)","Normal (1.3x)","Fast (1.8x)","Very fast (2.5x)"};
        final float[] values={0.85f,1.3f,1.8f,2.5f};
        new AlertDialog.Builder(this).setTitle("Gyro sensitivity")
            .setSingleChoiceItems(labels, gyroSensitivity<1.1f?0:gyroSensitivity<1.55f?1:gyroSensitivity<2.15f?2:3,
                (dialog,index)->{
                    gyroSensitivity=values[index];
                    getPreferences(MODE_PRIVATE).edit().putFloat("gyro_sensitivity",gyroSensitivity).apply();
                    filteredDx=filteredDy=0;
                    vibrate(pad);
                    dialog.dismiss();
                })
            .setNegativeButton("Cancel",null).show();
    }

    @Override public void onCreate(Bundle state){
        super.onCreate(state);
        getWindow().setStatusBarColor(BG);getWindow().setNavigationBarColor(BG);
        getWindow().getDecorView().setSystemUiVisibility(0);
        getWindow().setSoftInputMode(android.view.WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE);
        sensors=(SensorManager)getSystemService(SENSOR_SERVICE);
        gyro=sensors.getDefaultSensor(Sensor.TYPE_GYROSCOPE);
        gyroTapMouse=getPreferences(MODE_PRIVATE).getBoolean("gyro_mouse_click",true);
        gyroSensitivity=getPreferences(MODE_PRIVATE).getFloat("gyro_sensitivity",1.8f);
        haptics=new Haptics(this);
        buildUi();
        askBtPermissionsThenStart();
    }
    private void buildUi(){
        LinearLayout root=new LinearLayout(this);root.setOrientation(LinearLayout.VERTICAL);root.setBackgroundColor(BG);
        root.setPadding(dp(18),dp(10),dp(18),dp(14));
        setContentView(root);

        LinearLayout header=new LinearLayout(this);header.setOrientation(LinearLayout.HORIZONTAL);header.setGravity(Gravity.CENTER_VERTICAL);
        title=txt("B1",19);title.setTypeface(Typeface.DEFAULT,Typeface.BOLD);
        header.addView(title,new LinearLayout.LayoutParams(0,dp(50),1));
        btButton=txt("●",21);btButton.setTextColor(ORANGE);
        btButton.setBackground(bg(SURFACE,40));
        btButton.setOnClickListener(v->{vibrate(v);
            if(hidService!=null && hidService.isEnabled() && hid!=null) hid.retryRegistration();
            else startAndBindHidService();
        });
        header.addView(btButton,lp(45,45));
        TextView power=txt("⏻",25);power.setBackground(bg(SURFACE,40));
        LinearLayout.LayoutParams powerLp=lp(45,45);powerLp.leftMargin=dp(8);header.addView(power,powerLp);
        power.setOnClickListener(v->{vibrate(v);new AlertDialog.Builder(this).setTitle("B1 Power")
            .setMessage("Power HID mapping is not yet verified. The current B1 device will not be shut down.")
            .setPositiveButton("OK",null).show();});
        TextView menu=txt("⋮",26);menu.setBackground(bg(SURFACE,40));
        LinearLayout.LayoutParams menuLp=lp(45,45);menuLp.leftMargin=dp(8);header.addView(menu,menuLp);
        menu.setOnClickListener(v->{vibrate(v);PopupMenu popup=new PopupMenu(this,menu);
           popup.getMenu().add(0,ControlPad.DPAD,0,"D-Pad");
           popup.getMenu().add(0,ControlPad.SWIPE,1,"Swipe");
           popup.getMenu().add(0,ControlPad.GYRO,2,"Gyro");
           popup.getMenu().add(1,100,3,"Pair / choose HID host");
           popup.getMenu().add(1,101,4,"Enable Bluetooth discoverability");
           popup.getMenu().add(2,102,5,gyroTapMouse?"Gyro tap: Mouse (switch to Enter)":"Gyro tap: Enter (switch to Mouse)");
           popup.getMenu().add(2,103,6,"Gyro sensitivity");
           popup.getMenu().add(3,104,7,"Disconnect & stop background remote");
           popup.setOnMenuItemClickListener(item->{int id=item.getItemId();if(id<=2){pad.setMode(id);updateGyro();return true;}
              if(id==100){chooseHost();return true;}
              if(id==101){requestDiscoverable();return true;}
              if(id==102){gyroTapMouse=!gyroTapMouse;
                  getPreferences(MODE_PRIVATE).edit().putBoolean("gyro_mouse_click",gyroTapMouse).apply();
                  toast(gyroTapMouse?"Gyro click: Mouse":"Gyro click: Enter");return true;}
              if(id==103){chooseGyroSensitivity();return true;}
              if(id==104){
                  new AlertDialog.Builder(this).setTitle("Disconnect B1 Remote")
                      .setMessage("Stop the Bluetooth HID connection and background service?\nYou can reconnect using the orange button.")
                      .setPositiveButton("Disconnect",(d,which)->{
                          if(hidService!=null) hidService.stopByUser();
                          showConnectionStatus("DISCONNECTED_BY_USER",false);
                      })
                      .setNegativeButton("Cancel",null).show();
                  return true;
              }
              return false;});popup.show();});
        root.addView(header,lp(-1,52));

        stateText=txt("HID profile not yet tested",11);stateText.setTextColor(0xffb5b8bc);
        root.addView(stateText,lp(-1,32));
        pad=new ControlPad(this,new ControlPad.Listener(){
            public void onDirection(int usage){if(hid!=null) hid.key(usage);}
            public void onOk(){
                if(hid==null) return;
                if(pad!=null && pad.getMode()==ControlPad.GYRO && gyroTapMouse) hid.mouseClick();
                else hid.key(0x28);
            }
            public void onBack(){if(hid!=null) hid.back();}
        });
        LinearLayout.LayoutParams padLp=new LinearLayout.LayoutParams(-1,0,1);padLp.topMargin=dp(8);padLp.bottomMargin=dp(10);
        root.addView(pad,padLp);
        LinearLayout nav=new LinearLayout(this);nav.setGravity(Gravity.CENTER);nav.setOrientation(LinearLayout.HORIZONTAL);
        navButton(nav,"‹",()->{if(hid!=null) hid.back();});
        navButton(nav,"⌂",()->{if(hid!=null) hid.consumer(0x223);});  // AC Home; verify Android mapping during UAT
        navButton(nav,"✦",()->toast("Assistant HID mapping pending"));
        root.addView(nav,lp(-1,64));
        LinearLayout vol=new LinearLayout(this);vol.setGravity(Gravity.CENTER);vol.setOrientation(LinearLayout.HORIZONTAL);
        navButton(vol,"◀",()->{if(hid!=null) hid.consumer(0xe2);});
        navButton(vol,"−",()->{if(hid!=null) hid.consumer(0xea);});
        navButton(vol,"+",()->{if(hid!=null) hid.consumer(0xe9);});
        root.addView(vol,lp(-1,62));
    }
    private void navButton(LinearLayout row,String glyph,Runnable action){
        TextView button=txt(glyph,28);button.setBackground(bg(SURFACE,35));
        LinearLayout.LayoutParams params=new LinearLayout.LayoutParams(0,dp(54),1);params.setMargins(dp(3),dp(3),dp(3),dp(3));
        row.addView(button,params);
        button.setOnClickListener(v->{vibrate(v);action.run();});
    }
    private void askBtPermissionsThenStart(){
        if(Build.VERSION.SDK_INT>=31 && checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT)!=PackageManager.PERMISSION_GRANTED){
            requestPermissions(new String[]{Manifest.permission.BLUETOOTH_CONNECT,Manifest.permission.BLUETOOTH_ADVERTISE},701);return;
        }
        startAndBindHidService();
    }
    @Override public void onRequestPermissionsResult(int requestCode,String[] permissions,int[] grants){
        super.onRequestPermissionsResult(requestCode,permissions,grants);
        if(requestCode==701){if(grants.length>=1 && grants[0]==PackageManager.PERMISSION_GRANTED)startAndBindHidService();else toast("Bluetooth permission is required");}
    }
    private void chooseHost(){
        if(hid==null || !hid.isRegistered()){toast("HID must register first");return;}
        List<BluetoothDevice> found=new ArrayList<>(hid.bondedDevices());
        if(found.isEmpty()){
            new AlertDialog.Builder(this).setTitle("No paired HID hosts")
            .setMessage("Pair this phone with B1 in Android TV Bluetooth Settings first. No existing BLE pairing will be removed.")
            .setPositiveButton("OK",null).show();return;
        }
        String[] names=new String[found.size()];for(int i=0;i<found.size();i++)names[i]=hid.safeName(found.get(i));
        new AlertDialog.Builder(this).setTitle("Choose B1 HID host")
            .setItems(names,(dialog,index)->hid.connect(found.get(index)))
            .setNegativeButton("Cancel",null).show();
    }
    private void requestDiscoverable(){
        try{Intent i=new Intent(BluetoothAdapter.ACTION_REQUEST_DISCOVERABLE);
            i.putExtra(BluetoothAdapter.EXTRA_DISCOVERABLE_DURATION,120);startActivity(i);}
        catch(Exception e){toast("Open phone Bluetooth settings to pair");}
    }
    private void updateGyro(){
        if(sensors==null)return;
        sensors.unregisterListener(this);lastGyroNs=0;filteredDx=filteredDy=0;
        if(active && pad!=null && pad.getMode()==ControlPad.GYRO && gyro!=null){
            sensors.registerListener(this,gyro,SensorManager.SENSOR_DELAY_GAME);
        }
        if(pad!=null && pad.getMode()==ControlPad.GYRO && gyro==null)toast("Phone gyro sensor unavailable");
    }
    @Override public void onSensorChanged(SensorEvent event){
        if(pad==null || pad.getMode()!=ControlPad.GYRO || hid==null || !hid.isConnected())return;
        if(lastGyroNs!=0 && event.timestamp-lastGyroNs<25_000_000)return; // 40Hz max
        lastGyroNs=event.timestamp;
        // A relative HID mouse needs higher, adjustable gain on B1's TV.
        // Low-pass filtering reduces gyro jitter without losing responsiveness.
        float rawDx=-event.values[1]*13f*gyroSensitivity;
        float rawDy=-event.values[0]*13f*gyroSensitivity;
        filteredDx=filteredDx*0.32f+rawDx*0.68f;
        filteredDy=filteredDy*0.32f+rawDy*0.68f;
        int dx=Math.max(-127,Math.min(127,Math.round(filteredDx)));
        int dy=Math.max(-127,Math.min(127,Math.round(filteredDy)));
        if(dx==0 && dy==0)return;
        hid.mouse(dx,dy,false);
    }
    @Override public void onAccuracyChanged(Sensor sensor,int accuracy){}
    @Override protected void onResume(){
        super.onResume();
        active=true;
        if (hidService != null) hidService.setUiListener(this::showConnectionStatus);
        updateGyro();
    }
    @Override protected void onPause(){
        active=false;
        updateGyro();
        if (hidService != null) hidService.setUiListener(null);
        super.onPause();
    }
    @Override protected void onDestroy(){
        if (hidService != null) hidService.setUiListener(null);
        if (serviceBound) unbindService(serviceConnection);
        serviceBound = false;
        hidService = null;
        hid = null;
        super.onDestroy();
    }
    @Override public boolean onKeyDown(int keyCode,KeyEvent e){
        if(hid!=null && hid.isConnected()){
            if(keyCode==KeyEvent.KEYCODE_VOLUME_UP){hid.consumer(0xe9);return true;}
            if(keyCode==KeyEvent.KEYCODE_VOLUME_DOWN){hid.consumer(0xea);return true;}
        }
        return super.onKeyDown(keyCode,e);
    }
}
