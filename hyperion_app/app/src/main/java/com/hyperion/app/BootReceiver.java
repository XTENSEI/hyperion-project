package com.hyperion.app;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

public class BootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        if (Intent.ACTION_BOOT_COMPLETED.equals(intent.getAction())) {
            // Start service on boot
            Intent serviceIntent = new Intent(context, HyperionService.class);
            context.startService(serviceIntent);
        }
    }
}
