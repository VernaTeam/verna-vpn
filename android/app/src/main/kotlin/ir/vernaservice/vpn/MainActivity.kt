package ir.vernaservice.vpn

import android.content.Context
import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import java.lang.ref.WeakReference

/**
 * The screen. What Dart needs from Android lives in [EngineChannels], so the
 * same answers reach an engine the Quick Settings tile started with no screen.
 */
class MainActivity : FlutterActivity() {

    /** Set only for an engine this activity made; the tile's engine outlives it. */
    private var ownChannels: EngineChannels? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        EngineChannels.activity = WeakReference(this)
        super.onCreate(savedInstanceState)
    }

    /**
     * The tile's engine, when it is running: one copy of the tunnel logic, not
     * two side by side watching the same service. Null otherwise, and Flutter
     * makes this activity its own engine as before.
     */
    override fun provideFlutterEngine(context: Context): FlutterEngine? = TileEngine.cached()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The tile's engine already has its channels, registered with the
        // application context so they survive this activity.
        if (flutterEngine === TileEngine.cached()) return
        val channels = EngineChannels(this)
        channels.register(flutterEngine)
        ownChannels = channels
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        ownChannels?.dispose()
        ownChannels = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    // Both, and only once the activity is in front, because the connect may
    // need to show Android's consent dialog. A tap on the tile with this app
    // already on screen is a new intent with no resume at all.
    override fun onResume() {
        super.onResume()
        announceTileRequest()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        announceTileRequest()
    }

    /** Only says one is waiting. Dart takes it, so two of these start one connect. */
    private fun announceTileRequest() {
        if (TileBridge.hasConnectRequest()) {
            TileBridge.channel?.invokeMethod("connectRequested", null)
        }
    }

    override fun onDestroy() {
        if (EngineChannels.activity?.get() === this) EngineChannels.activity = null
        super.onDestroy()
    }
}
