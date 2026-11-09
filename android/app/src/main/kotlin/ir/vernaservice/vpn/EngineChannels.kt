package ir.vernaservice.vpn

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.widget.Toast
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.lang.ref.WeakReference

/**
 * The platform capabilities Dart cannot reach on its own, on one engine.
 *
 * These lived in MainActivity, which tied them to a screen. The Quick Settings
 * tile now runs the app's Dart with no screen at all (see [TileEngine]), and
 * that engine needs the same answers -- the network under the tunnel, whether
 * a core service is alive -- or it connects half-blind. So they take the
 * application context, and only the one thing that really needs an Activity,
 * asking for the notification permission, looks for one.
 *
 * **The notification permission.** From Android 13 a foreground service's
 * notification is dropped unless the app holds POST_NOTIFICATIONS, and nothing
 * grants it on the app's behalf. Measured on a Galaxy A54 running Android 16
 * with the permission revoked: the tunnel came up and logcat repeated
 * "Suppressing notification from package ir.vernaservice.vpn by user request"
 * once a second. Only an Activity can ask.
 *
 * **The network transport.** A tunnel is built on whatever network the phone
 * had when it started, and walking out of Wi-Fi onto mobile data does not tear
 * it down politely. `connectivity_plus` pulled in a build that wanted AGP
 * 8.12.1 against this project's AGP 9; thirty lines of ConnectivityManager
 * cost nothing and conflict with nothing.
 */
class EngineChannels(context: Context) {

    companion object {
        const val METHODS = "ir.vernaservice.vpn/permissions"
        const val NETWORK_EVENTS = "ir.vernaservice.vpn/network"
        const val REQUEST_NOTIFICATIONS = 4711

        /** The screen, while there is one. Only the permission request needs it. */
        var activity: WeakReference<Activity>? = null
    }

    private val context = context.applicationContext
    private var tile: MethodChannel? = null
    private var networkEvents: EventChannel.EventSink? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private val main = Handler(Looper.getMainLooper())

    fun register(engine: FlutterEngine) {
        val messenger = engine.dartExecutor.binaryMessenger

        MethodChannel(messenger, METHODS).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasNotificationPermission" -> result.success(hasNotifications())
                "hasInternet" -> result.success(hasInternet())
                "transport" -> result.success(underlyingTransport())
                "vpnActive" -> result.success(vpnActive())
                "vpnPrepared" -> result.success(vpnPrepared())
                "coreRunning" -> result.success(
                    CoreServices.running(context, call.argument<Boolean>("vpnOnly") == true),
                )
                "mobileOperator" -> result.success(mobileOperator())
                "requestNotificationPermission" -> {
                    requestNotifications()
                    result.success(null)
                }
                // Off the main thread: drawing a hundred icons takes a moment.
                "launchableApps" -> Thread {
                    val apps = try {
                        launchableApps()
                    } catch (_: Exception) {
                        emptyList()
                    }
                    main.post { result.success(apps) }
                }.start()
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, NETWORK_EVENTS).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    networkEvents = sink
                    startWatchingNetwork()
                }

                override fun onCancel(arguments: Any?) {
                    stopWatchingNetwork()
                    networkEvents = null
                }
            },
        )

        val tileChannel = MethodChannel(messenger, TileBridge.CHANNEL)
        tileChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "publish" -> {
                    TileBridge.publish(call.argument("state"), call.argument("busyLabel"))
                    result.success(null)
                }
                "takeConnectRequest" -> result.success(TileBridge.takeConnectRequest())
                "takeStoppedAway" -> result.success(TileBridge.takeStoppedAway(context))
                "toast" -> {
                    val text = call.argument<String>("text")
                    if (!text.isNullOrBlank()) Toast.makeText(context, text, Toast.LENGTH_LONG).show()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        tile = tileChannel
        TileBridge.channel = tileChannel
    }

    /** The engine is going away: let go of what points at it. */
    fun dispose() {
        stopWatchingNetwork()
        networkEvents = null
        tile?.let { TileBridge.engineGone(it) }
        tile = null
    }

    // ── VPN ──────────────────────────────────────────────────────────────────

    /** Whether any VPN network is up, this app's or another's. */
    @Suppress("DEPRECATION")
    private fun vpnActive(): Boolean {
        val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return false
        return manager.allNetworks.any {
            manager.getNetworkCapabilities(it)
                ?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true
        }
    }

    /**
     * Whether Android would let this app start a VPN without asking. Only
     * asks: with no consent intent acted on, `prepare` changes nothing, so it
     * cannot take the VPN from another app. Needed because the plugin's own
     * permission call answers "no" whenever there is no Activity -- which is
     * every connect the tile starts with the app closed.
     */
    private fun vpnPrepared(): Boolean = try {
        VpnService.prepare(context) == null
    } catch (_: Exception) {
        false
    }

    // ── split tunneling ──────────────────────────────────────────────────────

    /** Apps with a launcher entry, this one left out, each with a small icon. */
    private fun launchableApps(): List<Map<String, Any?>> {
        val pm = context.packageManager
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return pm.queryIntentActivities(launcher, 0)
            .map { it.activityInfo.applicationInfo }
            .distinctBy { it.packageName }
            .filter { it.packageName != context.packageName }
            .map { info ->
                mapOf(
                    "package" to info.packageName,
                    "label" to pm.getApplicationLabel(info).toString(),
                    "icon" to iconPng(pm.getApplicationIcon(info)),
                )
            }
    }

    private fun iconPng(drawable: Drawable): ByteArray? = try {
        val size = 72
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, size, size)
        drawable.draw(canvas)
        ByteArrayOutputStream().use { out ->
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
            bitmap.recycle()
            out.toByteArray()
        }
    } catch (_: Exception) {
        null
    }

    // ── notifications ────────────────────────────────────────────────────────

    /** True below Android 13, where the permission is implicit. */
    private fun hasNotifications(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun requestNotifications() {
        if (hasNotifications()) return
        val screen = activity?.get() ?: return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        screen.requestPermissions(
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
     * very networks this app exists for.
     */
    @Suppress("DEPRECATION") // allNetworks: fine for a one-off read.
    private fun hasInternet(): Boolean {
        val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return true
        return manager.allNetworks.any { network ->
            val capabilities = manager.getNetworkCapabilities(network) ?: return@any false
            capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                !capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
        }
    }

    /**
     * The network the phone's traffic really rides on: "wifi", "cellular" or
     * "unknown" -- never "vpn". Wi-Fi wins when both are up, as Android's own
     * routing does.
     */
    @Suppress("DEPRECATION") // allNetworks: fine for a one-off read.
    private fun underlyingTransport(): String {
        val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return "unknown"
        val usable = manager.allNetworks
            .mapNotNull { manager.getNetworkCapabilities(it) }
            .filter {
                it.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                    !it.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
            }
        return when {
            usable.any { it.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) } -> "wifi"
            usable.any { it.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) } -> "cellular"
            else -> "unknown"
        }
    }

    /**
     * MCC+MNC of the mobile network carrying data -- "43235" for Irancell,
     * "43211" for MCI -- or null. The data SIM, not the default one: on a
     * dual-SIM phone the default instance answers for the voice subscription.
     */
    private fun mobileOperator(): String? {
        val base = context.getSystemService(Context.TELEPHONY_SERVICE)
            as? android.telephony.TelephonyManager ?: return null
        val dataSub = android.telephony.SubscriptionManager.getDefaultDataSubscriptionId()
        val telephony = if (dataSub != android.telephony.SubscriptionManager.INVALID_SUBSCRIPTION_ID) {
            base.createForSubscriptionId(dataSub)
        } else {
            base
        }
        // "" when not registered: null, so "no operator" means one thing.
        val code = telephony.networkOperator ?: return null
        return if (code.length in 5..6 && code.all { it.isDigit() }) code else null
    }

    private fun startWatchingNetwork() {
        if (networkCallback != null) return
        val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
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
        val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        try {
            manager?.unregisterNetworkCallback(callback)
        } catch (_: IllegalArgumentException) {
            // Already gone.
        }
    }

    /** The transport as one word: Dart only needs to know it changed. */
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
}

/**
 * A Flutter engine with no screen, for the Quick Settings tile.
 *
 * Connecting is Dart's work -- picking a server, verifying the tunnel -- and
 * the only engine used to be the one MainActivity made, so a tap on the tile
 * had to open the app. Other VPN apps connect from the tile without showing
 * anything, and Meysam asked for the same on 2026-11-09.
 *
 * It runs the app's own `main()`. With no view attached, no widget is built;
 * the tile's handlers in `main()` work without one. Cached under [ID] so that
 * opening the app afterwards attaches the screen to this same engine
 * (MainActivity.provideFlutterEngine) instead of starting a second copy of
 * the tunnel logic beside it.
 */
object TileEngine {
    const val ID = "verna_main"

    fun ensure(context: Context): FlutterEngine {
        val cache = io.flutter.embedding.engine.FlutterEngineCache.getInstance()
        cache.get(ID)?.let { return it }
        val app = context.applicationContext
        val engine = FlutterEngine(app)
        EngineChannels(app).register(engine)
        engine.dartExecutor.executeDartEntrypoint(
            io.flutter.embedding.engine.dart.DartExecutor.DartEntrypoint.createDefault(),
        )
        cache.put(ID, engine)
        return engine
    }

    fun cached(): FlutterEngine? =
        io.flutter.embedding.engine.FlutterEngineCache.getInstance().get(ID)
}
