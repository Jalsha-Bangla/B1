package com.fks.b1precision;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Bitmap;
import android.graphics.Path;
import android.graphics.Rect;
import android.graphics.Paint;
import android.graphics.RectF;
import android.os.Handler;
import android.os.Looper;
import android.view.MotionEvent;
import android.view.View;

/** Custom round D-pad, precision swipe, and gyro-tap surface. */
final class ControlPad extends View {
    interface Listener { void onDirection(int usage); void onOk(); void onBack(); }
    static final int DPAD = 0, SWIPE = 1, GYRO = 2;
    private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final Listener listener;
    private Bitmap swipeBackground;
    private final Haptics haptics;
    private int mode = DPAD, pressed = 0, repeatingUsage = 0;
    private float downX,downY, ballX,ballY,drawBallX,drawBallY;
    private boolean dragging, didSwipe;
    private long downTime, lastTap;
    private final Runnable repeating = new Runnable() {
        @Override public void run() {
            if(repeatingUsage == 0) return;
            hitDirection(repeatingUsage);
            handler.postDelayed(this,250);  // EXACT 4 events/sec while held
        }
    };
    ControlPad(Context context,Listener listener) {
        super(context);
        this.listener = listener;
        haptics = new Haptics(context);
        setHapticFeedbackEnabled(true);
    }
    int getMode(){return mode;}
    void setSwipeBackground(Bitmap bitmap) {
        swipeBackground=bitmap;
        invalidate();
    }
    void setMode(int m){mode=m;stopRepeat();dragging=false;invalidate();}
    void stopRepeat(){repeatingUsage=0;handler.removeCallbacks(repeating);}
    void hitDirection(int usage){haptics.tick(this);listener.onDirection(usage);}
    void hitOk(){haptics.tick(this);listener.onOk();}
    private int direction(float dx,float dy){return Math.abs(dx)>Math.abs(dy) ? (dx<0?0x50:0x4f) : (dy<0?0x52:0x51);}
    private float dp(float v){return v*getResources().getDisplayMetrics().density;}
    @Override protected void onDraw(Canvas c){
        float w=getWidth(),h=getHeight(), cx=w/2f,cy=h/2f;
        paint.setStyle(Paint.Style.FILL);
        if(mode==DPAD){
            float radius=Math.min(w,h)*.445f;
            paint.setColor(0xff191b1f);c.drawCircle(cx,cy,radius,paint);
            paint.setColor(0xff666970);c.drawCircle(cx,cy,radius*.43f,paint);
            paint.setColor(0xfffafafa);paint.setTextSize(radius*.28f);paint.setTextAlign(Paint.Align.CENTER);
            c.drawText("▲",cx,cy-radius*.68f+paint.getTextSize()*.3f,paint);
            c.drawText("▼",cx,cy+radius*.70f+paint.getTextSize()*.3f,paint);
            c.drawText("◀",cx-radius*.70f,cy+paint.getTextSize()*.3f,paint);
            c.drawText("▶",cx+radius*.70f,cy+paint.getTextSize()*.3f,paint);
        } else {
            float pad=dp(10);
            RectF panel = new RectF(pad,pad,w-pad,h-pad);
            float radius=dp(38);
            paint.setColor(0xff191b1f);
            c.drawRoundRect(panel,radius,radius,paint);
            if(mode==SWIPE && swipeBackground!=null && !swipeBackground.isRecycled()) {
                // The selected family photo stays in private app files and is never
                // packaged in the public repository. Crop to fill the SWIPE panel.
                int bw=swipeBackground.getWidth(), bh=swipeBackground.getHeight();
                float targetRatio=panel.width()/Math.max(1f,panel.height());
                float sourceRatio=(float)bw/Math.max(1,bh);
                Rect src;
                if(sourceRatio>targetRatio) {
                    int cropWidth=Math.max(1,Math.round(bh*targetRatio));
                    int left=(bw-cropWidth)/2;
                    src=new Rect(left,0,left+cropWidth,bh);
                } else {
                    int cropHeight=Math.max(1,Math.round(bw/targetRatio));
                    int top=(bh-cropHeight)/2;
                    src=new Rect(0,top,bw,top+cropHeight);
                }
                Path rounded=new Path();
                rounded.addRoundRect(panel,radius,radius,Path.Direction.CW);
                c.save();
                c.clipPath(rounded);
                paint.setColor(0xffffffff);
                paint.setAlpha(92); // light 36% opacity on the charcoal background
                paint.setFilterBitmap(true);
                c.drawBitmap(swipeBackground,src,panel,paint);
                paint.setAlpha(255);
                c.restore();
            }
            if(mode==SWIPE){
                paint.setColor(0xffefeff4);
                drawBallX+=(ballX-drawBallX)*.24f;
                drawBallY+=(ballY-drawBallY)*.24f;
                c.drawCircle(cx+drawBallX,cy+drawBallY,dp(23),paint);
                if(Math.abs(drawBallX-ballX)>.5f || Math.abs(drawBallY-ballY)>.5f)postInvalidateOnAnimation();
            }
        }
    }
    @Override public boolean onTouchEvent(MotionEvent e){
        float x=e.getX(),y=e.getY();
        switch(e.getActionMasked()){
            case MotionEvent.ACTION_DOWN:
                downX=x;downY=y; downTime=System.currentTimeMillis();didSwipe=false; dragging=true;
                if(mode==SWIPE){ballX=ballY=drawBallX=drawBallY=0; invalidate();}
                return true;
            case MotionEvent.ACTION_MOVE:
                if(mode==SWIPE){
                    ballX=Math.max(-getWidth()*.30f,Math.min(getWidth()*.30f,x-downX));
                    ballY=Math.max(-getHeight()*.30f,Math.min(getHeight()*.30f,y-downY));
                    if(!didSwipe && Math.hypot(x-downX,y-downY)>dp(42)){
                        didSwipe=true;repeatingUsage=direction(x-downX,y-downY);
                        hitDirection(repeatingUsage);handler.postDelayed(repeating,250);
                    }
                    invalidate();
                }
                return true;
            case MotionEvent.ACTION_UP:
                if(mode==DPAD){
                    float dx=x-getWidth()/2f,dy=y-getHeight()/2f;
                    float r=(float)Math.hypot(dx,dy), max=Math.min(getWidth(),getHeight())*.445f;
                    if(r<max*.43f)hitOk();else if(r<max)hitDirection(direction(dx,dy));
                } else if(mode==GYRO){
                    long now=System.currentTimeMillis();
                    if(now-lastTap<250){handler.removeCallbacksAndMessages(null);haptics.tick(this);listener.onBack();lastTap=0;}
                    else {lastTap=now;handler.postDelayed(()->{if(lastTap==now)hitOk();},260);}
                } else if(mode==SWIPE && !didSwipe)hitOk();
                stopRepeat();dragging=false;ballX=ballY=0;invalidate();return true;
            case MotionEvent.ACTION_CANCEL:
                stopRepeat();dragging=false;ballX=ballY=0;invalidate();return true;
        }
        return true;
    }
}
