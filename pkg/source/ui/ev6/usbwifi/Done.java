package ev6.usbwifi;

import android.content.Context;
import android.graphics.drawable.GradientDrawable;
import android.media.ToneGenerator;
import android.os.Handler;
import android.os.Looper;
import android.view.MotionEvent;
import android.view.View;
import android.view.WindowManager;
import android.widget.LinearLayout;
import android.widget.TextView;
import java.io.FileOutputStream;
import java.lang.reflect.Method;

/**
 * usbwifi.hotspot 4.14.1: the result of the Launch log copy as a window in the middle of the car's screen that stays
 * until the ✕ button is pressed (a toast is easy to miss). Same window method and look as the connection recorder's
 * panel (app_process, system context, an overlay window type the car accepts).
 *
 * app_process /system/bin ev6.usbwifi.Done ok|fail "<title>" "<message>" <status file>
 * The status file gets "shown type N" once the window is up, or "fail: why" (collect.sh then shows a toast instead).
 */
public final class Done {
    static final int BG_OK = 0xF2123524, BG_BAD = 0xF23A1416, EDGE_OK = 0xFF22C55E, EDGE_BAD = 0xFFEF4444;
    static final int TXT = 0xFFF1F5F9, DIM = 0xFFCBD5E1, BTN = 0xFF2A3B4D, BTN_DOWN = 0xFF4B647D;

    private static Context ctx;
    private static WindowManager wm;
    private static View root;
    private static ToneGenerator tg;

    private Done() {
    }

    public static void main(String[] a) {
        if (a.length < 4) {
            System.err.println("usage: Done ok|fail <title> <message> <status file>");
            System.exit(2);
        }
        final boolean good = "ok".equals(a[0]);
        final String title = a[1], msg = a[2].replace("\\n", "\n"), status = a[3];   // the shell passes "\n" as two characters
        try {
            Looper.prepareMainLooper();
        } catch (Throwable e) {
            Looper.prepare();
        }
        final Handler h = new Handler(Looper.myLooper());
        h.post(new Runnable() {
            int tries;

            public void run() {
                String why = show(good, title, msg);
                if (why == null) return;                         // shown: write done inside show()
                if (++tries < 10) {                              // window service not ready yet: try for 10 s
                    h.postDelayed(this, 1000);
                    return;
                }
                write(status, "fail: " + why);
                System.exit(1);
            }

            private String show(boolean ok, String t, String m) {
                if (!context()) return "no system context";
                int[] types = {2020, 2008, 2003, 2002};
                String last = "no window type accepted";
                for (int type : types) {
                    View v = build(ok, t, m);
                    try {
                        WindowManager.LayoutParams lp = new WindowManager.LayoutParams(-2, -2, type, 8 | 32 | 128 | 256, -3);
                        lp.gravity = 17;
                        lp.setTitle("EV6-UsbWifi-Done");
                        wm.addView(v, lp);
                        root = v;
                        write(status, "shown type " + type);
                        tone(ok ? ToneGenerator.TONE_PROP_ACK : ToneGenerator.TONE_PROP_NACK, ok ? 400 : 500);
                        return null;
                    } catch (Throwable th) {
                        last = "type " + type + ": " + th;
                        try {
                            wm.removeViewImmediate(v);
                        } catch (Throwable ignored) {
                        }
                    }
                }
                return last;
            }
        });
        Looper.loop();
    }

    private static boolean context() {
        if (ctx != null && wm != null) return true;
        try {
            Method m = Class.forName("android.os.ServiceManager").getMethod("getService", String.class);
            if (m.invoke(null, "window") == null || m.invoke(null, "activity") == null) return false;
            Class<?> at = Class.forName("android.app.ActivityThread");
            Object t = at.getMethod("currentActivityThread").invoke(null);
            if (t == null) t = at.getMethod("systemMain").invoke(null);
            ctx = (Context) at.getMethod("getSystemContext").invoke(t);
            wm = (WindowManager) ctx.getSystemService("window");
            return ctx != null && wm != null;
        } catch (Throwable th) {
            ctx = null;
            wm = null;
            return false;
        }
    }

    private static View build(boolean ok, String title, String msg) {
        int sw = ctx.getResources().getDisplayMetrics().widthPixels;
        LinearLayout frame = new LinearLayout(ctx);
        frame.setOrientation(LinearLayout.VERTICAL);
        frame.setPadding(34, 22, 22, 30);
        frame.setMinimumWidth(Math.max(560, sw * 45 / 100));
        frame.setBackgroundDrawable(round(ok ? BG_OK : BG_BAD, ok ? EDGE_OK : EDGE_BAD, 4));

        LinearLayout head = new LinearLayout(ctx);
        head.setOrientation(LinearLayout.HORIZONTAL);
        head.setGravity(16);
        TextView t = text((ok ? "✔  " : "✖  ") + title, 27f, ok ? EDGE_OK : EDGE_BAD);
        head.addView(t, new LinearLayout.LayoutParams(0, -2, 1f));
        TextView x = text("✕", 30f, TXT);
        x.setGravity(17);
        x.setPadding(26, 6, 26, 10);
        x.setMinWidth(88);
        x.setMinHeight(80);
        x.setBackgroundDrawable(round(BTN, 0xFF3A4E63, 2));
        x.setOnTouchListener(new View.OnTouchListener() {
            public boolean onTouch(View v, MotionEvent e) {
                int act = e.getActionMasked();
                if (act == MotionEvent.ACTION_DOWN) {
                    v.setBackgroundDrawable(round(BTN_DOWN, 0xFFFFFFFF, 2));
                    tone(ToneGenerator.TONE_PROP_BEEP, 45);
                } else if (act == MotionEvent.ACTION_UP) {
                    close();
                } else if (act == MotionEvent.ACTION_CANCEL) {
                    v.setBackgroundDrawable(round(BTN, 0xFF3A4E63, 2));
                }
                return true;
            }
        });
        LinearLayout.LayoutParams xl = new LinearLayout.LayoutParams(-2, -2);
        xl.leftMargin = 20;
        head.addView(x, xl);
        frame.addView(head, new LinearLayout.LayoutParams(-1, -2));

        TextView m = text(msg, 22f, TXT);
        m.setLineSpacing(6f, 1f);
        m.setMaxWidth(sw * 60 / 100);
        LinearLayout.LayoutParams ml = new LinearLayout.LayoutParams(-2, -2);
        ml.topMargin = 22;
        ml.rightMargin = 12;
        frame.addView(m, ml);

        TextView hint = text("✕ 를 누르면 닫힙니다", 16f, DIM);
        LinearLayout.LayoutParams hl = new LinearLayout.LayoutParams(-2, -2);
        hl.topMargin = 18;
        frame.addView(hint, hl);
        return frame;
    }

    private static void close() {
        try {
            if (root != null) wm.removeViewImmediate(root);
        } catch (Throwable ignored) {
        }
        System.exit(0);
    }

    private static GradientDrawable round(int fill, int stroke, int width) {
        GradientDrawable g = new GradientDrawable();
        g.setColor(fill);
        g.setCornerRadius(16f);
        g.setStroke(width, stroke);
        return g;
    }

    private static TextView text(String s, float size, int color) {
        TextView t = new TextView(ctx);
        t.setText(s);
        t.setTextSize(size);
        t.setTextColor(color);
        return t;
    }

    private static void tone(int tone, int ms) {
        try {
            if (tg == null) tg = new ToneGenerator(1, 90);   // STREAM_SYSTEM
            tg.startTone(tone, ms);
        } catch (Throwable ignored) {
        }
    }

    private static void write(String path, String s) {
        try {
            FileOutputStream o = new FileOutputStream(path);
            o.write((s + "\n").getBytes("UTF-8"));
            o.close();
        } catch (Throwable ignored) {
        }
    }
}
