// package com.example.godotgame; // Change this to your app's package name
package com.example.godotgame;

import android.bluetooth.BluetoothAdapter;
import android.content.Context;
import androidx.annotation.NonNull;
import org.godotengine.godot.GodotPlugin;
import org.godotengine.godot.Godot;

public class BluetoothPlugin extends GodotPlugin {

    public BluetoothPlugin(Godot godot) {
        super(godot);
    }

    @NonNull
    @Override
    public String getPluginName() {
        return "BluetoothPlugin";
    }

    public String getBluetoothName() {
        BluetoothAdapter bluetoothAdapter = BluetoothAdapter.getDefaultAdapter();
        if (bluetoothAdapter != null) {
            return bluetoothAdapter.getName(); // ✅ Returns device's Bluetooth name
        }
        return "Unknown Device";
    }
}
