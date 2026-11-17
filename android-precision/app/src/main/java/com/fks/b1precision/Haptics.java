package com.fks.b1precision;

import android.content.Context;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.view.HapticFeedbackConstants;
import android.view.View;

/** Short, subtle tactile confirmation for direct remote interactions. */
final class Haptics {
    private final Vibrator vibrator;

    Haptics(Context context) {
        vibrator = (Vibrator) context.getSystemService(Context.VIBRATOR_SERVICE);
    }

    void tick(View view) {
        try {
            if (vibrator != null && vibrator.hasVibrator()) {
                // Programmatic vibration is more reliable than View haptics
                // when custom canvas regions have no native click semantics.
                vibrator.vibrate(VibrationEffect.createOneShot(11, 42));
                return;
            }
        } catch (RuntimeException ignored) {
            // Fall back to the framework's system-configured tap feedback.
        }
        if (view != null) view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP);
    }
}
