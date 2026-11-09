package ir.vernaservice.vpn

import android.app.ActivityManager
import android.content.Context

/**
 * Whether the plugin's core services are really alive, asked of Android.
 *
 * The plugin's own state is not that answer. It reports "stopped" whenever its
 * control connection to the core drops -- including the late disconnects of a
 * core that is still shutting down, and connection errors of one that is
 * still running. Trusting it left a core running with nobody holding it: the
 * next start reused the live service, the new core failed to bind
 * 127.0.0.1:10086, and Android destroyed the service with only the failed
 * core in hand. The old one kept both ports until the process died, so every
 * start after that failed in a second. Measured on the J7 on 2026-11-09; the
 * user-visible fix was clearing the app's data, which ends the process.
 *
 * Android still lists a caller's own services here; the deprecation only took
 * away other apps'. By name, because the plugin's classes extend types this
 * module cannot compile against.
 */
object CoreServices {
    private const val VPN = "dev.amirzr.singbox.service.SingboxVPNService"
    private const val PROXY = "dev.amirzr.singbox.service.SingboxProxyService"

    @Suppress("DEPRECATION")
    fun running(context: Context, vpnOnly: Boolean = false): Boolean {
        val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
            ?: return false
        return manager.getRunningServices(Int.MAX_VALUE).any {
            val name = it.service.className
            name == VPN || (!vpnOnly && name == PROXY)
        }
    }
}
