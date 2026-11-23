package com.viniciusnpaula.ultron_mobile

import android.animation.ValueAnimator
import android.app.KeyguardManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.view.animation.LinearInterpolator
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.sin

/**
 * Estados visuais e operacionais do Orbe Flutuante do U.L.T.R.O.N.
 */
enum class OrbState(val id: String, val labelPt: String) {
    IDLE("ocioso", "OCIOSO"),
    LISTENING("ouvindo", "OUVINDO"),
    PROCESSING("processando", "PROC…"),
    SPEAKING("falando", "FALANDO");

    companion object {
        fun fromId(raw: String?): OrbState {
            return when (raw?.trim()?.lowercase()) {
                "listening", "ouvindo" -> LISTENING
                "processing", "processando" -> PROCESSING
                "speaking", "falando" -> SPEAKING
                else -> IDLE
            }
        }
    }
}

/**
 * Orbe Flutuante nativo (SYSTEM_ALERT_WINDOW / WindowManager).
 *
 * Exibe uma bolha tática arrastável sobre outros aplicativos com 4 estados
 * (ocioso, ouvindo, processando, falando). Respeita o AuthGate: quando a sessão
 * estiver `locked`, o toque no orbe solicita desbloqueio antes de executar
 * comandos ou ações sensíveis/críticas.
 */
class FloatingOrbService : Service() {

    companion object {
        const val ACTION_STOP_ORB = "com.viniciusnpaula.ultron_mobile.STOP_FLOATING_ORB"
        const val ACTION_UPDATE_STATE = "com.viniciusnpaula.ultron_mobile.UPDATE_FLOATING_ORB_STATE"
        const val EXTRA_ORB_STATE = "orb_state"
        const val EXTRA_ORB_VOICE_TRIGGER = "ultron_orb_voice_trigger"
        const val EXTRA_ORB_REQUIRE_UNLOCK = "ultron_orb_require_unlock"
        const val PREF_ORB_ENABLED = "floating_orb_enabled"

        private val mainHandler = Handler(Looper.getMainLooper())

        @Volatile
        var isRunning: Boolean = false
            private set

        @Volatile
        var currentState: OrbState = OrbState.IDLE
            private set

        /**
         * Fail-closed por padrão: inicia bloqueado até o AuthGate do Flutter
         * sincronizar uma sessão autenticada (basic, elevated ou sovereign).
         */
        @Volatile
        var isSessionLocked: Boolean = true
            private set

        @Volatile
        var sessionAccessLevel: String = "locked"
            private set

        @Volatile
        private var instance: FloatingOrbService? = null

        fun canDraw(context: Context): Boolean {
            return Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(context)
        }

        fun start(context: Context): Boolean {
            if (!canDraw(context)) return false
            return try {
                context.getSharedPreferences(UltronAudioService.PREFS_NAME, Context.MODE_PRIVATE)
                    .edit()
                    .putBoolean(PREF_ORB_ENABLED, true)
                    .apply()
                context.startService(Intent(context, FloatingOrbService::class.java))
                true
            } catch (_: Exception) {
                false
            }
        }

        fun stop(context: Context) {
            try {
                context.getSharedPreferences(UltronAudioService.PREFS_NAME, Context.MODE_PRIVATE)
                    .edit()
                    .putBoolean(PREF_ORB_ENABLED, false)
                    .apply()
                context.stopService(Intent(context, FloatingOrbService::class.java))
            } catch (_: Exception) {
            }
        }

        fun updateState(state: OrbState) {
            currentState = state
            mainHandler.post {
                instance?.orbView?.invalidate()
            }
        }

        fun updateStateById(stateId: String?) {
            updateState(OrbState.fromId(stateId))
        }

        fun updateAuthState(locked: Boolean, accessLevel: String) {
            isSessionLocked = locked
            sessionAccessLevel = if (locked) "locked" else accessLevel.lowercase()
            mainHandler.post {
                instance?.orbView?.invalidate()
            }
        }

        /**
         * Verifica se uma ação em segundo plano exige confirmação/desbloqueio pelo AuthGate.
         */
        fun requiresUnlockForBackgroundAction(context: Context, actionCmd: String): Boolean {
            val km = context.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
            val deviceLocked = km?.isDeviceLocked == true
            if (deviceLocked || isSessionLocked) return true
            val upper = actionCmd.trim().uppercase()
            if (upper.startsWith("PC_")) {
                return sessionAccessLevel != "sovereign"
            }
            val sensitiveCommands = setOf(
                "READ_MESSAGES",
                "REPLY_MESSAGE",
                "WHATSAPP",
                "SMS",
                "DIAL",
                "CANCEL_EVENT",
                "SKILL_CREATE",
                "SKILL_DELETE",
                "KILL_SWITCH",
                "CLEAR_HISTORY",
            )
            if (upper in sensitiveCommands) {
                return sessionAccessLevel == "basic" || sessionAccessLevel == "locked"
            }
            return false
        }
    }

    private var windowManager: WindowManager? = null
    private var orbView: FloatingOrbView? = null
    private var windowLayoutParams: WindowManager.LayoutParams? = null
    private var animator: ValueAnimator? = null
    @Volatile
    private var bgVoiceBusy: Boolean = false

    override fun onCreate() {
        super.onCreate()
        instance = this
        if (!canDraw(this)) {
            stopSelf()
            return
        }
        setupOverlayWindow()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP_ORB -> {
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_UPDATE_STATE -> {
                val raw = intent.getStringExtra(EXTRA_ORB_STATE)
                updateStateById(raw)
                return START_STICKY
            }
        }
        if (!canDraw(this)) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (orbView == null) {
            setupOverlayWindow()
        }
        return START_STICKY
    }

    private fun setupOverlayWindow() {
        val wm = getSystemService(Context.WINDOW_SERVICE) as? WindowManager ?: run {
            stopSelf()
            return
        }
        windowManager = wm
        val dm = resources.displayMetrics
        val sizePx = dpToPx(68f)
        val marginPx = dpToPx(10f)

        val overlayType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val params = WindowManager.LayoutParams(
            sizePx,
            sizePx,
            overlayType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = (dm.widthPixels - sizePx - marginPx).coerceAtLeast(0)
            y = (dm.heightPixels / 3).coerceAtLeast(marginPx)
        }
        windowLayoutParams = params

        val view = FloatingOrbView(this)
        orbView = view

        try {
            wm.addView(view, params)
            isRunning = true
            startAnimationLoop()
        } catch (_: Exception) {
            orbView = null
            isRunning = false
            stopSelf()
        }
    }

    private fun startAnimationLoop() {
        animator?.cancel()
        animator = ValueAnimator.ofFloat(0f, 1000f).apply {
            duration = 1_000_000L
            repeatCount = ValueAnimator.INFINITE
            interpolator = LinearInterpolator()
            addUpdateListener {
                orbView?.tick((it.animatedValue as Float))
            }
            start()
        }
    }

    private fun handleOrbTap() {
        val km = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
        val deviceLocked = km?.isDeviceLocked == true
        val locked = isSessionLocked || deviceLocked

        // Regra AuthGate: se a sessão estiver locked, solicita desbloqueio primeiro.
        if (locked) {
            MainActivity.notifyFloatingOrbTap(requiresUnlock = true)
            launchMainActivity(voiceTrigger = true, requireUnlock = true)
            return
        }

        if (MainActivity.isActivityResumed) {
            MainActivity.notifyFloatingOrbTap(requiresUnlock = false)
            return
        }

        if (currentState == OrbState.SPEAKING) {
            UltronTtsHelper.stopAll()
            updateState(OrbState.IDLE)
            return
        }

        val cfg = BackgroundVoiceConfigStore.load(this)
        if (!bgVoiceBusy && currentState == OrbState.IDLE && cfg.hasStt) {
            bgVoiceBusy = true
            Thread({
                try {
                    BackgroundVoiceResponder.runBackgroundTurn(
                        context = this@FloatingOrbService,
                        onStatusUpdate = { status ->
                            val nextState = when {
                                status.contains("Ouvindo", ignoreCase = true) -> OrbState.LISTENING
                                status.contains("Transcrevendo", ignoreCase = true) ||
                                    status.contains("Consultando", ignoreCase = true) -> OrbState.PROCESSING
                                status.contains("Respondendo", ignoreCase = true) -> OrbState.SPEAKING
                                else -> currentState
                            }
                            updateState(nextState)
                        },
                        onReplyNotification = { _, _ -> },
                        onRequireUnlock = {
                            MainActivity.notifyFloatingOrbTap(requiresUnlock = true)
                            launchMainActivity(voiceTrigger = true, requireUnlock = true)
                        },
                    )
                } finally {
                    bgVoiceBusy = false
                    updateState(OrbState.IDLE)
                }
            }, "UltronFloatingOrbVoiceThread").start()
        } else {
            MainActivity.notifyFloatingOrbTap(requiresUnlock = false)
            launchMainActivity(voiceTrigger = true, requireUnlock = false)
        }
    }

    private fun launchMainActivity(voiceTrigger: Boolean, requireUnlock: Boolean) {
        try {
            val openIntent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra(EXTRA_ORB_VOICE_TRIGGER, voiceTrigger)
                putExtra(EXTRA_ORB_REQUIRE_UNLOCK, requireUnlock)
            }
            startActivity(openIntent)
        } catch (_: Exception) {
        }
    }

    private fun dpToPx(dp: Float): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            dp,
            resources.displayMetrics,
        ).toInt()
    }

    override fun onDestroy() {
        isRunning = false
        animator?.cancel()
        animator = null
        val wm = windowManager
        val view = orbView
        if (wm != null && view != null) {
            try {
                wm.removeView(view)
            } catch (_: Exception) {
            }
        }
        orbView = null
        windowManager = null
        if (instance == this) instance = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private inner class FloatingOrbView(context: Context) : View(context) {
        private var animTime = 0f
        private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop
        private var downRawX = 0f
        private var downRawY = 0f
        private var startX = 0
        private var startY = 0
        private var isDragging = false
        private var downTimestampMs = 0L

        private val auraPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val ringPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeCap = Paint.Cap.ROUND
        }
        private val corePaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val badgeBgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(225, 16, 2, 6)
            style = Paint.Style.FILL
        }
        private val badgeBorderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = dpToPx(1f).toFloat()
        }
        private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            textAlign = Paint.Align.CENTER
            textSize = TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_SP,
                8.2f,
                resources.displayMetrics,
            )
            isFakeBoldText = true
        }
        private val arcRect = RectF()
        private val badgeRect = RectF()

        fun tick(t: Float) {
            animTime = t
            invalidate()
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val w = width.toFloat()
            val h = height.toFloat()
            if (w <= 0f || h <= 0f) return

            val cx = w / 2f
            val cy = h * 0.44f
            val baseR = minOf(w, h) * 0.36f
            val state = currentState
            val locked = isSessionLocked

            val primaryColor = when {
                locked -> Color.rgb(180, 35, 50)
                state == OrbState.LISTENING -> Color.rgb(255, 59, 71)
                state == OrbState.PROCESSING -> Color.rgb(255, 179, 0)
                state == OrbState.SPEAKING -> Color.rgb(255, 107, 115)
                else -> Color.rgb(229, 9, 20)
            }

            val speed = when (state) {
                OrbState.LISTENING -> 3.4f
                OrbState.PROCESSING -> 5.0f
                OrbState.SPEAKING -> 4.0f
                OrbState.IDLE -> 1.2f
            }
            val pulse = 1f + 0.08f * sin(animTime * speed)

            // 1. Aura radial
            val auraR = baseR * 1.28f * pulse
            auraPaint.shader = RadialGradient(
                cx,
                cy,
                auraR.coerceAtLeast(1f),
                intArrayOf(
                    Color.argb(145, Color.red(primaryColor), Color.green(primaryColor), Color.blue(primaryColor)),
                    Color.argb(40, Color.red(primaryColor), Color.green(primaryColor), Color.blue(primaryColor)),
                    Color.TRANSPARENT,
                ),
                floatArrayOf(0f, 0.65f, 1f),
                Shader.TileMode.CLAMP,
            )
            canvas.drawCircle(cx, cy, auraR, auraPaint)

            // 2. Arcos táticos giratórios
            val ringR = baseR * 1.02f
            arcRect.set(cx - ringR, cy - ringR, cx + ringR, cy + ringR)
            ringPaint.color = primaryColor
            ringPaint.strokeWidth = dpToPx(1.8f).toFloat()
            val baseAngle = (animTime * 42f * speed) % 360f
            for (i in 0 until 4) {
                canvas.drawArc(arcRect, baseAngle + i * 90f + 12f, 66f, false, ringPaint)
            }

            // 3. Núcleo esférico central
            val sphereR = baseR * 0.66f * pulse
            corePaint.shader = RadialGradient(
                cx - sphereR * 0.2f,
                cy - sphereR * 0.2f,
                sphereR.coerceAtLeast(1f),
                intArrayOf(
                    Color.rgb(255, 225, 225),
                    primaryColor,
                    Color.rgb(32, 2, 7),
                ),
                floatArrayOf(0f, 0.55f, 1f),
                Shader.TileMode.CLAMP,
            )
            canvas.drawCircle(cx, cy, sphereR, corePaint)

            // 4. Ondas extras para OUVINDO / FALANDO
            if (state == OrbState.LISTENING || state == OrbState.SPEAKING) {
                val wavePhase = (animTime * 1.8f) % 1f
                val waveR = sphereR + (ringR - sphereR) * wavePhase
                ringPaint.color = Color.argb(
                    ((1f - wavePhase) * 200).toInt().coerceIn(0, 255),
                    255,
                    160,
                    160,
                )
                ringPaint.strokeWidth = dpToPx(1.4f).toFloat()
                canvas.drawCircle(cx, cy, waveR, ringPaint)
            }

            // 5. Pílula de estado / cadeado AuthGate na base
            val badgeW = w * 0.92f
            val badgeH = dpToPx(14f).toFloat()
            val badgeTop = h - badgeH - dpToPx(1f)
            badgeRect.set(cx - badgeW / 2f, badgeTop, cx + badgeW / 2f, badgeTop + badgeH)
            val corner = badgeH / 2f
            canvas.drawRoundRect(badgeRect, corner, corner, badgeBgPaint)
            badgeBorderPaint.color = primaryColor
            canvas.drawRoundRect(badgeRect, corner, corner, badgeBorderPaint)

            val label = if (locked && state == OrbState.IDLE) "🔒 BLOQ" else state.labelPt
            val textY = badgeRect.centerY() - (textPaint.descent() + textPaint.ascent()) / 2f
            canvas.drawText(label, cx, textY, textPaint)
        }

        override fun onTouchEvent(event: MotionEvent): Boolean {
            val params = windowLayoutParams ?: return false
            val wm = windowManager ?: return false

            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downRawX = event.rawX
                    downRawY = event.rawY
                    startX = params.x
                    startY = params.y
                    isDragging = false
                    downTimestampMs = System.currentTimeMillis()
                    return true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - downRawX
                    val dy = event.rawY - downRawY
                    if (!isDragging && hypot(dx.toDouble(), dy.toDouble()) > touchSlop) {
                        isDragging = true
                    }
                    if (isDragging) {
                        params.x = (startX + dx.toInt()).coerceAtLeast(0)
                        params.y = (startY + dy.toInt()).coerceAtLeast(0)
                        try {
                            wm.updateViewLayout(this, params)
                        } catch (_: Exception) {
                        }
                    }
                    return true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    if (isDragging) {
                        snapToHorizontalEdge(params, wm)
                    } else {
                        val elapsed = System.currentTimeMillis() - downTimestampMs
                        if (elapsed >= 650L) {
                            launchMainActivity(
                                voiceTrigger = false,
                                requireUnlock = isSessionLocked,
                            )
                        } else {
                            handleOrbTap()
                        }
                    }
                    isDragging = false
                    return true
                }
            }
            return super.onTouchEvent(event)
        }

        private fun snapToHorizontalEdge(params: WindowManager.LayoutParams, wm: WindowManager) {
            val dm = resources.displayMetrics
            val margin = dpToPx(8f)
            val midX = params.x + width / 2
            params.x = if (midX < dm.widthPixels / 2) {
                margin
            } else {
                (dm.widthPixels - width - margin).coerceAtLeast(margin)
            }
            try {
                wm.updateViewLayout(this, params)
            } catch (_: Exception) {
            }
        }
    }
}
