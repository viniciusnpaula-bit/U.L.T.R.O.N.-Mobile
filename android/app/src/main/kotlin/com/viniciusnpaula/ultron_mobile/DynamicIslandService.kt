package com.viniciusnpaula.ultron_mobile

import android.animation.ValueAnimator
import android.app.KeyguardManager
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Typeface
import android.media.AudioManager
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.util.TypedValue
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.view.animation.DecelerateInterpolator
import android.view.animation.LinearInterpolator
import android.view.animation.OvershootInterpolator
import androidx.core.content.ContextCompat
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.sin

enum class IslandMode(val id: String) {
    IDLE("idle"),
    LISTENING("listening"),
    PROCESSING("processing"),
    SPEAKING("speaking"),
    MEDIA("media"),
    NOTIFICATION("notification"),
    CHARGING("charging");

    companion object {
        fun fromId(raw: String?): IslandMode = when (raw?.trim()?.lowercase()) {
            "listening", "ouvindo" -> LISTENING
            "processing", "thinking", "processando" -> PROCESSING
            "speaking", "falando" -> SPEAKING
            "media", "musica", "spotify" -> MEDIA
            "notification", "notificacao", "urgente" -> NOTIFICATION
            "charging", "carregando" -> CHARGING
            else -> IDLE
        }
    }
}

/**
 * Ilha Dinâmica Expressiva nativa inspirada no EvanKoe/expressive-cutout:
 * ancora ao redor do recorte da câmera frontal (`DisplayCutout`) com morphing
 * físico (Overshoot spring) em 3 estágios (compacto, ativo, expandido),
 * gestos de toque/deslize, mídia, voz em 2º plano, alertas urgentes e carregamento.
 */
class DynamicIslandService : Service() {

    companion object {
        const val PREF_ISLAND_ENABLED = "dynamic_island_enabled"
        const val ACTION_STOP = "com.viniciusnpaula.ultron_mobile.STOP_DYNAMIC_ISLAND"

        private val mainHandler = Handler(Looper.getMainLooper())

        @Volatile
        var isRunning: Boolean = false
            private set

        @Volatile
        var currentMode: IslandMode = IslandMode.IDLE
            private set

        @Volatile
        var accentColorArgb: Int = Color.rgb(241, 13, 40)
            private set

        @Volatile
        var headline: String = "U.L.T.R.O.N."
            private set

        @Volatile
        var subtitle: String = "Pronto"
            private set

        @Volatile
        var mediaTitle: String = ""
            private set

        @Volatile
        var mediaArtist: String = ""
            private set

        @Volatile
        var mediaPlaying: Boolean = false
            private set

        @Volatile
        var isSessionLocked: Boolean = true
            private set

        @Volatile
        private var instance: DynamicIslandService? = null

        private val autoResetRunnable = Runnable {
            val svc = instance ?: return@Runnable
            if (currentMode == IslandMode.NOTIFICATION || currentMode == IslandMode.CHARGING) {
                if (mediaPlaying && mediaTitle.isNotBlank()) {
                    currentMode = IslandMode.MEDIA
                    headline = mediaTitle
                    subtitle = mediaArtist.ifBlank { "Tocando agora" }
                } else {
                    currentMode = IslandMode.IDLE
                    headline = "U.L.T.R.O.N."
                    subtitle = "Pronto"
                }
                svc.morphToTarget(expanded = false)
            }
        }

        private val autoCollapseExpandedRunnable = Runnable {
            instance?.morphToTarget(expanded = false)
        }

        fun canDraw(context: Context): Boolean =
            Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(context)

        fun isEnabledPref(context: Context): Boolean =
            context.getSharedPreferences(UltronAudioService.PREFS_NAME, Context.MODE_PRIVATE)
                .getBoolean(PREF_ISLAND_ENABLED, false)

        fun start(context: Context): Boolean {
            if (!canDraw(context)) return false
            return try {
                context.getSharedPreferences(UltronAudioService.PREFS_NAME, Context.MODE_PRIVATE)
                    .edit()
                    .putBoolean(PREF_ISLAND_ENABLED, true)
                    .apply()
                context.startService(Intent(context, DynamicIslandService::class.java))
                true
            } catch (_: Exception) {
                false
            }
        }

        fun stop(context: Context) {
            try {
                context.getSharedPreferences(UltronAudioService.PREFS_NAME, Context.MODE_PRIVATE)
                    .edit()
                    .putBoolean(PREF_ISLAND_ENABLED, false)
                    .apply()
                context.stopService(Intent(context, DynamicIslandService::class.java))
            } catch (_: Exception) {
            }
        }

        fun setAccentColor(argb: Int) {
            accentColorArgb = argb
            mainHandler.post { instance?.islandView?.invalidate() }
        }

        fun updateAuthState(locked: Boolean) {
            isSessionLocked = locked
            mainHandler.post { instance?.islandView?.invalidate() }
        }

        fun updateState(modeId: String, title: String = "", detail: String = "") {
            val mode = IslandMode.fromId(modeId)
            mainHandler.post {
                mainHandler.removeCallbacks(autoResetRunnable)
                if (mode == IslandMode.IDLE && mediaPlaying && mediaTitle.isNotBlank()) {
                    currentMode = IslandMode.MEDIA
                    headline = mediaTitle
                    subtitle = mediaArtist.ifBlank { "Tocando agora" }
                } else {
                    currentMode = mode
                    headline = title.ifBlank {
                        when (mode) {
                            IslandMode.LISTENING -> "Ouvindo..."
                            IslandMode.PROCESSING -> "Processando..."
                            IslandMode.SPEAKING -> "Respondendo"
                            IslandMode.MEDIA -> mediaTitle.ifBlank { "Mídia" }
                            IslandMode.NOTIFICATION -> "Alerta"
                            IslandMode.CHARGING -> "Carregando"
                            IslandMode.IDLE -> "U.L.T.R.O.N."
                        }
                    }
                    subtitle = detail.ifBlank {
                        when (mode) {
                            IslandMode.LISTENING -> "Microfone nativo ativo"
                            IslandMode.PROCESSING -> "Analisando pedido"
                            IslandMode.SPEAKING -> "Toque para silenciar"
                            IslandMode.MEDIA -> mediaArtist.ifBlank { "Reprodução ativa" }
                            IslandMode.NOTIFICATION -> "Toque para abrir"
                            IslandMode.CHARGING -> "Energia conectada"
                            IslandMode.IDLE -> "Pronto"
                        }
                    }
                }
                instance?.morphToTarget(expanded = false)
            }
        }

        fun updateMediaState(title: String, artist: String, isPlaying: Boolean) {
            mediaTitle = title.trim()
            mediaArtist = artist.trim()
            mediaPlaying = isPlaying && mediaTitle.isNotBlank()
            mainHandler.post {
                if (currentMode == IslandMode.IDLE || currentMode == IslandMode.MEDIA) {
                    if (mediaPlaying) {
                        currentMode = IslandMode.MEDIA
                        headline = mediaTitle
                        subtitle = mediaArtist.ifBlank { "Tocando agora" }
                    } else {
                        currentMode = IslandMode.IDLE
                        headline = "U.L.T.R.O.N."
                        subtitle = "Pronto"
                    }
                    instance?.morphToTarget(expanded = false)
                }
            }
        }

        fun showNotificationAlert(sender: String, preview: String, appLabel: String = "") {
            if (!isRunning) return
            mainHandler.post {
                mainHandler.removeCallbacks(autoResetRunnable)
                currentMode = IslandMode.NOTIFICATION
                headline = if (appLabel.isNotBlank()) "$sender ($appLabel)" else sender
                subtitle = preview.trim().take(80)
                instance?.morphToTarget(expanded = false)
                mainHandler.postDelayed(autoResetRunnable, 6500L)
            }
        }

        fun showChargingPulse(batteryPercent: Int) {
            if (!isRunning) return
            mainHandler.post {
                mainHandler.removeCallbacks(autoResetRunnable)
                currentMode = IslandMode.CHARGING
                headline = "Carregando · $batteryPercent%"
                subtitle = "Energia conectada"
                instance?.morphToTarget(expanded = false)
                mainHandler.postDelayed(autoResetRunnable, 4200L)
            }
        }
    }

    private var windowManager: WindowManager? = null
    private var islandView: ExpressiveCutoutView? = null
    private var layoutParams: WindowManager.LayoutParams? = null
    private var waveAnimator: ValueAnimator? = null
    private var morphAnimator: ValueAnimator? = null
    private var powerReceiver: BroadcastReceiver? = null

    private var isExpanded = false
    private var currentWidthPx = 0
    private var currentHeightPx = 0
    private var currentCornerPx = 0f
    private var cutoutTopPx = 0

    override fun onCreate() {
        super.onCreate()
        instance = this
        if (!canDraw(this)) {
            stopSelf()
            return
        }
        registerPowerReceiver()
        setupOverlay()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (!canDraw(this)) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (islandView == null) {
            setupOverlay()
        }
        return START_STICKY
    }

    private fun registerPowerReceiver() {
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == Intent.ACTION_POWER_CONNECTED) {
                    val bm = getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
                    val pct = bm?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: 0
                    showChargingPulse(pct.coerceIn(0, 100))
                }
            }
        }
        powerReceiver = receiver
        try {
            ContextCompat.registerReceiver(
                this,
                receiver,
                IntentFilter(Intent.ACTION_POWER_CONNECTED),
                ContextCompat.RECEIVER_NOT_EXPORTED,
            )
        } catch (_: Exception) {
        }
    }

    private fun resolveCutoutTopPx(wm: WindowManager): Int {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                val cutout = wm.currentWindowMetrics.windowInsets.displayCutout
                val topRect: Rect? = cutout?.boundingRects?.minByOrNull { it.top }
                if (topRect != null && topRect.height() > 0) {
                    return (topRect.top - dpToPx(2f)).coerceAtLeast(dpToPx(4f))
                }
            } catch (_: Exception) {
            }
        }
        return dpToPx(8f)
    }

    private fun setupOverlay() {
        val wm = getSystemService(Context.WINDOW_SERVICE) as? WindowManager ?: run {
            stopSelf()
            return
        }
        windowManager = wm
        cutoutTopPx = resolveCutoutTopPx(wm)

        val (targetW, targetH, targetCorner) = targetDimensions(expanded = false)
        currentWidthPx = targetW
        currentHeightPx = targetH
        currentCornerPx = targetCorner

        val overlayType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val params = WindowManager.LayoutParams(
            targetW,
            targetH,
            overlayType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            x = 0
            y = cutoutTopPx
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }
        layoutParams = params

        val view = ExpressiveCutoutView(this)
        islandView = view

        try {
            wm.addView(view, params)
            isRunning = true
            startWaveLoop()
        } catch (_: Exception) {
            islandView = null
            isRunning = false
            stopSelf()
        }
    }

    private fun targetDimensions(expanded: Boolean): Triple<Int, Int, Float> {
        if (expanded) {
            val maxW = (resources.displayMetrics.widthPixels - dpToPx(24f)).coerceAtLeast(dpToPx(280f))
            val w = dpToPx(336f).coerceAtMost(maxW)
            return Triple(w, dpToPx(134f), dpToPx(30f).toFloat())
        }
        return when (currentMode) {
            IslandMode.IDLE -> Triple(dpToPx(124f), dpToPx(32f), dpToPx(18f).toFloat())
            IslandMode.LISTENING,
            IslandMode.PROCESSING,
            IslandMode.SPEAKING,
            IslandMode.MEDIA,
            IslandMode.CHARGING -> Triple(dpToPx(232f), dpToPx(40f), dpToPx(22f).toFloat())
            IslandMode.NOTIFICATION -> Triple(dpToPx(276f), dpToPx(46f), dpToPx(24f).toFloat())
        }
    }

    internal fun morphToTarget(expanded: Boolean) {
        val wm = windowManager ?: return
        val view = islandView ?: return
        val params = layoutParams ?: return
        isExpanded = expanded
        mainHandler.removeCallbacks(autoCollapseExpandedRunnable)
        if (expanded) {
            mainHandler.postDelayed(autoCollapseExpandedRunnable, 8500L)
        }

        val (targetW, targetH, targetCorner) = targetDimensions(expanded)
        val startW = currentWidthPx
        val startH = currentHeightPx
        val startCorner = currentCornerPx

        morphAnimator?.cancel()
        morphAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = if (expanded) 340L else 260L
            interpolator = if (expanded || currentMode != IslandMode.IDLE) {
                OvershootInterpolator(1.08f)
            } else {
                DecelerateInterpolator()
            }
            addUpdateListener { anim ->
                val f = anim.animatedValue as Float
                currentWidthPx = (startW + (targetW - startW) * f).toInt().coerceAtLeast(dpToPx(84f))
                currentHeightPx = (startH + (targetH - startH) * f).toInt().coerceAtLeast(dpToPx(28f))
                currentCornerPx = (startCorner + (targetCorner - startCorner) * f).coerceAtLeast(dpToPx(14f).toFloat())
                params.width = currentWidthPx
                params.height = currentHeightPx
                try {
                    wm.updateViewLayout(view, params)
                } catch (_: Exception) {
                }
                view.invalidate()
            }
            start()
        }
    }

    private fun startWaveLoop() {
        waveAnimator?.cancel()
        waveAnimator = ValueAnimator.ofFloat(0f, 1000f).apply {
            duration = 1_000_000L
            repeatCount = ValueAnimator.INFINITE
            interpolator = LinearInterpolator()
            addUpdateListener {
                islandView?.tick(it.animatedValue as Float)
            }
            start()
        }
    }

    private fun dispatchMediaKey(keyCode: Int) {
        val am = getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        val now = android.os.SystemClock.uptimeMillis()
        am.dispatchMediaKeyEvent(KeyEvent(now, now, KeyEvent.ACTION_DOWN, keyCode, 0))
        am.dispatchMediaKeyEvent(KeyEvent(now, now, KeyEvent.ACTION_UP, keyCode, 0))
    }

    private fun triggerVoiceAction() {
        val km = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
        val locked = isSessionLocked || km?.isDeviceLocked == true
        morphToTarget(expanded = false)
        MainActivity.notifyFloatingOrbTap(requiresUnlock = locked)
        launchMainActivity(voiceTrigger = true, requireUnlock = locked)
    }

    private fun triggerStopSpeaking() {
        UltronTtsHelper.stopAll()
        MainActivity.notifyStopSpeakingRequested()
        updateState("idle")
        morphToTarget(expanded = false)
    }

    private fun launchMainActivity(voiceTrigger: Boolean = false, requireUnlock: Boolean = false) {
        try {
            val openIntent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra(FloatingOrbService.EXTRA_ORB_VOICE_TRIGGER, voiceTrigger)
                putExtra(FloatingOrbService.EXTRA_ORB_REQUIRE_UNLOCK, requireUnlock)
            }
            startActivity(openIntent)
        } catch (_: Exception) {
        }
    }

    private fun dpToPx(dp: Float): Int =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, dp, resources.displayMetrics).toInt()

    private fun spToPx(sp: Float): Float =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, sp, resources.displayMetrics)

    override fun onDestroy() {
        isRunning = false
        mainHandler.removeCallbacks(autoResetRunnable)
        mainHandler.removeCallbacks(autoCollapseExpandedRunnable)
        waveAnimator?.cancel()
        waveAnimator = null
        morphAnimator?.cancel()
        morphAnimator = null
        powerReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: Exception) {
            }
        }
        powerReceiver = null
        val wm = windowManager
        val view = islandView
        if (wm != null && view != null) {
            try {
                wm.removeView(view)
            } catch (_: Exception) {
            }
        }
        islandView = null
        windowManager = null
        if (instance == this) instance = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private data class ActionButtonHit(val id: String, val label: String, val rect: RectF)

    private inner class ExpressiveCutoutView(context: Context) : View(context) {
        private var animTime = 0f
        private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop
        private var downX = 0f
        private var downY = 0f
        private var downTime = 0L
        private val actionHits = mutableListOf<ActionButtonHit>()

        private val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(246, 10, 10, 13)
            style = Paint.Style.FILL
        }
        private val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = dpToPx(1.1f).toFloat()
        }
        private val accentPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
        }
        private val pillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(26, 26, 32)
            style = Paint.Style.FILL
        }
        private val primaryPillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
        }
        private val titlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(245, 245, 247)
            textSize = spToPx(12.5f)
            typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        }
        private val subPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(160, 160, 170)
            textSize = spToPx(10.5f)
            typeface = Typeface.SANS_SERIF
        }
        private val buttonTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(245, 245, 247)
            textSize = spToPx(11.5f)
            textAlign = Paint.Align.CENTER
            typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        }
        private val bgRect = RectF()

        fun tick(t: Float) {
            animTime = t
            if (currentMode != IslandMode.IDLE || isExpanded) {
                invalidate()
            }
        }

        private fun activeTint(): Int = when (currentMode) {
            IslandMode.CHARGING -> Color.rgb(34, 197, 94)
            IslandMode.PROCESSING -> Color.rgb(245, 158, 11)
            IslandMode.MEDIA -> Color.rgb(56, 189, 248)
            else -> accentColorArgb
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val w = width.toFloat()
            val h = height.toFloat()
            if (w <= 0f || h <= 0f) return

            val pad = dpToPx(1.5f).toFloat()
            bgRect.set(pad, pad, w - pad, h - pad)
            val radius = currentCornerPx.coerceAtMost(h / 2f)

            val tint = activeTint()
            canvas.drawRoundRect(bgRect, radius, radius, bgPaint)
            borderPaint.color = if (currentMode == IslandMode.IDLE && !isExpanded) {
                Color.argb(90, 255, 255, 255)
            } else {
                Color.argb(150, Color.red(tint), Color.green(tint), Color.blue(tint))
            }
            canvas.drawRoundRect(bgRect, radius, radius, borderPaint)

            actionHits.clear()
            if (isExpanded) {
                drawExpandedCard(canvas, w, h, tint)
            } else if (currentMode == IslandMode.IDLE) {
                drawCompactIdle(canvas, w, h, tint)
            } else {
                drawActivePill(canvas, w, h, tint)
            }
        }

        private fun drawCompactIdle(canvas: Canvas, w: Float, h: Float, tint: Int) {
            val cy = h / 2f
            val dotR = dpToPx(3.6f).toFloat()
            accentPaint.color = tint
            canvas.drawCircle(dpToPx(14f).toFloat(), cy, dotR, accentPaint)

            // Indicador minimalista à direita da câmera frontal
            accentPaint.color = if (UltronAudioService.isListeningForReal()) {
                Color.rgb(34, 197, 94)
            } else {
                Color.rgb(115, 115, 128)
            }
            canvas.drawCircle(w - dpToPx(14f).toFloat(), cy, dpToPx(3f).toFloat(), accentPaint)
        }

        private fun drawActivePill(canvas: Canvas, w: Float, h: Float, tint: Int) {
            val cy = h / 2f
            val leftX = dpToPx(16f).toFloat()
            drawExpressiveGlyph(canvas, leftX, cy, tint)

            val textStart = dpToPx(32f).toFloat()
            val maxTextW = (w - textStart - dpToPx(38f)).coerceAtLeast(40f)
            titlePaint.textSize = spToPx(11.5f)
            val truncated = truncateText(headline, titlePaint, maxTextW)
            val textY = cy - (titlePaint.descent() + titlePaint.ascent()) / 2f
            canvas.drawText(truncated, textStart, textY, titlePaint)

            // Mini equalizador à direita
            drawMiniEqualizer(canvas, w - dpToPx(24f).toFloat(), cy, tint)
        }

        private fun drawExpandedCard(canvas: Canvas, w: Float, h: Float, tint: Int) {
            val headerY = dpToPx(26f).toFloat()
            drawExpressiveGlyph(canvas, dpToPx(24f).toFloat(), headerY, tint)

            val textX = dpToPx(44f).toFloat()
            val maxTextW = (w - textX - dpToPx(18f)).coerceAtLeast(80f)
            titlePaint.textSize = spToPx(13.5f)
            canvas.drawText(truncateText(headline, titlePaint, maxTextW), textX, headerY - dpToPx(1f), titlePaint)
            canvas.drawText(truncateText(subtitle, subPaint, maxTextW), textX, headerY + dpToPx(15f), subPaint)

            // Barra de botões expressivos Material 3 na base do card
            val btnTop = h - dpToPx(50f).toFloat()
            val btnBottom = h - dpToPx(14f).toFloat()
            val btnGap = dpToPx(8f).toFloat()
            val sidePad = dpToPx(14f).toFloat()

            val buttons: List<Pair<String, String>> = when (currentMode) {
                IslandMode.MEDIA -> listOf(
                    "prev" to "Anterior",
                    "play_pause" to "Play/Pause",
                    "next" to "Próxima",
                    "voice" to "Falar",
                )
                IslandMode.SPEAKING -> listOf(
                    "stop_speak" to "Silenciar",
                    "voice" to "Falar",
                    "open" to "Abrir",
                )
                else -> listOf(
                    "voice" to "Falar",
                    "play_pause" to "Mídia",
                    "open" to "Abrir App",
                )
            }

            val availW = w - sidePad * 2f - btnGap * (buttons.size - 1)
            val btnW = availW / buttons.size
            val btnCorner = (btnBottom - btnTop) / 2f

            buttons.forEachIndexed { idx, (id, label) ->
                val left = sidePad + idx * (btnW + btnGap)
                val rect = RectF(left, btnTop, left + btnW, btnBottom)
                actionHits.add(ActionButtonHit(id, label, rect))

                val isPrimary = id == "voice" || id == "stop_speak"
                if (isPrimary) {
                    primaryPillPaint.color = Color.argb(
                        220,
                        Color.red(tint),
                        Color.green(tint),
                        Color.blue(tint),
                    )
                    canvas.drawRoundRect(rect, btnCorner, btnCorner, primaryPillPaint)
                } else {
                    canvas.drawRoundRect(rect, btnCorner, btnCorner, pillPaint)
                }

                val ty = rect.centerY() - (buttonTextPaint.descent() + buttonTextPaint.ascent()) / 2f
                canvas.drawText(label, rect.centerX(), ty, buttonTextPaint)
            }
        }

        private fun drawExpressiveGlyph(canvas: Canvas, cx: Float, cy: Float, tint: Int) {
            val pulse = 1f + 0.14f * sin(animTime * 4.2f)
            accentPaint.color = Color.argb(65, Color.red(tint), Color.green(tint), Color.blue(tint))
            canvas.drawCircle(cx, cy, dpToPx(10f) * pulse, accentPaint)
            accentPaint.color = tint
            canvas.drawCircle(cx, cy, dpToPx(5.2f).toFloat(), accentPaint)
        }

        private fun drawMiniEqualizer(canvas: Canvas, startX: Float, cy: Float, tint: Int) {
            accentPaint.color = tint
            val barW = dpToPx(2.4f).toFloat()
            val gap = dpToPx(4.2f).toFloat()
            for (i in 0 until 4) {
                val wave = abs(sin(animTime * 5.2f + i * 0.9f))
                val barH = dpToPx(4f + 10f * wave).toFloat()
                val x = startX + i * gap
                canvas.drawRoundRect(
                    x,
                    cy - barH / 2f,
                    x + barW,
                    cy + barH / 2f,
                    barW / 2f,
                    barW / 2f,
                    accentPaint,
                )
            }
        }

        private fun truncateText(text: String, paint: Paint, maxWidth: Float): String {
            if (paint.measureText(text) <= maxWidth) return text
            var end = text.length
            while (end > 1 && paint.measureText(text.substring(0, end) + "...") > maxWidth) {
                end--
            }
            return if (end <= 1) text.take(1) else text.substring(0, end) + "..."
        }

        override fun onTouchEvent(event: MotionEvent): Boolean {
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = event.x
                    downY = event.y
                    downTime = System.currentTimeMillis()
                    return true
                }
                MotionEvent.ACTION_UP -> {
                    val dx = event.x - downX
                    val dy = event.y - downY
                    val elapsed = System.currentTimeMillis() - downTime

                    // Deslizar para cima recolhe ou dispensa alerta
                    if (dy < -touchSlop * 2f && abs(dy) > abs(dx)) {
                        performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
                        if (isExpanded) {
                            morphToTarget(expanded = false)
                        } else if (currentMode == IslandMode.NOTIFICATION || currentMode == IslandMode.CHARGING) {
                            mainHandler.removeCallbacks(autoResetRunnable)
                            mainHandler.post(autoResetRunnable)
                        }
                        return true
                    }

                    if (hypot(dx.toDouble(), dy.toDouble()) <= touchSlop * 2f) {
                        if (elapsed >= 550L) {
                            performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
                            morphToTarget(expanded = false)
                            launchMainActivity(voiceTrigger = false, requireUnlock = isSessionLocked)
                            return true
                        }
                        if (isExpanded) {
                            val hit = actionHits.firstOrNull { it.rect.contains(event.x, event.y) }
                            if (hit != null) {
                                performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
                                when (hit.id) {
                                    "voice" -> triggerVoiceAction()
                                    "stop_speak" -> triggerStopSpeaking()
                                    "prev" -> dispatchMediaKey(KeyEvent.KEYCODE_MEDIA_PREVIOUS)
                                    "play_pause" -> dispatchMediaKey(KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE)
                                    "next" -> dispatchMediaKey(KeyEvent.KEYCODE_MEDIA_NEXT)
                                    "open" -> {
                                        morphToTarget(expanded = false)
                                        launchMainActivity(voiceTrigger = false, requireUnlock = isSessionLocked)
                                    }
                                }
                                return true
                            }
                            morphToTarget(expanded = false)
                            return true
                        } else {
                            performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
                            morphToTarget(expanded = true)
                            return true
                        }
                    }
                    return true
                }
            }
            return super.onTouchEvent(event)
        }
    }
}
