package ir.vernaservice.vpn

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import io.flutter.plugin.common.MethodChannel

/**
 * What the tile and the Flutter side share, within one process.
 *
 * A static rather than Intent extras: MainActivity is exported, so an extra
 * saying "connect" could be sent by any app on the phone. This cannot.
 */
object TileBridge {
    const val CHANNEL = "ir.vernaservice.vpn/tile"
    private const val PREFS = "verna_tile"
    private const val KEY_STOPPED_AWAY = "stopped_while_away"

    /** Null while no Flutter engine is alive: the VPN service outlives it. */
    var channel: MethodChannel? = null

    /** "on", "busy" or "off" as Dart last said, or null without an engine. */
    var uiState: String? = null
    var busyLabel: String? = null

    /** The tile while the panel is showing it. */
    var tile: VernaTileService? = null

    private var connectRequested = false

    fun requestConnect() {
        connectRequested = true
    }

    fun hasConnectRequest(): Boolean = connectRequested

    /** Whether a tap is waiting. Reads once, so a request starts one connect. */
    fun takeConnectRequest(): Boolean {
        val requested = connectRequested
        connectRequested = false
        return requested
    }

    fun publish(state: String?, label: String?) {
        uiState = state
        busyLabel = label
        tile?.refresh()
    }

    fun engineGone(gone: MethodChannel) {
        if (channel !== gone) return
        channel = null
        uiState = null
        busyLabel = null
        tile?.refresh()
    }

    /**
     * Written down rather than held in memory: with no engine running, the
     * process can end along with the service it just stopped.
     */
    fun noteStoppedAway(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY_STOPPED_AWAY, true).apply()
    }

    fun takeStoppedAway(context: Context): Boolean {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val stopped = prefs.getBoolean(KEY_STOPPED_AWAY, false)
        if (stopped) prefs.edit().remove(KEY_STOPPED_AWAY).apply()
        return stopped
    }
}

/**
 * The on/off button in the phone's Quick Settings panel, next to Wi-Fi.
 *
 * Off, a tap opens the app and starts the same connect as its big button. That
 * cannot happen from here: choosing a server, asking for VPN consent and
 * verifying the tunnel all live in Dart, and a search can end in a failure
 * that needs a screen to explain it.
 *
 * On, a tap stops the tunnel without opening anything. Through Dart when an
 * engine is alive, so the session is closed as the user's own; through the
 * plugin's stop action when the service has outlived the engine.
 */
class VernaTileService : TileService() {

    private val main = Handler(Looper.getMainLooper())

    override fun onStartListening() {
        super.onStartListening()
        TileBridge.tile = this
        refresh()
    }

    override fun onStopListening() {
        if (TileBridge.tile === this) TileBridge.tile = null
        super.onStopListening()
    }

    override fun onClick() {
        super.onClick()
        if (isLocked) unlockAndRun { toggle() } else toggle()
    }

    private fun toggle() {
        if (isOn()) stopTunnel() else openAndConnect()
    }

    private fun isOn(): Boolean = when (TileBridge.uiState) {
        "on", "busy" -> true
        "off" -> false
        // No engine to ask. The VPN service's own process is the answer: not
        // "any VPN is up", which would show this tile on for another app's
        // tunnel, and not the proxy-mode service the device test runs.
        else -> CoreServices.running(this, vpnOnly = true)
    }

    fun refresh() {
        val tile = qsTile ?: return
        val on = isOn()
        tile.state = if (on) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        // Left empty otherwise: Android writes its own On/Off, in the phone's
        // language.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = if (TileBridge.uiState == "busy") TileBridge.busyLabel else null
        }
        tile.updateTile()
    }

    private fun openAndConnect() {
        TileBridge.requestConnect()
        val intent = Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            // The Intent overload throws from Android 14 on.
            val pending = PendingIntent.getActivity(
                this,
                0,
                intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            startActivityAndCollapse(pending)
        } else {
            @Suppress("DEPRECATION", "StartActivityAndCollapseDeprecated")
            startActivityAndCollapse(intent)
        }
    }

    private fun stopTunnel() {
        val channel = TileBridge.channel
        if (channel == null) {
            stopWithoutEngine()
            return
        }
        channel.invokeMethod(
            "disconnectRequested",
            null,
            object : MethodChannel.Result {
                override fun success(result: Any?) = Unit
                override fun error(code: String, message: String?, details: Any?) =
                    stopWithoutEngine()
                override fun notImplemented() = stopWithoutEngine()
            },
        )
    }

    /**
     * The plugin's own stop action, the one its notification button sends.
     * Noted first, so the next launch closes the session as the user's and not
     * as the app having been killed.
     */
    private fun stopWithoutEngine() {
        TileBridge.noteStoppedAway(this)
        sendBroadcast(Intent(ACTION_STOP).setPackage(packageName))
        // No engine will publish the change, and the service takes a moment.
        main.postDelayed({ refresh() }, REFRESH_AFTER_STOP_MS)
    }

    private companion object {
        const val ACTION_STOP = "dev.amirzr.singbox.STOP"
        const val REFRESH_AFTER_STOP_MS = 1500L
    }
}
