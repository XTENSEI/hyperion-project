package com.hyperion.app;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.AsyncTask;
import android.os.Bundle;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.BaseAdapter;
import android.widget.Button;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ListView;
import android.widget.ProgressBar;
import android.widget.Switch;
import android.widget.TextView;
import android.widget.Toast;

import androidx.swiperefreshlayout.widget.SwipeRefreshLayout;

import com.google.android.material.appbar.CollapsingToolbarLayout;
import com.google.android.material.floatingactionbutton.FloatingActionButton;
import com.google.android.material.navigation.NavigationView;
import com.google.android.material.snackbar.Snackbar;

import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.DataOutputStream;
import java.io.File;
import java.io.IOException;
import java.io.InputStreamReader;
import java.util.ArrayList;
import java.util.List;

public class MainActivity extends Activity {

    private static final String MODULE_PATH = "/data/adb/modules/hyperion_project";
    private static final String CONFIG_DIR = "/data/adb/.config/hyperion";
    private static final String BIN_PATH = MODULE_PATH + "/system/bin/hyperion";
    
    private SharedPreferences prefs;
    private boolean isModuleInstalled = false;
    private boolean isServiceRunning = false;
    
    // UI Elements
    private TextView tvModuleStatus, tvServiceStatus, tvCpuFreq, tvCpuTemp, tvBattery;
    private TextView tvRamUsage, tvGpuFreq, tvProfile;
    private Switch swGameBooster, swAI, swBypass;
    private ProgressBar pbLoading;
    private LinearLayout layoutQuickToggle;
    private SwipeRefreshLayout swipeRefresh;
    
    private ListView lvProfiles;
    private ProfileAdapter profileAdapter;
    private List<ProfileItem> profileList;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);
        
        prefs = getSharedPreferences("hyperion_prefs", MODE_PRIVATE);
        
        initViews();
        checkModuleStatus();
        loadProfiles();
        
        // Auto refresh
        swipeRefresh.setOnRefreshListener(this::refreshData);
        refreshData();
    }

    private void initViews() {
        // Status
        tvModuleStatus = findViewById(R.id.tv_module_status);
        tvServiceStatus = findViewById(R.id.tv_service_status);
        
        // Stats
        tvCpuFreq = findViewById(R.id.tv_cpu_freq);
        tvCpuTemp = findViewById(R.id.tv_cpu_temp);
        tvBattery = findViewById(R.id.tv_battery);
        tvRamUsage = findViewById(R.id.tv_ram_usage);
        tvGpuFreq = findViewById(R.id.tv_gpu_freq);
        tvProfile = findViewById(R.id.tv_current_profile);
        
        // Toggles
        swGameBooster = findViewById(R.id.sw_game_booster);
        swAI = findViewById(R.id.sw_ai);
        swBypass = findViewById(R.id.sw_bypass);
        
        // Other
        pbLoading = findViewById(R.id.pb_loading);
        swipeRefresh = findViewById(R.id.swipe_refresh);
        lvProfiles = findViewById(R.id.lv_profiles);
        
        // Button clicks
        findViewById(R.id.btn_settings).setOnClickListener(v -> startActivity(new Intent(this, SettingsActivity.class)));
        findViewById(R.id.fab_refresh).setOnClickListener(v -> refreshData());
        
        swGameBooster.setOnCheckedChangeListener((btn, checked) -> {
            if (isModuleInstalled) {
                execCommand(checked ? "boost" : "unboost");
                showToast("Game Booster " + (checked ? "ON" : "OFF"));
            }
        });
        
        swAI.setOnCheckedChangeListener((btn, checked) -> {
            prefs.edit().putBoolean("ai_enabled", checked).apply();
            execCommand("ai " + (checked ? "enable" : "disable"));
            showToast("AI Mode " + (checked ? "ON" : "OFF"));
        });
        
        swBypass.setOnCheckedChangeListener((btn, checked) -> {
            execCommand("bypass " + (checked ? "enable" : "disable"));
            showToast("Bypass Charging " + (checked ? "ON" : "OFF"));
        });
    }

    private void checkModuleStatus() {
        new AsyncTask<Void, Void, Boolean>() {
            @Override
            protected Boolean doInBackground(Void... params) {
                File modPath = new File(MODULE_PATH);
                File binPath = new File(BIN_PATH);
                return modPath.exists() && binPath.exists();
            }
            
            @Override
            protected void onPostExecute(Boolean result) {
                isModuleInstalled = result;
                tvModuleStatus.setText(result ? "✓ Installed" : "✗ Not Installed");
                tvModuleStatus.setTextColor(getColor(result ? R.color.green : R.color.red));
                
                // Check service
                isServiceRunning = execCommandSilent("pgrep -x hyperiond").contains("hyperion");
                tvServiceStatus.setText(isServiceRunning ? "✓ Running" : "✗ Stopped");
                tvServiceStatus.setTextColor(getColor(isServiceRunning ? R.color.green : R.color.orange));
            }
        }.execute();
    }

    private void loadProfiles() {
        profileList = new ArrayList<>();
        profileList.add(new ProfileItem("Gaming", "🎮", "Maximum performance for games", "gaming"));
        profileList.add(new ProfileItem("Performance", "🚀", "High performance balanced", "performance"));
        profileList.add(new ProfileItem("Balanced", "⚖️", "Default balanced profile", "balanced"));
        profileList.add(new ProfileItem("Battery", "🔋", "Extended battery life", "battery"));
        profileList.add(new ProfileItem("Powersave", "💤", "Maximum battery saving", "powersave"));
        
        profileAdapter = new ProfileAdapter(this, profileList);
        lvProfiles.setAdapter(profileAdapter);
        
        // Load saved profile
        String savedProfile = prefs.getString("current_profile", "balanced");
        tvProfile.setText("Current: " + savedProfile.substring(0, 1).toUpperCase() + savedProfile.substring(1));
    }

    private void refreshData() {
        if (!isModuleInstalled) {
            swipeRefresh.setRefreshing(false);
            return;
        }
        
        new AsyncTask<Void, Void, JSONObject>() {
            @Override
            protected JSONObject doInBackground(Void... params) {
                JSONObject data = new JSONObject();
                try {
                    // CPU Info
                    String cpuFreq = execCommandSilent("cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null");
                    if (!cpuFreq.isEmpty()) {
                        data.put("cpu_freq", String.valueOf(Integer.parseInt(cpuFreq.trim()) / 1000));
                    }
                    
                    // Temperature
                    String temp = execCommandSilent("cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null");
                    if (!temp.isEmpty()) {
                        data.put("cpu_temp", String.valueOf(Integer.parseInt(temp.trim()) / 1000));
                    }
                    
                    // Battery
                    String battery = execCommandSilent("cat /sys/class/power_supply/battery/capacity 2>/dev/null");
                    if (!battery.isEmpty()) {
                        data.put("battery", battery.trim());
                    }
                    
                    // RAM
                    String memInfo = execCommandSilent("cat /proc/meminfo");
                    if (!memInfo.isEmpty()) {
                        String[] lines = memInfo.split("\n");
                        long total = 0, available = 0;
                        for (String line : lines) {
                            if (line.startsWith("MemTotal:")) {
                                total = Long.parseLong(line.split("\\s+")[1]);
                            }
                            if (line.startsWith("MemAvailable:")) {
                                available = Long.parseLong(line.split("\\s+")[1]);
                            }
                        }
                        long used = total - available;
                        int percent = (int) ((used * 100) / total);
                        data.put("ram_usage", percent);
                    }
                    
                    // GPU
                    String gpuFreq = execCommandSilent("cat /sys/class/kgsl/kgsl-3d0/gpuclk 2>/dev/null");
                    if (!gpuFreq.isEmpty()) {
                        data.put("gpu_freq", String.valueOf(Integer.parseInt(gpuFreq.trim()) / 1000000));
                    }
                    
                } catch (Exception e) {
                    e.printStackTrace();
                }
                return data;
            }
            
            @Override
            protected void onPostExecute(JSONObject result) {
                try {
                    if (result.has("cpu_freq")) {
                        tvCpuFreq.setText(result.getString("cpu_freq") + " MHz");
                    }
                    if (result.has("cpu_temp")) {
                        tvCpuTemp.setText(result.getString("cpu_temp") + "°C");
                    }
                    if (result.has("battery")) {
                        tvBattery.setText(result.getString("battery") + "%");
                    }
                    if (result.has("ram_usage")) {
                        tvRamUsage.setText(result.getString("ram_usage") + "%");
                    }
                    if (result.has("gpu_freq")) {
                        tvGpuFreq.setText(result.getString("gpu_freq") + " MHz");
                    }
                } catch (Exception e) {
                    e.printStackTrace();
                }
                swipeRefresh.setRefreshing(false);
            }
        }.execute();
    }

    private void applyProfile(String profile) {
        new AsyncTask<Void, Void, Void>() {
            @Override
            protected void onPreExecute() {
                pbLoading.setVisibility(View.VISIBLE);
            }
            
            @Override
            protected Void doInBackground(Void... params) {
                execCommand("profile " + profile);
                prefs.edit().putString("current_profile", profile).apply();
                return null;
            }
            
            @Override
            protected void onPostExecute(Void result) {
                pbLoading.setVisibility(View.GONE);
                tvProfile.setText("Current: " + profile.substring(0, 1).toUpperCase() + profile.substring(1));
                showToast("Profile: " + profile.toUpperCase());
            }
        }.execute();
    }

    // Command execution
    private String execCommand(String cmd) {
        return execCommandSilent(cmd);
    }
    
    private String execCommandSilent(String cmd) {
        try {
            Process process = Runtime.getRuntime().exec("su -c " + cmd);
            BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream()));
            StringBuilder sb = new StringBuilder();
            String line;
            while ((line = reader.readLine()) != null) {
                sb.append(line).append("\n");
            }
            process.waitFor();
            return sb.toString().trim();
        } catch (Exception e) {
            return "";
        }
    }

    private void showToast(String msg) {
        Toast.makeText(this, msg, Toast.LENGTH_SHORT).show();
    }

    // Profile Adapter
    private class ProfileAdapter extends BaseAdapter {
        private Context context;
        private List<ProfileItem> items;
        
        ProfileAdapter(Context context, List<ProfileItem> items) {
            this.context = context;
            this.items = items;
        }
        
        @Override
        public int getCount() { return items.size(); }
        
        @Override
        public Object getItem(int pos) { return items.get(pos); }
        
        @Override
        public long getItemId(int pos) { return pos; }
        
        @Override
        public View getView(int pos, View convertView, ViewGroup parent) {
            View v = LayoutInflater.from(context).inflate(R.layout.item_profile, parent, false);
            
            TextView tvName = v.findViewById(R.id.tv_profile_name);
            TextView tvDesc = v.findViewById(R.id.tv_profile_desc);
            TextView tvIcon = v.findViewById(R.id.tv_profile_icon);
            Button btnApply = v.findViewById(R.id.btn_apply);
            
            ProfileItem item = items.get(pos);
            tvName.setText(item.name);
            tvDesc.setText(item.desc);
            tvIcon.setText(item.icon);
            
            btnApply.setOnClickListener(v1 -> applyProfile(item.profile));
            
            return v;
        }
    }
    
    private class ProfileItem {
        String name, icon, desc, profile;
        
        ProfileItem(String name, String icon, String desc, String profile) {
            this.name = name;
            this.icon = icon;
            this.desc = desc;
            this.profile = profile;
        }
    }
}
