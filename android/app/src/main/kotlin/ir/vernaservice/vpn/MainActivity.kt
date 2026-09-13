package ir.vernaservice.vpn

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Two platform capabilities Dart cannot reach on its own.
 *
 * This class once carried three workarounds for the previous core's bugs, all
 * of which left with that core. What is here now is not worked around anything:
 * it is the parts of Android that have no Flutter equivalent.
 *
 * **The notification permission.** From Android 13 a foreground service's
 * notification is dropped unless the app holds POST_NOTIFICATIONS, and nothing
 * grants it on the app's behalf. Measured on a Galaxy A54 running Android 16
 * with the permission revoked to imitate a fresh install: the tunnel came up
 * and logcat repeated, once a second,
 *
 *     NotificationService: Suppressing notification from package
 *     ir.vernaservice.vpn by user request
 *
 * The user gets no country, no throughput and no stop button -- the app looks
 * broken while working perfectly. Only an Activity can ask.
 *
 * **The network transport.** A tunnel is built on whatever network the phone
 * had when it started, and walking out of Wi-Fi onto mobile data does not tear
 * it down politely: the service keeps running and nothing works.
 * `connectivity_plus` does this, and pulls in a build that wants AGP 8.12.1
 * against this project's AGP 9 -- the whole build stopped resolving. Thirty
 * lines of ConnectivityManager costs nothing and conflicts with nothing.
 */
class MainActivity : FlutterActivity() {

    private companion object {
        const val METHODS = "ir.vernaservice.vpn/permissions"
        const val NETWORK_EVENTS = "ir.vernaservice.vpn/network"
        const val REQUEST_NOTIFICATIONS = 4711
    }

    private var networkEvents: EventChannel.EventSink? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private val main = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHODS)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasNotificationPermission" -> result.success(hasNotifications())
                    "hasInternet" -> result.success(hasInternet())
                    "requestNotificationPermission" -> {
                        requestNotifications()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, NETWORK_EVENTS)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    networkEvents = sink
                    startWatchingNetwork()
                }

                override fun onCancel(arguments: Any?) {
                    stopWatchingNetwork()
                    networkEvents = null
                }
            })
    }

    // ── notifications ────────────────────────────────────────────────────────

    /** True below Android 13, where the permission is implicit. */
    private fun hasNotifications(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun requestNotifications() {
        if (hasNotifications()) return
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQUEST_NOTIFICATIONS,
        )
    }

    // ── network transport ────────────────────────────────────────────────────

    /**
     * Whether the phone has any network that can reach the internet at all.
     *
     * Any network, not the active one: while the app's own tunnel is up, the
     * active network *is* the tunnel. And not a validated one: Google's
     * connectivity check is blocked in Iran, so Android marks working networks
     * "no internet" there -- trusting that flag would refuse to connect on the
     * very networks this app exists for. This only answers "is Wi-Fi or mobile
     * data there", which is the question a two-minute search was answering the
     * slow way.
     */
    @Suppress("DEPRECATION") // allNetworks: fine for a one-off read.
    private fun hasInternet(): Boolean {
        val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return true
        return manager.allNetworks.any { network ->
            val capabilities = manager.getNetworkCapabilities(network) ?: return@any false
            capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                !capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
        }
    }

    private fun startWatchingNetwork() {
        if (networkCallback != null) return
        val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return

        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = report(network)
            override fun onLost(network: Network) = send("none")
            override fun onCapabilitiesChanged(
                network: Network,
                capabilities: NetworkCapabilities,
            ) = send(describe(capabilities))

            private fun report(network: Network) {
                send(describe(manager.getNetworkCapabilities(network)))
            }
        }

        // NOT_VPN, deliberately. The app's own tunnel is a network as far as
        // Android is concerned, so without this the callback fires for the
        // tunnel coming up and reports it as the transport changing -- the
        // tunnel would tear itself down every time it connected.
        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .removeCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
            .build()

        try {
            manager.registerNetworkCallback(request, callback)
            networkCallback = callback
        } catch (_: SecurityException) {
            // Some OEM builds refuse the callback. The tunnel still works; it
            // just will not notice a handover.
        }
    }

    private fun stopWatchingNetwork() {
        val callback = networkCallback ?: return
        networkCallback = null
        val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        try {
            manager?.unregisterNetworkCallback(callback)
        } catch (_: IllegalArgumentException) {
            // Already gone.
        }
    }

    /**
     * The transport as one word, which is all Dart needs.
     *
     * The tunnel does not care whether it is on Wi-Fi or mobile; it cares that
     * the answer changed since it was built.
     */
    private fun describe(capabilities: NetworkCapabilities?): String = when {
        capabilities == null -> "none"
        capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN) -> "vpn"
        capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
        capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
        capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
        else -> "other"
    }

    private fun send(transport: String) {
        main.post { networkEvents?.success(transport) }
    }

    override fun onDestroy() {
        stopWatchingNetwork()
        super.onDestroy()
    }
}
