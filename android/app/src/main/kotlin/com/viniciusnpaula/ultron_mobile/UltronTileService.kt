package com.viniciusnpaula.ultron_mobile

import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

class UltronTileService : TileService() {
    companion object {
        const val ACTION_TILE_LAUNCH = "com.viniciusnpaula.ultron_mobile.ACTION_TILE_LAUNCH"
        const val EXTRA_TILE_ACTION = "tile_action"
    }

    override fun onStartListening() {
        super.onStartListening()
        qsTile?.apply {
            state = Tile.STATE_INACTIVE
            label = "U.L.T.R.O.N."
            updateTile()
        }
    }

    override fun onClick() {
        super.onClick()
        // Never unlocks or opens microphone natively: always routes through
        // MainActivity -> AuthScreen, and Flutter consumes the pending action
        // only after AuthGate.isAuthenticated == true.
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            action = ACTION_TILE_LAUNCH
            putExtra(EXTRA_TILE_ACTION, "listen_voice")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val pendingIntent = PendingIntent.getActivity(
                this,
                4102,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            startActivityAndCollapse(pendingIntent)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(launchIntent)
        }
    }
}
