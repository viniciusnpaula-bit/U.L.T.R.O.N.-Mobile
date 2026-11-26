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
import android.graphics.DashPathEffect
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
import android.view.WindowInsets
import android.view.WindowManager
import android.view.animation.DecelerateInterpolator
import android.view.animation.LinearInterpolator
import android.view.animation.OvershootInterpolator
import androidx.core.content.ContextCompat
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.roundToInt
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

enum class IslandOrientation(val id: String) {
    AUTO("auto"),
    HORIZONTAL("horizontal"),
    VERTICAL("vertical");

    companion object {
        fun fromId(raw: String?): IslandOrientation = when (raw?.trim()?.lowercase()) {
            "horizontal", "deitada", "topo" -> HORIZONTAL
            "vertical", "em_pe", "empe", "lateral" -> VERTICAL
            else -> AUTO
        }
    }
}

data class IslandPlacement(
    val customPosition: Boolean = false,
    val posX: Float = 0.5f,
    val posY: Float = 0.04f,
    val orientation: IslandOrientation = IslandOrientation.AUTO,
    val scale: Float = 1.0f,
) {
    fun isEffectivelyVertical(): Boolean = when (orientation) {
        IslandOrientation.VERTICAL -> true
        IslandOrientation.HORIZONTAL -> false
        IslandOrientation.AUTO -> customPosition && (posX <= 0.16f || posX >= 0.84f)
    }

    fun zoneLabel(): String {
        if (!customPosition) return "Topo (Abaixo da barra)"
        val vertical = isEffectivelyVertical()
        return when {
            posX <= 0.16f && vertical -> "Esquerda (Em pé)"
            posX >= 0.84f && vertical -> "Direita (Em pé)"
            posY <= 0.12f && abs(posX - 0.5f) <= 0.14f && !vertical -> "Topo (Abaixo da barra)"
            vertical -> "Livre (Em pé)"
            else -> "Livre (Horizontal)"
        }
    }

    fun toMap(enabled: Boolean): Map<String, Any> = mapOf(
        "enabled" to enabled,
        "customPosition" to customPosition,
        "posX" to posX.toDouble(),
        "posY" to posY.toDouble(),
        "orientation" to orientation.id,
        "scale" to scale.toDouble(),
        "zoneLabel" to zoneLabel(),
    )
}

/**
 * Ilha Dinâmica Expressiva nativa inspirada no EvanKoe/expressive-cutout:
 * - Suporta ancoragem padrão no recorte da câmera frontal (`DisplayCutout`),
 *   posicionamento livre em qualquer lugar da tela e modo vertical ("em pé")
 *   nas bordas esquerda/direita ou livre.
 * - Modo interativo "Configurar ilha dinâmica" com tela escurecida, guias de
 *   alinhamento, arrastar livre, presets rápidos e controle de tamanho.
 */
class DynamicIslandService : Service() {

    companion object {
        const val PREF_ISLAND_ENABLED = "dynamic_island_enabled"
        const val PREF_ISLAND_CUSTOM = "dynamic_island_custom_pos"
        const val PREF_ISLAND_POS_X = "dynamic_island_pos_x"
        const val PREF_ISLAND_POS_Y = "dynamic_island_pos_y"
        const val PREF_ISLAND_ORIENTATION = "dynamic_island_orientation"
        const val PREF_ISLAND_SCALE = "dynamic_island_scale"

        const val ACTION_STOP = "com.viniciusnpaula.ultron_mobile.STOP_DYNAMIC_ISLAND"
        const val ACTION_CONFIGURE = "com.viniciusnpaula.ultron_mobile.CONFIGURE_DYNAMIC_ISLAND"

        private val mainHandler = Handler(Looper.getMainLooper())

        @Volatile
        var isRunning: Boolean = false
            private set

        @Volatile
        var isConfiguring: Boolean = false
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

        fun loadPlacement(context: Context): IslandPlacement {
            val prefs = context.getSharedPreferences(UltronAudioService.PREFS_NAME, Context.MODE_PRIVATE)
            return IslandPlacement(
                customPosition = prefs.getBoolean(PREF_ISLAND_CUSTOM, false),
                posX = prefs.getFloat(PREF_ISLAND_POS_X, 0.5f).coerceIn(0.02f, 0.98f),
                posY = prefs.getFloat(PREF_ISLAND_POS_Y, 0.04f).coerceIn(0.01f, 0.96f),
                orientation = IslandOrientation.fromId(prefs.getString(PREF_ISLAND_ORIENTATION, "auto")),
                scale = prefs.getFloat(PREF_ISLAND_SCALE, 1.0f).coerceIn(0.85f, 1.25f),
            )
        }

        fun savePlacement(context: Context, placement: IslandPlacement) {
            context.getSharedPreferences(UltronAudioService.PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(PREF_ISLAND_CUSTOM, placement.customPosition)
                .putFloat(PREF_ISLAND_POS_X, placement.posX.coerceIn(0.02f, 0.98f))
                .putFloat(PREF_ISLAND_POS_Y, placement.posY.coerceIn(0.01f, 0.96f))
                .putString(PREF_ISLAND_ORIENTATION, placement.orientation.id)
                .putFloat(PREF_ISLAND_SCALE, placement.scale.coerceIn(0.85f, 1.25f))
                .apply()
        }

        fun resetPlacement(context: Context): IslandPlacement {
            val def = IslandPlacement()
            savePlacement(context, def)
            mainHandler.post {
                instance?.applyPlacement(def, animate = true)
            }
            return def
        }

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

        fun openConfigurator(context: Context): Boolean {
            if (!canDraw(context)) return false
            return try {
                context.getSharedPreferences(UltronAudioService.PREFS_NAME, Context.MODE_PRIVATE)
                    .edit()
                    .putBoolean(PREF_ISLAND_ENABLED, true)
                    .apply()
                val intent = Intent(context, DynamicIslandService::class.java).apply {
                    action = ACTION_CONFIGURE
                }
                context.startService(intent)
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
            mainHandler.post {
                instance?.islandView?.invalidate()
                instance?.configOverlayView?.invalidate()
            }
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
    private var configOverlayView: IslandCalibrationOverlayView? = null
    private var layoutParams: WindowManager.LayoutParams? = null
    private var waveAnimator: ValueAnimator? = null
    private var morphAnimator: ValueAnimator? = null
    private var powerReceiver: BroadcastReceiver? = null

    private var placement: IslandPlacement = IslandPlacement()
    private var isExpanded = false
    private var currentWidthPx = 0
    private var currentHeightPx = 0
    private var currentCornerPx = 0f
    private var statusBarBandPx = 0
    private var safeTopPx = 0
    private var safeBottomPx = 0

    override fun onCreate() {
        super.onCreate()
        instance = this
        if (!canDraw(this)) {
            stopSelf()
            return
        }
        placement = loadPlacement(this)
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
            placement = loadPlacement(this)
            setupOverlay()
        }
        if (intent?.action == ACTION_CONFIGURE) {
            mainHandler.post { enterConfigMode() }
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

    private fun resolveScreenSize(): Pair<Int, Int> {
        val wm = windowManager
        if (wm != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                val b = wm.currentWindowMetrics.bounds
                if (b.width() > 0 && b.height() > 0) {
                    return b.width() to b.height()
                }
            } catch (_: Exception) {
            }
        }
        val dm = resources.displayMetrics
        return dm.widthPixels to dm.heightPixels
    }

    /**
     * Calcula a faixa superior protegida (barra de status + câmera frontal + hora + bateria)
     * e a margem inferior (barra de navegação/gestos), garantindo que a Ilha Dinâmica
     * NUNCA entre em conflito ou sobreponha elementos do sistema.
     */
    private fun refreshSafeVerticalBounds(wm: WindowManager? = windowManager) {
        var topSystemPx = 0
        var bottomSystemPx = 0

        val statusResId = resources.getIdentifier("status_bar_height", "dimen", "android")
        if (statusResId > 0) {
            topSystemPx = maxOf(topSystemPx, resources.getDimensionPixelSize(statusResId))
        }
        val navResId = resources.getIdentifier("navigation_bar_height", "dimen", "android")
        if (navResId > 0) {
            bottomSystemPx = maxOf(bottomSystemPx, resources.getDimensionPixelSize(navResId))
        }

        if (wm != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                val insets = wm.currentWindowMetrics.windowInsets
                val statusTop = insets.getInsetsIgnoringVisibility(WindowInsets.Type.statusBars()).top
                val cutoutTop = insets.getInsetsIgnoringVisibility(WindowInsets.Type.displayCutout()).top
                val cutoutBottom = insets.displayCutout?.boundingRects
                    ?.filter { it.top <= statusTop + dpToPx(24f) }
                    ?.maxOfOrNull { it.bottom }
                    ?: 0
                val navBottom = insets.getInsetsIgnoringVisibility(WindowInsets.Type.navigationBars()).bottom
                topSystemPx = maxOf(topSystemPx, statusTop, cutoutTop, cutoutBottom)
                bottomSystemPx = maxOf(bottomSystemPx, navBottom)
            } catch (_: Exception) {
            }
        }

        statusBarBandPx = topSystemPx.coerceAtLeast(dpToPx(34f))
        safeTopPx = statusBarBandPx + dpToPx(8f)
        safeBottomPx = bottomSystemPx.coerceAtLeast(dpToPx(16f)) + dpToPx(8f)
    }

    private fun overlayWindowType(): Int = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
    } else {
        @Suppress("DEPRECATION")
        WindowManager.LayoutParams.TYPE_PHONE
    }

    private fun computeOriginForSize(w: Int, h: Int, targetPlacement: IslandPlacement = placement): Pair<Int, Int> {
        refreshSafeVerticalBounds()
        val (screenW, screenH) = resolveScreenSize()
        val marginX = dpToPx(8f)
        val minTop = safeTopPx
        val maxLeft = (screenW - w - marginX).coerceAtLeast(marginX)
        val maxTop = (screenH - h - safeBottomPx).coerceAtLeast(minTop)

        if (!targetPlacement.customPosition) {
            val cx = ((screenW - w) / 2f).roundToInt().coerceIn(marginX, maxLeft)
            return cx to minTop
        }
        val desiredCx = (targetPlacement.posX * screenW).roundToInt()
        val desiredCy = (targetPlacement.posY * screenH).roundToInt()
        val left = (desiredCx - w / 2).coerceIn(marginX, maxLeft)
        val top = (desiredCy - h / 2).coerceIn(minTop, maxTop)
        return left to top
    }

    private fun setupOverlay() {
        val wm = getSystemService(Context.WINDOW_SERVICE) as? WindowManager ?: run {
            stopSelf()
            return
        }
        windowManager = wm
        refreshSafeVerticalBounds(wm)

        val (targetW, targetH, targetCorner) = targetDimensions(expanded = false)
        currentWidthPx = targetW
        currentHeightPx = targetH
        currentCornerPx = targetCorner

        val (originX, originY) = computeOriginForSize(targetW, targetH)
        val params = WindowManager.LayoutParams(
            targetW,
            targetH,
            overlayWindowType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = originX
            y = originY
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

    private fun targetDimensions(
        expanded: Boolean,
        targetPlacement: IslandPlacement = placement,
    ): Triple<Int, Int, Float> {
        val scale = targetPlacement.scale.coerceIn(0.85f, 1.25f)
        val (screenW, _) = resolveScreenSize()
        if (expanded) {
            val maxW = (screenW - dpToPx(24f)).coerceAtLeast(dpToPx(276f))
            val w = dpToPx(336f).coerceAtMost(maxW)
            return Triple(w, dpToPx(134f), dpToPx(30f).toFloat())
        }
        if (targetPlacement.isEffectivelyVertical()) {
            return when (currentMode) {
                IslandMode.IDLE -> Triple(
                    dpToPx(34f * scale),
                    dpToPx(116f * scale),
                    dpToPx(18f * scale).toFloat(),
                )
                IslandMode.NOTIFICATION -> Triple(
                    dpToPx(46f * scale),
                    dpToPx(176f * scale),
                    dpToPx(23f * scale).toFloat(),
                )
                else -> Triple(
                    dpToPx(42f * scale),
                    dpToPx(156f * scale),
                    dpToPx(21f * scale).toFloat(),
                )
            }
        }
        return when (currentMode) {
            IslandMode.IDLE -> Triple(
                dpToPx(124f * scale),
                dpToPx(32f * scale),
                dpToPx(18f * scale).toFloat(),
            )
            IslandMode.LISTENING,
            IslandMode.PROCESSING,
            IslandMode.SPEAKING,
            IslandMode.MEDIA,
            IslandMode.CHARGING -> Triple(
                dpToPx(232f * scale).coerceAtMost(screenW - dpToPx(24f)),
                dpToPx(40f * scale),
                dpToPx(22f * scale).toFloat(),
            )
            IslandMode.NOTIFICATION -> Triple(
                dpToPx(276f * scale).coerceAtMost(screenW - dpToPx(20f)),
                dpToPx(46f * scale),
                dpToPx(24f * scale).toFloat(),
            )
        }
    }

    internal fun applyPlacement(newPlacement: IslandPlacement, animate: Boolean = true) {
        placement = newPlacement
        if (!animate) {
            val wm = windowManager ?: return
            val view = islandView ?: return
            val params = layoutParams ?: return
            val (w, h, corner) = targetDimensions(expanded = false, targetPlacement = newPlacement)
            val (nx, ny) = computeOriginForSize(w, h, newPlacement)
            currentWidthPx = w
            currentHeightPx = h
            currentCornerPx = corner
            params.width = w
            params.height = h
            params.x = nx
            params.y = ny
            try {
                wm.updateViewLayout(view, params)
            } catch (_: Exception) {
            }
            view.invalidate()
        } else {
            morphToTarget(expanded = false)
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
        val (targetX, targetY) = computeOriginForSize(targetW, targetH)
        val startW = currentWidthPx
        val startH = currentHeightPx
        val startCorner = currentCornerPx
        val startX = params.x
        val startY = params.y

        morphAnimator?.cancel()
        morphAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = if (expanded) 340L else 260L
            interpolator = if (expanded || currentMode != IslandMode.IDLE) {
                OvershootInterpolator(1.06f)
            } else {
                DecelerateInterpolator()
            }
            addUpdateListener { anim ->
                val f = anim.animatedValue as Float
                currentWidthPx = (startW + (targetW - startW) * f).toInt().coerceAtLeast(dpToPx(30f))
                currentHeightPx = (startH + (targetH - startH) * f).toInt().coerceAtLeast(dpToPx(28f))
                currentCornerPx = (startCorner + (targetCorner - startCorner) * f).coerceAtLeast(dpToPx(14f).toFloat())
                params.width = currentWidthPx
                params.height = currentHeightPx
                params.x = (startX + (targetX - startX) * f).roundToInt()
                params.y = (startY + (targetY - startY) * f).roundToInt()
                try {
                    wm.updateViewLayout(view, params)
                } catch (_: Exception) {
                }
                view.invalidate()
            }
            start()
        }
    }

    private fun enterConfigMode() {
        val wm = windowManager ?: return
        if (configOverlayView != null) return
        isConfiguring = true
        islandView?.visibility = View.INVISIBLE

        val cfgView = IslandCalibrationOverlayView(
            context = this,
            initialPlacement = placement,
            onSave = { chosen ->
                savePlacement(this, chosen)
                exitConfigMode()
                applyPlacement(chosen, animate = true)
            },
            onCancel = {
                exitConfigMode()
            },
        )
        configOverlayView = cfgView

        val cfgParams = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            overlayWindowType(),
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }
        try {
            wm.addView(cfgView, cfgParams)
        } catch (_: Exception) {
            configOverlayView = null
            isConfiguring = false
            islandView?.visibility = View.VISIBLE
        }
    }

    private fun exitConfigMode() {
        val wm = windowManager
        val cfg = configOverlayView
        configOverlayView = null
        isConfiguring = false
        if (wm != null && cfg != null) {
            try {
                wm.removeView(cfg)
            } catch (_: Exception) {
            }
        }
        islandView?.visibility = View.VISIBLE
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

    private fun isLightColor(color: Int): Boolean {
        val r = Color.red(color) / 255f
        val g = Color.green(color) / 255f
        val b = Color.blue(color) / 255f
        return (0.2126f * r + 0.7152f * g + 0.0722f * b) > 0.52f
    }

    override fun onDestroy() {
        exitConfigMode()
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

    /**
     * Tela escurecida interativa de calibração da Ilha Dinâmica:
     * permite arrastar livremente, encaixar no topo (câmera) ou em pé nas laterais
     * esquerda/direita, escolher orientação (Auto / Horizontal / Em pé) e tamanho.
     */
    private inner class IslandCalibrationOverlayView(
        context: Context,
        initialPlacement: IslandPlacement,
        private val onSave: (IslandPlacement) -> Unit,
        private val onCancel: () -> Unit,
    ) : View(context) {

        private var draft: IslandPlacement = initialPlacement
        private var draggingIsland = false
        private var dragOffsetX = 0f
        private var dragOffsetY = 0f
        private var lastSnapZone = ""
        private val hitButtons = mutableListOf<ActionButtonHit>()
        private val islandPreviewRect = RectF()
        private val dockRect = RectF()

        private val scrimPaint = Paint().apply {
            color = Color.argb(208, 6, 6, 10)
            style = Paint.Style.FILL
        }
        private val guidePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(58, 255, 255, 255)
            style = Paint.Style.STROKE
            strokeWidth = dpToPx(1f).toFloat()
            pathEffect = DashPathEffect(floatArrayOf(dpToPx(6f).toFloat(), dpToPx(6f).toFloat()), 0f)
        }
        private val zoneBoxPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = dpToPx(1.2f).toFloat()
        }
        private val zoneFillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
        }
        private val previewBgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(248, 12, 12, 16)
            style = Paint.Style.FILL
        }
        private val previewBorderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = dpToPx(1.8f).toFloat()
        }
        private val accentPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
        }
        private val dockBgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(244, 17, 17, 22)
            style = Paint.Style.FILL
        }
        private val dockBorderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(42, 42, 52)
            style = Paint.Style.STROKE
            strokeWidth = dpToPx(1f).toFloat()
        }
        private val chipBgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(28, 28, 36)
            style = Paint.Style.FILL
        }
        private val titlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(242, 242, 246)
            textSize = spToPx(14f)
            typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        }
        private val subPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(160, 160, 174)
            textSize = spToPx(11.5f)
            typeface = Typeface.SANS_SERIF
        }
        private val zoneTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(150, 220, 220, 232)
            textSize = spToPx(10.5f)
            textAlign = Paint.Align.CENTER
            typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        }
        private val chipTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(238, 238, 242)
            textSize = spToPx(11.5f)
            textAlign = Paint.Align.CENTER
            typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        }

        init {
            isFocusable = true
            isFocusableInTouchMode = true
        }

        private fun previewDimensions(): Pair<Float, Float> {
            val scale = draft.scale.coerceIn(0.85f, 1.25f)
            return if (draft.isEffectivelyVertical()) {
                dpToPx(40f * scale).toFloat() to dpToPx(136f * scale).toFloat()
            } else {
                dpToPx(168f * scale).toFloat() to dpToPx(36f * scale).toFloat()
            }
        }

        private fun computePreviewRect(w: Float, h: Float) {
            refreshSafeVerticalBounds()
            val (pw, ph) = previewDimensions()
            val padX = dpToPx(8f).toFloat()
            val minCy = safeTopPx + ph / 2f
            val maxCy = (h - safeBottomPx - ph / 2f).coerceAtLeast(minCy)
            val cx = if (!draft.customPosition) {
                w / 2f
            } else {
                (draft.posX * w).coerceIn(padX + pw / 2f, (w - padX - pw / 2f).coerceAtLeast(padX + pw / 2f))
            }
            val cy = if (!draft.customPosition) {
                minCy
            } else {
                (draft.posY * h).coerceIn(minCy, maxCy)
            }
            islandPreviewRect.set(cx - pw / 2f, cy - ph / 2f, cx + pw / 2f, cy + ph / 2f)
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val w = width.toFloat()
            val h = height.toFloat()
            if (w <= 0f || h <= 0f) return
            refreshSafeVerticalBounds()

            // 1. Fundo escurecido
            canvas.drawRect(0f, 0f, w, h, scrimPaint)

            // 1B. Faixa superior protegida (barra de status, câmera, hora, notificações e bateria)
            val protectedRect = RectF(0f, 0f, w, statusBarBandPx.toFloat())
            zoneFillPaint.color = Color.argb(120, 42, 16, 20)
            canvas.drawRect(protectedRect, zoneFillPaint)
            zoneBoxPaint.color = Color.argb(135, 241, 13, 40)
            canvas.drawLine(0f, statusBarBandPx.toFloat(), w, statusBarBandPx.toFloat(), zoneBoxPaint)
            zoneTextPaint.color = Color.argb(190, 245, 200, 206)
            val protTy = (statusBarBandPx * 0.62f) - (zoneTextPaint.descent() + zoneTextPaint.ascent()) / 2f
            canvas.drawText("ÁREA PROTEGIDA · CÂMERA · HORA · BATERIA", w / 2f, protTy, zoneTextPaint)

            // 2. Guias de alinhamento (sempre abaixo da barra de status)
            canvas.drawLine(w / 2f, safeTopPx.toFloat(), w / 2f, h - dpToPx(240f).toFloat(), guidePaint)
            canvas.drawLine(dpToPx(18f).toFloat(), h * 0.44f, w - dpToPx(18f).toFloat(), h * 0.44f, guidePaint)

            val tint = accentColorArgb
            val activeZone = draft.zoneLabel()

            // 3. Zonas magnéticas sugeridas (sempre abaixo de safeTopPx)
            val topZone = RectF(
                w / 2f - dpToPx(96f),
                safeTopPx.toFloat(),
                w / 2f + dpToPx(96f),
                safeTopPx + dpToPx(46f).toFloat(),
            )
            val sideTop = maxOf(h * 0.24f, safeTopPx + dpToPx(20f).toFloat())
            val leftZone = RectF(dpToPx(6f).toFloat(), sideTop, dpToPx(60f).toFloat(), h * 0.58f)
            val rightZone = RectF(w - dpToPx(60f).toFloat(), sideTop, w - dpToPx(6f).toFloat(), h * 0.58f)

            drawDropZone(canvas, topZone, "TOPO", activeZone == "Topo (Abaixo da barra)", tint)
            drawDropZone(canvas, leftZone, "ESQ", activeZone == "Esquerda (Em pé)", tint)
            drawDropZone(canvas, rightZone, "DIR", activeZone == "Direita (Em pé)", tint)

            // 4. Preview interativo da Ilha Dinâmica arrastável
            computePreviewRect(w, h)
            val corner = (minOf(islandPreviewRect.width(), islandPreviewRect.height()) / 2f)
            canvas.drawRoundRect(islandPreviewRect, corner, corner, previewBgPaint)
            previewBorderPaint.color = tint
            canvas.drawRoundRect(islandPreviewRect, corner, corner, previewBorderPaint)

            accentPaint.color = tint
            if (draft.isEffectivelyVertical()) {
                val cx = islandPreviewRect.centerX()
                canvas.drawCircle(cx, islandPreviewRect.top + dpToPx(16f), dpToPx(4.5f).toFloat(), accentPaint)
                accentPaint.color = Color.argb(130, 255, 255, 255)
                val barW = dpToPx(12f).toFloat()
                val barH = dpToPx(2.5f).toFloat()
                for (i in -1..1) {
                    val y = islandPreviewRect.centerY() + i * dpToPx(8f)
                    canvas.drawRoundRect(cx - barW / 2f, y - barH / 2f, cx + barW / 2f, y + barH / 2f, barH / 2f, barH / 2f, accentPaint)
                }
                accentPaint.color = Color.rgb(34, 197, 94)
                canvas.drawCircle(cx, islandPreviewRect.bottom - dpToPx(16f), dpToPx(3.6f).toFloat(), accentPaint)
            } else {
                val cy = islandPreviewRect.centerY()
                canvas.drawCircle(islandPreviewRect.left + dpToPx(16f), cy, dpToPx(4.5f).toFloat(), accentPaint)
                zoneTextPaint.color = Color.rgb(236, 236, 242)
                val ty = cy - (zoneTextPaint.descent() + zoneTextPaint.ascent()) / 2f
                canvas.drawText("ARRASTE AQUI", islandPreviewRect.centerX(), ty, zoneTextPaint)
                accentPaint.color = Color.rgb(34, 197, 94)
                canvas.drawCircle(islandPreviewRect.right - dpToPx(16f), cy, dpToPx(3.6f).toFloat(), accentPaint)
            }

            // 5. Painel inferior de controles
            hitButtons.clear()
            val dockMargin = dpToPx(14f).toFloat()
            val dockHeight = dpToPx(216f).toFloat()
            val bottomInset = dpToPx(28f).toFloat()
            dockRect.set(dockMargin, h - dockHeight - bottomInset, w - dockMargin, h - bottomInset)
            val dockRadius = dpToPx(22f).toFloat()
            canvas.drawRoundRect(dockRect, dockRadius, dockRadius, dockBgPaint)
            canvas.drawRoundRect(dockRect, dockRadius, dockRadius, dockBorderPaint)

            val pad = dpToPx(16f).toFloat()
            var cursorY = dockRect.top + dpToPx(24f)
            canvas.drawText("Configurar Ilha Dinâmica", dockRect.left + pad, cursorY, titlePaint)
            cursorY += dpToPx(18f)
            canvas.drawText(
                "Arraste para qualquer ponto · ${draft.zoneLabel()}",
                dockRect.left + pad,
                cursorY,
                subPaint,
            )

            // Linha 1: Orientação (Auto / Horizontal / Em pé)
            cursorY += dpToPx(14f)
            drawChipRow(
                canvas = canvas,
                top = cursorY,
                height = dpToPx(34f).toFloat(),
                left = dockRect.left + pad,
                right = dockRect.right - pad,
                items = listOf(
                    Triple("ori_auto", "Auto", draft.orientation == IslandOrientation.AUTO),
                    Triple("ori_h", "Horizontal", draft.orientation == IslandOrientation.HORIZONTAL),
                    Triple("ori_v", "Em pé", draft.orientation == IslandOrientation.VERTICAL),
                ),
                tint = tint,
            )

            // Linha 2: Presets rápidos + Tamanho
            cursorY += dpToPx(42f)
            drawChipRow(
                canvas = canvas,
                top = cursorY,
                height = dpToPx(34f).toFloat(),
                left = dockRect.left + pad,
                right = dockRect.right - pad,
                items = listOf(
                    Triple("pos_top", "Topo", !draft.customPosition),
                    Triple("pos_left", "Esq. em pé", draft.customPosition && draft.posX <= 0.16f),
                    Triple("pos_right", "Dir. em pé", draft.customPosition && draft.posX >= 0.84f),
                    Triple("size_cycle", sizeLabel(draft.scale), false),
                ),
                tint = tint,
            )

            // Linha 3: Cancelar / Salvar posição
            cursorY += dpToPx(44f)
            drawChipRow(
                canvas = canvas,
                top = cursorY,
                height = dpToPx(40f).toFloat(),
                left = dockRect.left + pad,
                right = dockRect.right - pad,
                items = listOf(
                    Triple("cancel", "Cancelar", false),
                    Triple("save", "Salvar posição", true),
                ),
                tint = tint,
            )
        }

        private fun sizeLabel(scale: Float): String = when {
            scale < 0.93f -> "Tam: P"
            scale > 1.09f -> "Tam: G"
            else -> "Tam: M"
        }

        private fun drawDropZone(canvas: Canvas, rect: RectF, label: String, active: Boolean, tint: Int) {
            val r = dpToPx(16f).toFloat()
            zoneFillPaint.color = if (active) {
                Color.argb(45, Color.red(tint), Color.green(tint), Color.blue(tint))
            } else {
                Color.argb(22, 255, 255, 255)
            }
            zoneBoxPaint.color = if (active) tint else Color.argb(72, 255, 255, 255)
            canvas.drawRoundRect(rect, r, r, zoneFillPaint)
            canvas.drawRoundRect(rect, r, r, zoneBoxPaint)
            zoneTextPaint.color = if (active) tint else Color.argb(140, 220, 220, 232)
            val ty = rect.centerY() - (zoneTextPaint.descent() + zoneTextPaint.ascent()) / 2f
            canvas.drawText(label, rect.centerX(), ty, zoneTextPaint)
        }

        private fun drawChipRow(
            canvas: Canvas,
            top: Float,
            height: Float,
            left: Float,
            right: Float,
            items: List<Triple<String, String, Boolean>>,
            tint: Int,
        ) {
            val gap = dpToPx(8f).toFloat()
            val btnW = (right - left - gap * (items.size - 1)) / items.size
            val r = height / 2f
            items.forEachIndexed { idx, (id, label, selected) ->
                val x0 = left + idx * (btnW + gap)
                val rect = RectF(x0, top, x0 + btnW, top + height)
                hitButtons.add(ActionButtonHit(id, label, rect))
                if (selected) {
                    accentPaint.color = if (id == "save") {
                        tint
                    } else {
                        Color.argb(70, Color.red(tint), Color.green(tint), Color.blue(tint))
                    }
                    canvas.drawRoundRect(rect, r, r, accentPaint)
                    previewBorderPaint.color = tint
                    val oldW = previewBorderPaint.strokeWidth
                    previewBorderPaint.strokeWidth = dpToPx(1.1f).toFloat()
                    canvas.drawRoundRect(rect, r, r, previewBorderPaint)
                    previewBorderPaint.strokeWidth = oldW
                } else {
                    canvas.drawRoundRect(rect, r, r, chipBgPaint)
                }
                chipTextPaint.color = if (id == "save" && isLightColor(tint)) {
                    Color.rgb(12, 12, 16)
                } else {
                    Color.rgb(242, 242, 246)
                }
                val ty = rect.centerY() - (chipTextPaint.descent() + chipTextPaint.ascent()) / 2f
                canvas.drawText(label, rect.centerX(), ty, chipTextPaint)
            }
        }

        override fun onTouchEvent(event: MotionEvent): Boolean {
            val w = width.toFloat().coerceAtLeast(1f)
            val h = height.toFloat().coerceAtLeast(1f)
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    val hit = hitButtons.firstOrNull { it.rect.contains(event.x, event.y) }
                    if (hit != null) {
                        performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
                        handleDockAction(hit.id)
                        return true
                    }
                    if (!dockRect.contains(event.x, event.y)) {
                        draggingIsland = true
                        if (islandPreviewRect.contains(event.x, event.y)) {
                            dragOffsetX = event.x - islandPreviewRect.centerX()
                            dragOffsetY = event.y - islandPreviewRect.centerY()
                        } else {
                            dragOffsetX = 0f
                            dragOffsetY = 0f
                            updateDraftPosition(event.x, event.y, w, h)
                        }
                        return true
                    }
                    return true
                }
                MotionEvent.ACTION_MOVE -> {
                    if (draggingIsland) {
                        val targetX = event.x - dragOffsetX
                        val targetY = (event.y - dragOffsetY).coerceAtMost(dockRect.top - dpToPx(24f))
                        updateDraftPosition(targetX, targetY, w, h)
                        return true
                    }
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    draggingIsland = false
                    return true
                }
            }
            return super.onTouchEvent(event)
        }

        private fun updateDraftPosition(px: Float, py: Float, w: Float, h: Float) {
            refreshSafeVerticalBounds()
            val (_, ph) = previewDimensions()
            val minCyPx = safeTopPx + ph / 2f
            val maxCyPx = (dockRect.top - dpToPx(16f) - ph / 2f).coerceAtLeast(minCyPx)
            val clampedPy = py.coerceIn(minCyPx, maxCyPx)

            var nx = (px / w).coerceIn(0.03f, 0.97f)
            var ny = (clampedPy / h).coerceIn((minCyPx / h).coerceIn(0.05f, 0.25f), 0.78f)
            var custom = true

            // Encaixe magnético suave nas zonas principais (sempre abaixo da barra de status)
            val nearSafeTop = clampedPy <= (minCyPx + dpToPx(24f))
            if (nearSafeTop && abs(nx - 0.5f) <= 0.13f && draft.orientation != IslandOrientation.VERTICAL) {
                nx = 0.5f
                ny = (minCyPx / h).coerceIn(0.05f, 0.25f)
                custom = false
            } else if (nx <= 0.11f) {
                nx = 0.06f
            } else if (nx >= 0.89f) {
                nx = 0.94f
            }

            draft = draft.copy(customPosition = custom, posX = nx, posY = ny)
            val zone = draft.zoneLabel()
            if (zone != lastSnapZone) {
                lastSnapZone = zone
                performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
            }
            invalidate()
        }

        private fun handleDockAction(id: String) {
            when (id) {
                "ori_auto" -> draft = draft.copy(orientation = IslandOrientation.AUTO)
                "ori_h" -> draft = draft.copy(orientation = IslandOrientation.HORIZONTAL)
                "ori_v" -> draft = draft.copy(
                    customPosition = true,
                    orientation = IslandOrientation.VERTICAL,
                    posY = if (!draft.customPosition) 0.34f else draft.posY,
                )
                "pos_top" -> draft = draft.copy(
                    customPosition = false,
                    posX = 0.5f,
                    posY = 0.04f,
                    orientation = IslandOrientation.AUTO,
                )
                "pos_left" -> draft = draft.copy(
                    customPosition = true,
                    posX = 0.06f,
                    posY = if (draft.posY < 0.15f) 0.36f else draft.posY,
                    orientation = IslandOrientation.AUTO,
                )
                "pos_right" -> draft = draft.copy(
                    customPosition = true,
                    posX = 0.94f,
                    posY = if (draft.posY < 0.15f) 0.36f else draft.posY,
                    orientation = IslandOrientation.AUTO,
                )
                "size_cycle" -> {
                    val nextScale = when {
                        draft.scale < 0.93f -> 1.0f
                        draft.scale > 1.09f -> 0.86f
                        else -> 1.16f
                    }
                    draft = draft.copy(scale = nextScale)
                }
                "save" -> {
                    onSave(draft)
                    return
                }
                "cancel" -> {
                    onCancel()
                    return
                }
            }
            invalidate()
        }
    }

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
            val radius = currentCornerPx.coerceAtMost(minOf(w, h) / 2f)

            val tint = activeTint()
            canvas.drawRoundRect(bgRect, radius, radius, bgPaint)
            borderPaint.color = if (currentMode == IslandMode.IDLE && !isExpanded) {
                Color.argb(90, 255, 255, 255)
            } else {
                Color.argb(155, Color.red(tint), Color.green(tint), Color.blue(tint))
            }
            canvas.drawRoundRect(bgRect, radius, radius, borderPaint)

            actionHits.clear()
            if (isExpanded) {
                drawExpandedCard(canvas, w, h, tint)
            } else if (placement.isEffectivelyVertical()) {
                if (currentMode == IslandMode.IDLE) {
                    drawCompactIdleVertical(canvas, w, h, tint)
                } else {
                    drawActivePillVertical(canvas, w, h, tint)
                }
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

            accentPaint.color = if (UltronAudioService.isListeningForReal()) {
                Color.rgb(34, 197, 94)
            } else {
                Color.rgb(115, 115, 128)
            }
            canvas.drawCircle(w - dpToPx(14f).toFloat(), cy, dpToPx(3f).toFloat(), accentPaint)
        }

        private fun drawCompactIdleVertical(canvas: Canvas, w: Float, h: Float, tint: Int) {
            val cx = w / 2f
            accentPaint.color = tint
            canvas.drawCircle(cx, dpToPx(16f).toFloat(), dpToPx(4f).toFloat(), accentPaint)

            // Barra central sutil da pílula em pé
            accentPaint.color = Color.argb(65, 255, 255, 255)
            val spineW = dpToPx(2.4f).toFloat()
            canvas.drawRoundRect(
                cx - spineW / 2f,
                h * 0.34f,
                cx + spineW / 2f,
                h * 0.66f,
                spineW / 2f,
                spineW / 2f,
                accentPaint,
            )

            accentPaint.color = if (UltronAudioService.isListeningForReal()) {
                Color.rgb(34, 197, 94)
            } else {
                Color.rgb(115, 115, 128)
            }
            canvas.drawCircle(cx, h - dpToPx(16f).toFloat(), dpToPx(3.2f).toFloat(), accentPaint)
        }

        private fun drawActivePillVertical(canvas: Canvas, w: Float, h: Float, tint: Int) {
            val cx = w / 2f
            drawExpressiveGlyph(canvas, cx, dpToPx(22f).toFloat(), tint)

            // Equalizador horizontal empilhado verticalmente no meio da pílula em pé
            accentPaint.color = tint
            val barH = dpToPx(2.6f).toFloat()
            val gap = dpToPx(6.5f).toFloat()
            val startY = h * 0.5f - gap * 1.5f
            for (i in 0 until 4) {
                val wave = abs(sin(animTime * 5.2f + i * 0.9f))
                val barW = dpToPx(8f + 14f * wave).toFloat().coerceAtMost(w - dpToPx(12f))
                val y = startY + i * gap
                canvas.drawRoundRect(
                    cx - barW / 2f,
                    y - barH / 2f,
                    cx + barW / 2f,
                    y + barH / 2f,
                    barH / 2f,
                    barH / 2f,
                    accentPaint,
                )
            }

            // Indicador de toque na base
            accentPaint.color = Color.argb(120, 235, 235, 245)
            canvas.drawCircle(cx, h - dpToPx(16f).toFloat(), dpToPx(3f).toFloat(), accentPaint)
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
                        225,
                        Color.red(tint),
                        Color.green(tint),
                        Color.blue(tint),
                    )
                    canvas.drawRoundRect(rect, btnCorner, btnCorner, primaryPillPaint)
                    buttonTextPaint.color = if (isLightColor(tint)) {
                        Color.rgb(12, 12, 16)
                    } else {
                        Color.rgb(245, 245, 247)
                    }
                } else {
                    canvas.drawRoundRect(rect, btnCorner, btnCorner, pillPaint)
                    buttonTextPaint.color = Color.rgb(245, 245, 247)
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

                    // Deslizar para cima (ou para a borda lateral no modo em pé) recolhe
                    val swipeDismiss = (dy < -touchSlop * 2f && abs(dy) > abs(dx)) ||
                        (placement.isEffectivelyVertical() && abs(dx) > touchSlop * 2f && abs(dx) > abs(dy))
                    if (swipeDismiss) {
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
                            enterConfigMode()
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
