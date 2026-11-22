package com.fks.b1precision;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.RectF;
import android.view.View;

/** Drawable power glyph; never depends on Unicode font coverage. */
public final class PowerIconView extends View {
    private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);

    public PowerIconView(Context context) {
        super(context);
        setContentDescription("AA TV Power / Standby");
        setClickable(true);
        setFocusable(true);
    }

    @Override protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        float cx=getWidth()/2f, cy=getHeight()/2f;
        float density=getResources().getDisplayMetrics().density;
        float radius=10*density;
        paint.setColor(Color.WHITE);
        paint.setStyle(Paint.Style.STROKE);
        paint.setStrokeWidth(2.35f*density);
        paint.setStrokeCap(Paint.Cap.ROUND);
        paint.setStrokeJoin(Paint.Join.ROUND);
        RectF oval=new RectF(cx-radius,cy-radius,cx+radius,cy+radius);
        canvas.drawArc(oval,-55,290,false,paint);
        canvas.drawLine(cx,cy-radius-2*density,cx,cy-1.4f*density,paint);
        paint.setStyle(Paint.Style.FILL);
    }
}
